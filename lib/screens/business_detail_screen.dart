import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../utils/helpers.dart';
import '../utils/single_flight_guard.dart';
import '../services/booking_visibility_service.dart';
import '../services/booking_messaging_service.dart';
import '../services/auth_required_action.dart';
import '../services/analytics_service.dart';
import '../services/local_link_share_service.dart';
import '../models/business_opening_hours.dart';
import '../services/business_activation_policy.dart';
import '../widgets/business_contact_actions.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_image.dart';
import '../widgets/local_link_section_header.dart';
import '../widgets/local_link_states.dart';
import '../widgets/local_link_surface_card.dart';

import 'availability_detail_screen.dart';
import 'booking_conversation_screen.dart';
import 'listing_claim_request_screen.dart';

double _asDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _asInt(dynamic value) {
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _isCurrentUserBusinessOwner(Map<String, dynamic> businessData) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid.isEmpty) return false;

  bool matches(Object? value) => value?.toString() == uid;

  bool containsUser(Object? value) {
    if (value is Iterable) {
      return value.map((item) => item.toString()).contains(uid);
    }
    return false;
  }

  return matches(businessData['ownerId']) ||
      matches(businessData['businessOwnerId']) ||
      matches(businessData['ownerUid']) ||
      matches(businessData['claimedBy']) ||
      _creatorCanManageBusiness(businessData, uid) ||
      containsUser(businessData['ownerIds']) ||
      containsUser(businessData['adminUserIds']);
}

bool _creatorCanManageBusiness(Map<String, dynamic> businessData, String uid) {
  if (businessData['createdBy']?.toString() != uid) return false;
  final moderatorSeeded = businessData['createdByModerator'] == true;
  final claimed =
      businessData['isClaimed'] == true ||
      businessData['listingOwnershipStatus']?.toString() == 'claimed';
  return !(moderatorSeeded && claimed);
}

class BusinessDetailScreen extends StatefulWidget {
  final String businessId;
  final String? initialServiceId;

  const BusinessDetailScreen({
    super.key,
    required this.businessId,
    this.initialServiceId,
  });

