import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../theme/app_colors.dart';
import '../utils/helpers.dart';
import '../utils/single_flight_guard.dart';
import '../services/booking_messaging_service.dart';
import '../services/local_link_share_service.dart';

import 'availability_detail_screen.dart';
import 'booking_conversation_screen.dart';

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
      matches(businessData['createdBy']) ||
      containsUser(businessData['ownerIds']) ||
      containsUser(businessData['adminUserIds']);
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
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final businessData =
            snapshot.data!.data() as Map<String, dynamic>? ?? {};

        final businessName = safeText(businessData['businessName'], 'Business');

        final category = safeText(businessData['category'], 'No category');

        final bio = safeText(businessData['bio'], '');

        final address = safeText(businessData['address'], '');

        final serviceArea = safeText(businessData['serviceArea'], '');

        final openingHours = safeText(businessData['openingHours'], '');

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

        final photoURLs = List<String>.from(businessData['photoURLs'] ?? []);

        final coverPhoto = photoURLs.isNotEmpty ? photoURLs.first : null;

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
                      if (coverPhoto != null)
                        Image.network(
                          coverPhoto,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: AppColors.serviceGreen.withValues(
                                alpha: 0.08,
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: AppColors.serviceGreen.withValues(
                                alpha: 0.10,
                              ),
                              child: const Icon(
                                Icons.storefront_outlined,
                                size: 56,
                                color: AppColors.serviceGreen,
                              ),
                            );
                          },
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
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundImage: NetworkImage(logoUrl),
                                    onBackgroundImageError:
                                        (exception, stackTrace) {},
                                    backgroundColor: Colors.white,
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
                      _PrimaryBusinessActions(
                        businessId: widget.businessId,
                        businessName: businessName,
                        category: category,
                        onBook: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Choose a service below to book.'),
                            ),
                          );
                        },
                        onContact: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Choose a service below to ask a question.',
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 22),

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
                        const SizedBox(height: 28),

                        const Text(
                          'About',

                          style: TextStyle(
                            fontSize: 24,

                            fontWeight: FontWeight.w800,

                            color: AppColors.charcoal,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          bio,

                          style: TextStyle(
                            height: 1.6,

                            fontSize: 15,

                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],

                      if (photoURLs.length > 1) ...[
                        const SizedBox(height: 24),

                        _PhotoGallery(photoURLs: photoURLs.skip(1).toList()),
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
                      const SizedBox(height: 36),

                      const Text(
                        'Services',

                        style: TextStyle(
                          fontSize: 28,

                          fontWeight: FontWeight.w800,

                          color: AppColors.charcoal,
                        ),
                      ),

                      const SizedBox(height: 16),

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
                          if (!snapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.all(30),

                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          final services = snapshot.data?.docs ?? [];

                          if (services.isEmpty) {
                            return Container(
                              width: double.infinity,

                              padding: const EdgeInsets.all(24),

                              decoration: BoxDecoration(
                                color: Colors.white,

                                borderRadius: BorderRadius.circular(24),
                              ),

                              child: const Text('No services available yet.'),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

      decoration: BoxDecoration(
        color: AppColors.serviceGreen.withValues(alpha: 0.08),

        borderRadius: BorderRadius.circular(999),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(icon, size: 18, color: AppColors.serviceGreen),

          const SizedBox(width: 7),

          Text(
            label,

            style: const TextStyle(
              fontWeight: FontWeight.w700,

              color: AppColors.charcoal,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryBusinessActions extends StatelessWidget {
  const _PrimaryBusinessActions({
    required this.businessId,
    required this.businessName,
    required this.category,
    required this.onBook,
    required this.onContact,
  });

  final String businessId;
  final String businessName;
  final String category;
  final VoidCallback onBook;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onBook,
            icon: const Icon(Icons.calendar_month_outlined),
            label: const Text('Book Service'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.serviceGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onContact,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Contact Business'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.serviceGreen,
                  side: const BorderSide(color: AppColors.serviceGreen),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _FavoriteBusinessIconButton(
              businessId: businessId,
              businessName: businessName,
              category: category,
            ),
          ],
        ),
      ],
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
        const _TrustBadge(icon: Icons.credit_card, label: 'Card Payments'),
      if (paymentMethods.contains('cash'))
        const _TrustBadge(icon: Icons.payments, label: 'Cash Accepted'),
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
        const Text(
          'Trust',
          style: TextStyle(
            color: AppColors.charcoal,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: items),
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
            child: Image.network(
              photoURLs[index],
              width: 124,
              height: 92,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: 124,
                  height: 92,
                  color: AppColors.serviceGreen.withValues(alpha: 0.08),
                  child: const Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 124,
                  height: 92,
                  color: AppColors.serviceGreen.withValues(alpha: 0.10),
                  child: const Icon(
                    Icons.image_not_supported_outlined,
                    color: AppColors.serviceGreen,
                  ),
                );
              },
            ),
          );
        },
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
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
                : paymentMethods
                      .map((method) => method == 'stripe' ? 'Card' : 'Cash')
                      .join(', '),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to ask a question.')),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(24),
        border: highlighted
            ? Border.all(color: AppColors.serviceGreen, width: 2)
            : null,

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),

            blurRadius: 12,

            offset: const Offset(0, 6),
          ),
        ],
      ),

      child: Padding(
        padding: const EdgeInsets.all(18),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            if (imageUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  imageUrl,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 150,
                      color: AppColors.serviceGreen.withValues(alpha: 0.08),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.serviceGreen,
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 150,
                      color: AppColors.serviceGreen.withValues(alpha: 0.08),
                      child: const Icon(
                        Icons.handshake_outlined,
                        color: AppColors.serviceGreen,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,

                    style: const TextStyle(
                      fontSize: 20,

                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),

                Text(
                  price,

                  style: const TextStyle(
                    fontWeight: FontWeight.w800,

                    fontSize: 18,

                    color: AppColors.serviceGreen,
                  ),
                ),
              ],
            ),

            if (duration != null) ...[
              const SizedBox(height: 6),

              Text('$duration mins'),
            ],

            if (details.trim().isNotEmpty) ...[
              const SizedBox(height: 12),

              Text(
                details,

                style: TextStyle(height: 1.5, color: Colors.grey.shade700),
              ),
            ],

            const SizedBox(height: 18),

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _liveAvailabilityStream(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? const [];
                final availability = docs.isEmpty ? null : docs.first;

                if (availability != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
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
                        icon: const Icon(Icons.event_available_outlined),
                        label: const Text('Book available time'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.serviceGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (!isOwnBusiness)
                        _ServiceEnquiryButton.outlined(
                          onPressed: () => _askQuestion(context),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: 'Ask a Question',
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.serviceGreen,
                            side: const BorderSide(
                              color: AppColors.serviceGreen,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'No times currently listed.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (!isOwnBusiness)
                      _ServiceEnquiryButton.filled(
                        onPressed: () => _askQuestion(context),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: 'Enquire with business',
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.serviceGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
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
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Share'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.serviceGreen,
                  side: const BorderSide(color: AppColors.serviceGreen),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
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
    required this.style,
  }) : type = _ServiceEnquiryButtonType.filled;

  const _ServiceEnquiryButton.outlined({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.style,
  }) : type = _ServiceEnquiryButtonType.outlined;

  final Future<void> Function() onPressed;
  final Widget icon;
  final String label;
  final ButtonStyle style;
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
    final icon = _isSending
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : widget.icon;

    if (widget.type == _ServiceEnquiryButtonType.outlined) {
      return OutlinedButton.icon(
        onPressed: _isSending ? null : _handlePressed,
        icon: icon,
        label: Text(widget.label),
        style: widget.style,
      );
    }

    return ElevatedButton.icon(
      onPressed: _isSending ? null : _handlePressed,
      icon: icon,
      label: Text(widget.label),
      style: widget.style,
    );
  }
}