  @override
  State<BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends State<BusinessDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _serviceKeys = {};
  bool _didScrollToInitialService = false;
  bool _loggedView = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleInitialServiceScroll() {
    final serviceId = widget.initialServiceId?.trim();
    if (_didScrollToInitialService || serviceId == null || serviceId.isEmpty) {
      return;
    }

    _didScrollToInitialService = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _serviceKeys[serviceId]?.currentContext;
      if (context == null) return;

      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .get(),

      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: LocalLinkLoadingState(label: 'Loading business'),
          );
        }

        final businessData =
            snapshot.data!.data() as Map<String, dynamic>? ?? {};

        final businessName = safeText(businessData['businessName'], 'Business');

        final category = safeText(businessData['category'], 'No category');
        if (!_loggedView) {
          _loggedView = true;
          LocalLinkAnalytics.instance.discoveryView(
            eventName: 'business_view',
            source: widget.initialServiceId == null ? 'other' : 'service',
            category: category,
          );
        }

        final bio = safeText(businessData['bio'], '');

        final address = safeText(businessData['address'], '');

        final serviceArea = safeText(businessData['serviceArea'], '');

        final openingHours = BusinessOpeningHours.displayText(businessData);

        final logoUrl = safeText(businessData['logoUrl'], '');

        final verified =
            businessData['stripeChargesEnabled'] == true ||
            businessData['verified'] == true;

        final rating = _asDouble(
          businessData['rating'] ?? businessData['averageRating'],
        );

        final reviewCount = _asInt(businessData['reviewCount']);

        final completedBookings = _asInt(businessData['completedBookings']);

        final responseTime = safeText(
          businessData['typicalResponseTime'] ?? businessData['responseTime'],
          '',
        );

        final insurance = safeText(businessData['insurance'], '');

        final insuranceVerified = businessData['insuranceVerified'] == true;

        final paymentMethods = resolvePaymentMethods(businessData);

        final photoURLs = businessPhotoUrls(businessData);

        final coverPhoto = businessCoverImageUrl(businessData);

        final galleryPhotoURLs = photoURLs
            .where((url) => url.trim() != coverPhoto.trim())
            .toList();

        final isModeratorSeeded = businessData['createdByModerator'] == true;
        final isUnclaimedListing =
            isModeratorSeeded &&
            businessData['listingOwnershipStatus'] != 'claimed';

        return Scaffold(
          backgroundColor: AppColors.background,

          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // =====================================
              // HERO
              // =====================================
              SliverAppBar(
                expandedHeight: 300,

                pinned: true,

                backgroundColor: AppColors.serviceGreen,

                foregroundColor: Colors.white,

                actions: [
                  IconButton(
                    icon: const Icon(Icons.ios_share_outlined),
                    tooltip: 'Share',
                    onPressed: () async {
                      try {
                        await LocalLinkShareService().shareItem(
                          item: LocalLinkShareItem(
                            type: LocalLinkShareItemType.business,
                            id: widget.businessId,
                            data: {...businessData, 'coverPhoto': coverPhoto},
                          ),
                        );
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Sharing could not be started.'),
                          ),
                        );
                      }
                    },
                  ),
                ],

                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,

                    children: [
                      // IMAGE
                      if (coverPhoto.isNotEmpty)
                        LocalLinkImage(
                          imageUrl: coverPhoto,
                          aspectRatio: 16 / 9,
                          fallbackIcon: Icons.storefront_outlined,
                          accentColor: AppColors.serviceGreen,
                          semanticLabel: businessName,
                        )
                      else
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.serviceGreen,

                                Color(0xFF0F6A44),
                              ],
                            ),
                          ),

                          child: const Center(
                            child: Icon(
                              Icons.storefront,

                              color: Colors.white,

                              size: 70,
                            ),
                          ),
                        ),

                      // OVERLAY
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,

                            end: Alignment.bottomCenter,

                            colors: [
                              Colors.black.withValues(alpha: 0.15),

                              Colors.black.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),

                      // TITLE AREA
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 24,

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),

                              decoration: BoxDecoration(
                                color: Colors.black87,

                                borderRadius: BorderRadius.circular(999),
                              ),

                              child: Text(
                                category,

                                style: const TextStyle(
                                  color: Colors.white,

                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            Row(
                              children: [
                                if (logoUrl.isNotEmpty) ...[
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: LocalLinkImage(
                                      imageUrl: logoUrl,
                                      aspectRatio: 1,
                                      fallbackIcon: Icons.storefront_outlined,
                                      accentColor: AppColors.serviceGreen,
                                      semanticLabel: '$businessName logo',
                                    ),
                                  ),

                                  const SizedBox(width: 10),
                                ],

                                Expanded(
                                  child: Text(
                                    businessName,

                                    style: const TextStyle(
                                      color: Colors.white,

                                      fontSize: 30,

                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),

                                if (verified)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),

                                    decoration: BoxDecoration(
                                      color: AppColors.success,

                                      borderRadius: BorderRadius.circular(999),
                                    ),

                                    child: const Row(
                                      children: [
                                        Icon(
                                          Icons.verified,

                                          color: Colors.white,

                                          size: 16,
                                        ),

                                        SizedBox(width: 4),

                                        Text(
                                          'Payments Verified',

                                          style: TextStyle(
                                            color: Colors.white,

                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),

                            if (reviewCount > 0) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Color(0xFFFFC857),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${rating.toStringAsFixed(1)} ($reviewCount reviews)',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            if (address.trim().isNotEmpty) ...[
                              const SizedBox(height: 10),

                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,

                                    color: Colors.white70,

                                    size: 18,
                                  ),

                                  const SizedBox(width: 6),

                                  Expanded(
                                    child: Text(
                                      address,

                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // =====================================
              // CONTENT
              // =====================================
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('businesses')
                            .doc(widget.businessId)
                            .collection('services')
                            .where('isActive', isEqualTo: true)
                            .limit(1)
                            .snapshots(),
                        builder: (context, snapshot) {
                          final hasServices =
                              snapshot.hasData &&
                              snapshot.data!.docs.isNotEmpty;
                          final canUseServices =
                              hasServices &&
                              BusinessActivationPolicy.listingLive(
                                businessData,
                              ) &&
                              BusinessActivationPolicy.hasClaimedOwner(
                                businessData,
                              );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (canUseServices) ...[
                                LocalLinkButton(
                                  label: 'View services and booking options',
                                  icon: Icons.handyman_outlined,
                                  expand: true,
                                  onPressed: () {
                                    final serviceId =
                                        snapshot.data!.docs.first.id;
                                    final destination =
                                        _serviceKeys[serviceId]?.currentContext;
                                    if (destination != null) {
                                      Scrollable.ensureVisible(
                                        destination,
                                        duration: const Duration(
                                          milliseconds: 450,
                                        ),
                                        alignment: 0.1,
                                      );
                                    } else {
                                      _scrollController.animateTo(
                                        _scrollController
                                            .position
                                            .maxScrollExtent,
                                        duration: const Duration(
                                          milliseconds: 450,
                                        ),
                                        curve: Curves.easeOut,
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),
                              ],
                              BusinessContactActions(
                                businessData: businessData,
                              ),
                              _FavoriteBusinessIconButton(
                                businessId: widget.businessId,
                                businessName: businessName,
                                category: category,
                              ),
                            ],
                          );
                        },
                      ),

                      if (isUnclaimedListing) ...[
                        const SizedBox(height: 14),
                        _UnclaimedBusinessCard(
                          businessId: widget.businessId,
                          businessName: businessName,
                        ),
                      ],

                      const SizedBox(height: LocalLinkSpacing.lg),

                      _BusinessTrustSection(
                        verified: verified,
                        rating: rating,
                        reviewCount: reviewCount,
                        completedBookings: completedBookings,
                        responseTime: responseTime,
                        paymentMethods: paymentMethods,
                        insurance: insurance,
                        insuranceVerified: insuranceVerified,
                      ),

                      // =================================
                      // ABOUT
                      // =================================
                      if (bio.trim().isNotEmpty) ...[
                        const SizedBox(height: LocalLinkSpacing.xl),

                        const LocalLinkSectionHeader(title: 'About'),

                        const SizedBox(height: LocalLinkSpacing.sm),

                        LocalLinkSurfaceCard(
                          elevated: false,
                          padding: const EdgeInsets.all(LocalLinkSpacing.md),
                          child: Text(bio, style: LocalLinkTextStyles.body),
                        ),
                      ],

                      if (galleryPhotoURLs.isNotEmpty) ...[
                        const SizedBox(height: 24),

                        _PhotoGallery(photoURLs: galleryPhotoURLs),
                      ],

                      if (openingHours.trim().isNotEmpty ||
                          serviceArea.trim().isNotEmpty) ...[
                        const SizedBox(height: 24),

                        _BusinessInfoCard(
                          openingHours: openingHours,
                          serviceArea: serviceArea,
                          paymentMethods: paymentMethods,
                        ),
                      ],

                      // =================================
                      // SERVICES HEADER
                      // =================================
                      const SizedBox(height: LocalLinkSpacing.xxl),

                      const LocalLinkSectionHeader(
                        title: 'Services',
                        subtitle: 'Explore what this business offers.',
                      ),

                      const SizedBox(height: LocalLinkSpacing.md),

                      // =================================
                      // SERVICES
                      // =================================
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('businesses')
                            .doc(widget.businessId)
                            .collection('services')
                            .where('isActive', isEqualTo: true)
                            .snapshots(),

                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const Text(
                              'We could not load services just now. You can use the contact details above if available.',
                            );
                          }
                          if (!snapshot.hasData) {
                            return const LocalLinkLoadingState(
                              label: 'Loading services',
                            );
                          }

                          final services = snapshot.data?.docs ?? [];

                          if (!BusinessActivationPolicy.listingLive(
                                businessData,
                              ) ||
                              !BusinessActivationPolicy.hasClaimedOwner(
                                businessData,
                              )) {
                            return const Text(
                              'Services and LocalLink enquiries are not available for this listing yet.',
                            );
                          }

                          if (services.isEmpty) {
                            return const LocalLinkEmptyState(
                              icon: Icons.handyman_outlined,
                              title: 'No services yet',
                              message:
                                  'This business has not listed services. Use the contact details above if available, or save this page for later.',
                            );
                          }

                          _scheduleInitialServiceScroll();

                          return Column(
                            children: services.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final key = _serviceKeys.putIfAbsent(
                                doc.id,
                                () => GlobalKey(),
                              );

                              return KeyedSubtree(
                                key: key,
                                child: _ServiceCard(
                                  businessId: widget.businessId,

                                  businessName: businessName,

                                  businessData: businessData,

                                  serviceId: doc.id,

                                  serviceData: data,

                                  highlighted:
                                      doc.id == widget.initialServiceId,
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =====================================================
// TRUST BADGE
// =====================================================

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.sm,
        vertical: LocalLinkSpacing.xs,
      ),

      decoration: BoxDecoration(
        color: AppColors.serviceGreen.withValues(alpha: 0.09),

        borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
        border: Border.all(
          color: AppColors.serviceGreen.withValues(alpha: 0.12),
        ),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(icon, size: 17, color: AppColors.serviceGreen),

          const SizedBox(width: LocalLinkSpacing.xxs),

          Text(
            label,

            style: LocalLinkTextStyles.label.copyWith(
              color: AppColors.charcoal,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessTrustSection extends StatelessWidget {
  const _BusinessTrustSection({
    required this.verified,
    required this.rating,
    required this.reviewCount,
    required this.completedBookings,
    required this.responseTime,
    required this.paymentMethods,
    required this.insurance,
    required this.insuranceVerified,
  });

  final bool verified;
  final double rating;
  final int reviewCount;
  final int completedBookings;
  final String responseTime;
  final List<String> paymentMethods;
  final String insurance;
  final bool insuranceVerified;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      if (verified)
        const _TrustBadge(icon: Icons.verified, label: 'Verified Business'),
      if (reviewCount > 0)
        _TrustBadge(
          icon: Icons.star_rounded,
          label: '${rating.toStringAsFixed(1)} from $reviewCount reviews',
        ),
      if (completedBookings > 0)
        _TrustBadge(
          icon: Icons.check_circle_outline,
          label: '$completedBookings completed bookings',
        ),
      if (responseTime.trim().isNotEmpty)
        _TrustBadge(
          icon: Icons.schedule_outlined,
          label: 'Usually replies $responseTime',
        ),
      if (paymentMethods.contains('stripe'))
        const _TrustBadge(icon: Icons.credit_card, label: 'Card & Apple Pay'),
      if (paymentMethods.contains('cash'))
        const _TrustBadge(icon: Icons.payments, label: 'Cash Accepted'),
      if (paymentMethods.contains('bank_transfer'))
        const _TrustBadge(
          icon: Icons.account_balance_outlined,
          label: 'Bank Transfer',
        ),
      if (insuranceVerified)
        const _TrustBadge(
          icon: Icons.shield_outlined,
          label: 'Insurance Verified',
        )
      else if (insurance.trim().isNotEmpty)
        _TrustBadge(icon: Icons.shield_outlined, label: insurance),
    ];

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LocalLinkSectionHeader(title: 'Trust'),
        const SizedBox(height: LocalLinkSpacing.sm),
        Wrap(
          spacing: LocalLinkSpacing.xs,
          runSpacing: LocalLinkSpacing.xs,
          children: items,
        ),
      ],
    );
  }
}

class _FavoriteBusinessIconButton extends StatelessWidget {
  const _FavoriteBusinessIconButton({
    required this.businessId,
    required this.businessName,
    required this.category,
  });

  final String businessId;
  final String businessName;
  final String category;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const SizedBox.shrink();
    }

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('savedBusinesses')
        .doc(businessId);

    return StreamBuilder<DocumentSnapshot>(
      stream: ref.snapshots(),
      builder: (context, snapshot) {
        final saved = snapshot.data?.exists == true;

        return Tooltip(
          message: saved ? 'Saved Business' : 'Save Business',
          child: IconButton.filledTonal(
            onPressed: () async {
              if (saved) {
                await ref.delete();
              } else {
                await ref.set({
                  'businessId': businessId,
                  'businessName': businessName,
                  'category': category,
                  'savedAt': FieldValue.serverTimestamp(),
                });
                await LocalLinkAnalytics.instance.businessSaved(
                  source: 'business_detail',
                  category: category,
                );
              }
            },
            icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
            color: AppColors.serviceGreen,
          ),
        );
      },
    );
  }
}

class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({required this.photoURLs});

  final List<String> photoURLs;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photoURLs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 124,
              height: 92,
              child: LocalLinkImage(
                imageUrl: photoURLs[index],
                aspectRatio: 124 / 92,
                fallbackIcon: Icons.image_not_supported_outlined,
                accentColor: AppColors.serviceGreen,
                semanticLabel: 'Business photo',
              ),
            ),
          );
        },
      ),
    );
  }
}

class _UnclaimedBusinessCard extends StatelessWidget {
  const _UnclaimedBusinessCard({
    required this.businessId,
    required this.businessName,
  });

  final String businessId;
  final String businessName;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      color: AppColors.primary.withValues(alpha: 0.07),
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unclaimed listing',
            style: LocalLinkTextStyles.label.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: LocalLinkSpacing.xxs),
          Text(
            'This business has not yet claimed or verified its LocalLink page.',
            style: LocalLinkTextStyles.secondary,
          ),
          const SizedBox(height: LocalLinkSpacing.sm),
          LocalLinkButton(
            label: 'Claim this business',
            icon: Icons.verified_user_outlined,
            variant: LocalLinkButtonVariant.secondary,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ListingClaimRequestScreen(
                    listingType: 'business',
                    listingId: businessId,
                    listingTitle: businessName,
                  ),
                ),
              );
            },
            expand: true,
          ),
        ],
      ),
    );
  }
}

class _BusinessInfoCard extends StatelessWidget {
  const _BusinessInfoCard({
    required this.openingHours,
    required this.serviceArea,
    required this.paymentMethods,
  });

  final String openingHours;
  final String serviceArea;
  final List<String> paymentMethods;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Column(
        children: [
          if (openingHours.trim().isNotEmpty)
            _InfoLine(
              icon: Icons.schedule,
              label: 'Opening hours',
              value: openingHours,
            ),
          if (serviceArea.trim().isNotEmpty)
            _InfoLine(
              icon: Icons.map_outlined,
              label: 'Service area',
              value: serviceArea,
            ),
          _InfoLine(
            icon: Icons.payments_outlined,
            label: 'Payment',
            value: paymentMethods.isEmpty
                ? 'Ask business'
                : paymentMethods.map(paymentMethodLabel).join(', '),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.serviceGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// SERVICE CARD
// =====================================================

class _ServiceCard extends StatelessWidget {
  final String businessId;
  final String businessName;
  final Map<String, dynamic> businessData;
  final String serviceId;

  final Map<String, dynamic> serviceData;

  final bool highlighted;

  const _ServiceCard({
    required this.businessId,
    required this.businessName,
    required this.businessData,
    required this.serviceId,
    required this.serviceData,
    this.highlighted = false,
  });

  Future<void> _askQuestion(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.isAnonymous) {
      await AuthRequiredAction.run(
        context,
        action: () => _askQuestion(context),
      );
      return;
    }

    final message = await showDialog<String>(
      context: context,
      builder: (_) => const _ServiceQuestionDialog(),
    );

    if (message == null || message.isEmpty) {
      return;
    }

    try {
      if (kDebugMode) {
        debugPrint(
          'Service enquiry submit start '
          'uid=${user.uid} businessId=$businessId serviceId=$serviceId '
          'messageLength=${message.length}',
        );
      }

      final conversationId = await BookingMessagingService()
          .createServiceEnquiry(
            businessId: businessId,
            serviceId: serviceId,
            text: message,
          );
      await LocalLinkAnalytics.instance.messageStarted(
        source: 'business_detail',
        type: 'service_enquiry',
      );

      if (kDebugMode) {
        debugPrint(
          'Service enquiry submit succeeded conversationId=$conversationId',
        );
      }

      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BookingConversationScreen(
            conversationId: conversationId,
            viewerType: 'customer',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Service enquiry submit failed '
          'businessId=$businessId serviceId=$serviceId error=$error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }

      if (!context.mounted) return;

      final message =
          error.code == 'failed-precondition' &&
              (error.message ?? '').contains(
                'Businesses cannot start customer conversations',
              )
          ? 'Use a customer account to enquire with this business.'
          : 'Your question could not be sent. Please try again.';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Service enquiry submit failed '
          'businessId=$businessId serviceId=$serviceId error=$error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your question could not be sent. Please try again.'),
        ),
      );
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _liveAvailabilityStream() {
    return FirebaseFirestore.instance
        .collection('availabilityPosts')
        .where('businessId', isEqualTo: businessId)
        .where('serviceId', isEqualTo: serviceId)
        .where('isActive', isEqualTo: true)
        .where('status', isEqualTo: 'live')
        .limit(1)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final name = safeText(serviceData['name'], 'Service');

    final details = safeText(serviceData['details'], '');

    final price = formatPrice(serviceData['price']);

    final duration = serviceData['durationMinutes'];

    final imageUrl = safeText(serviceData['imageUrl'], '');

    final isOwnBusiness = _isCurrentUserBusinessOwner(businessData);

    return Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.md),
      child: LocalLinkSurfaceCard(
        elevated: highlighted,
        color: highlighted
            ? AppColors.serviceGreen.withValues(alpha: 0.06)
            : AppColors.card,
        padding: const EdgeInsets.all(LocalLinkSpacing.md),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            if (imageUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
                child: LocalLinkImage(
                  imageUrl: imageUrl,
                  aspectRatio: 16 / 9,
                  fallbackIcon: Icons.handyman_outlined,
                  accentColor: AppColors.serviceGreen,
                  semanticLabel: 'Service photo',
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LocalLinkTextStyles.cardTitle.copyWith(fontSize: 20),
                  ),
                ),
                const SizedBox(width: LocalLinkSpacing.sm),

                Text(
                  price,
                  style: LocalLinkTextStyles.bodyStrong.copyWith(
                    fontSize: 18,
                    color: AppColors.serviceGreen,
                  ),
                ),
              ],
            ),

            if (duration != null) ...[
              const SizedBox(height: LocalLinkSpacing.xs),

              _ServiceMeta(icon: Icons.timer_outlined, label: '$duration mins'),
            ],

            if (details.trim().isNotEmpty) ...[
              const SizedBox(height: LocalLinkSpacing.sm),

              Text(
                details,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: LocalLinkTextStyles.body,
              ),
            ],

            const SizedBox(height: LocalLinkSpacing.md),

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _liveAvailabilityStream(),
              builder: (context, snapshot) {
                final docs = (snapshot.data?.docs ?? const [])
                    .where(
                      (doc) => isAvailabilityUsable(doc.data(), DateTime.now()),
                    )
                    .toList();
                final availability = docs.isEmpty ? null : docs.first;

                if (availability != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LocalLinkButton(
                        label: 'Book available time',
                        icon: Icons.event_available_outlined,
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AvailabilityDetailScreen(
                                postId: availability.id,
                                availabilityData: availability.data(),
                                businessData: businessData,
                              ),
                            ),
                          );
                        },
                        expand: true,
                      ),
                      const SizedBox(height: LocalLinkSpacing.xs),
                      if (!isOwnBusiness)
                        _ServiceEnquiryButton.outlined(
                          onPressed: () => _askQuestion(context),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: 'Ask a question',
                        ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'No times currently listed.',
                      style: LocalLinkTextStyles.metadata,
                    ),
                    const SizedBox(height: LocalLinkSpacing.xs),
                    if (!isOwnBusiness)
                      _ServiceEnquiryButton.filled(
                        onPressed: () => _askQuestion(context),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: 'Enquire with business',
                      ),
                  ],
                );
              },
            ),

            const SizedBox(height: LocalLinkSpacing.xs),

            LocalLinkButton(
              label: 'Share service',
              icon: Icons.ios_share_outlined,
              variant: LocalLinkButtonVariant.secondary,
              onPressed: () async {
                try {
                  await LocalLinkShareService().shareItem(
                    item: LocalLinkShareItem(
                      type: LocalLinkShareItemType.service,
                      id: serviceId,
                      parentId: businessId,
                      data: {...serviceData, 'businessName': businessName},
                    ),
                  );
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sharing could not be started.'),
                    ),
                  );
                }
              },
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceQuestionDialog extends StatefulWidget {
  const _ServiceQuestionDialog();

  @override
  State<_ServiceQuestionDialog> createState() => _ServiceQuestionDialogState();
}

class _ServiceQuestionDialogState extends State<_ServiceQuestionDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _hasSubmitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    if (_hasSubmitted) return;
    _hasSubmitted = true;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ask a Question'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Ask about times, details or anything you need to know.',
        ),
        onSubmitted: (_) => _send(),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _send, child: const Text('Send')),
      ],
    );
  }
}

enum _ServiceEnquiryButtonType { filled, outlined }

class _ServiceEnquiryButton extends StatefulWidget {
  const _ServiceEnquiryButton.filled({
    required this.onPressed,
    required this.icon,
    required this.label,
  }) : type = _ServiceEnquiryButtonType.filled;

  const _ServiceEnquiryButton.outlined({
    required this.onPressed,
    required this.icon,
    required this.label,
  }) : type = _ServiceEnquiryButtonType.outlined;

  final Future<void> Function() onPressed;
  final Widget icon;
  final String label;
  final _ServiceEnquiryButtonType type;

  @override
  State<_ServiceEnquiryButton> createState() => _ServiceEnquiryButtonState();
}

class _ServiceEnquiryButtonState extends State<_ServiceEnquiryButton> {
  bool _isSending = false;
  final SingleFlightGuard _guard = SingleFlightGuard();

  Future<void> _handlePressed() async {
    await _guard.run(() async {
      setState(() => _isSending = true);
      try {
        await widget.onPressed();
      } finally {
        if (mounted) {
          setState(() => _isSending = false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final iconData = widget.icon is Icon
        ? (widget.icon as Icon).icon
        : Icons.chat_bubble_outline;

    return LocalLinkButton(
      label: widget.label,
      icon: iconData,
      isLoading: _isSending,
      variant: widget.type == _ServiceEnquiryButtonType.outlined
          ? LocalLinkButtonVariant.secondary
          : LocalLinkButtonVariant.primary,
      onPressed: _isSending ? null : _handlePressed,
      expand: true,
    );
  }
}

class _ServiceMeta extends StatelessWidget {
  const _ServiceMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.serviceGreen),
        const SizedBox(width: LocalLinkSpacing.xxs),
        Text(label, style: LocalLinkTextStyles.metadata),
      ],
    );
  }
}
