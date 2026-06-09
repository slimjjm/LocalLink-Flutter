import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_colors.dart';
import '../viewmodels/customer_unread_view_model.dart';
import '../widgets/business_card.dart';

import 'business_list_screen.dart';
import 'my_bookings_screen.dart';
import 'business_gate_screen.dart';
import 'inbox_screen.dart';
import 'claim_business_screen.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:geolocator/geolocator.dart';

import '../services/location_service.dart';
import 'opportunity_detail_screen.dart';
import 'create_opportunity_screen.dart';
import 'my_opportunities_screen.dart';


class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final CustomerUnreadViewModel unreadViewModel = CustomerUnreadViewModel();

final List<String> categories = const [
  'Fitness & Sport',
  'Family',
  'Pets',
  'Hobbies',
  'Social',
  'Volunteering',
  'Learning',
  'Local Deals',
];

  @override
  void initState() {
    super.initState();

    unreadViewModel.onUpdated = () {
      if (mounted) setState(() {});
    };

    unreadViewModel.startListening();
  }

  @override
  void dispose() {
    unreadViewModel.dispose();
    super.dispose();
  }

  void _openBusinessList({
    String? postcode,
    String? category,
    bool useCurrentLocation = false,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessListScreen(
          initialPostcode: postcode,
          initialCategory: category,
          useCurrentLocation: useCurrentLocation,
        ),
      ),
    );
  }

  void _openInbox() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const InboxScreen(
          currentRole: 'customer',
        ),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SettingsSheet(),
    );
  }

  Future<void> _showPostcodeSearch() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PostcodeSearchSheet(),
    );

    if (!mounted) return;

    final postcode = result?.trim();

    if (postcode == null || postcode.isEmpty) return;

    _openBusinessList(postcode: postcode);
  }

  @override
  Widget build(BuildContext context) {
   return Scaffold(
  backgroundColor: AppColors.background,

  

  body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                

                   _WelcomeHeader(
  unreadCount:
      unreadViewModel.unreadCount,
  onMessagesTap: _openInbox,
  onSettingsTap: _openSettings,
),

                    const SizedBox(height: 16),

                    _PostcodeSearchCard(
                      onTap: _showPostcodeSearch,
                    ),

                    const SizedBox(height: 12),

                  const SizedBox(height: 16),

const _FeaturedOpportunityCard(),

const SizedBox(height: 24),

const _CreateOpportunityCard(),

const SizedBox(height: 16),

const _MyOpportunitiesCard(),

const SizedBox(height: 24),

const _OpportunityFeed(),

                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// =====================================================
// HEADER
// =====================================================

class _Header extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onMessagesTap;
  final VoidCallback onSettingsTap;

  const _Header({
    required this.unreadCount,
    required this.onMessagesTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LocalLink',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppColors.charcoal,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Find trusted services wherever you need them.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),

        _HeaderIconButton(
          icon: Icons.settings_outlined,
          onTap: onSettingsTap,
        ),

        const SizedBox(width: 10),

        GestureDetector(
          onTap: onMessagesTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const _HeaderIconButton(
                icon: Icons.chat_bubble_outline,
              ),
              if (unreadCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _HeaderIconButton({
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: AppColors.charcoal,
      ),
    );

    if (onTap == null) return button;

    return GestureDetector(
      onTap: onTap,
      child: button,
    );
  }
}
class _WelcomeHeader extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onMessagesTap;
  final VoidCallback onSettingsTap;

  const _WelcomeHeader({
    required this.unreadCount,
    required this.onMessagesTap,
    required this.onSettingsTap,
  });

  String greeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return 'Good morning';
    }

    if (hour < 18) {
      return 'Good afternoon';
    }

    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                '${greeting()}, Jay 👋',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppColors.charcoal,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Discover opportunities and connect with your local community',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        Column(
          children: [

            _HeaderIconButton(
              icon: Icons.settings_outlined,
              onTap: onSettingsTap,
            ),

            const SizedBox(height: 10),

            GestureDetector(
              onTap: onMessagesTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [

                  const _HeaderIconButton(
                    icon: Icons.chat_bubble_outline,
                  ),

                  if (unreadCount > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius:
                              BorderRadius.circular(
                            999,
                          ),
                        ),
                        child: Text(
                          unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
// =====================================================
// HERO
// =====================================================

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.primary,
            Color(0xFFFF7A3D),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LOCAL LINK',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
              fontSize: 12,
            ),
          ),
          SizedBox(height: 10),
          Text(
           'Discover your community',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Find local groups, events, volunteering, fitness and community opportunities near you.',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// POSTCODE SEARCH
// =====================================================

class _PostcodeSearchCard extends StatelessWidget {
  final VoidCallback onTap;

  const _PostcodeSearchCard({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.search,
              color: Colors.grey.shade500,
            ),
            const SizedBox(width: 12),
           const Expanded(
  child: Text(
    'Search nearby opportunities...',
                style: TextStyle(
                  color: Colors.black45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Colors.black38,
            ),
          ],
        ),
      ),
    );
  }
}

class _PostcodeSearchSheet extends StatefulWidget {
  const _PostcodeSearchSheet();

  @override
  State<_PostcodeSearchSheet> createState() => _PostcodeSearchSheetState();
}

class _PostcodeSearchSheetState extends State<_PostcodeSearchSheet> {
  final TextEditingController controller = TextEditingController();
  String? errorText;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit() {
    final postcode = controller.text.trim();

    if (postcode.isEmpty) {
      setState(() {
        errorText = 'Enter a postcode to search.';
      });
      return;
    }

    Navigator.pop(context, postcode);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(30),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Search by postcode',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppColors.charcoal,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Useful if you’re booking for a rental, family member, job address, or another location.',
                style: TextStyle(
                  color: Colors.black54,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              keyboardType: TextInputType.streetAddress,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Enter postcode e.g. L23 8SW',
                errorText: errorText,
                prefixIcon: const Icon(Icons.location_on_outlined),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: Colors.grey.shade200,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: Colors.grey.shade200,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.search),
                label: const Text('Search postcode'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
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

class _CurrentLocationButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CurrentLocationButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.near_me),
        label: const Text('Use current location'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _MyOpportunitiesCard
    extends StatelessWidget {

  const _MyOpportunitiesCard();

  @override
  Widget build(BuildContext context) {

    return GestureDetector(
      onTap: () {

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const MyOpportunitiesScreen(),
          ),
        );
      },
      child: Container(
        padding:
            const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(24),
        ),
        child: const Row(
          children: [

            Icon(
              Icons.event_available,
            ),

            SizedBox(width: 12),

            Expanded(
              child: Text(
                'My Opportunities',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
            ),

            Icon(
              Icons.chevron_right,
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// FEATURED OPPORTUNITY
// =====================================================

class _FeaturedOpportunityCard extends StatelessWidget {
  const _FeaturedOpportunityCard();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Position?>(
      future: LocationService().getCurrentLocation(),
      builder: (context, locationSnapshot) {
        final userPosition = locationSnapshot.data;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('opportunities')
              .where('isActive', isEqualTo: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData ||
                snapshot.data!.docs.isEmpty) {
              return const SizedBox.shrink();
            }

            final docs = snapshot.data!.docs;

            QueryDocumentSnapshot? bestDoc;
            double bestScore = -999999;

            for (final doc in docs) {
              final data =
                  doc.data() as Map<String, dynamic>;

                  debugPrint(
  'Opportunity: ${doc.id} => $data',
);

              double score = 0;

              // ======================
              // ATTENDEES
              // ======================

            final attendees =
    (data['attendeeCount'] as num?)?.toInt() ?? 0;

              score += attendees * 3;

              // ======================
              // RECENCY
              // ======================

              final createdAt =
                  data['createdAt'];

              if (createdAt != null) {
                final daysOld =
                    DateTime.now()
                        .difference(
                          createdAt.toDate(),
                        )
                        .inDays;

                score +=
                    (30 - daysOld)
                        .clamp(0, 30);
              }

              // ======================
              // DISTANCE
              // ======================

          double? latitude;
double? longitude;

if (data['latitude'] != null) {
  latitude =
      double.tryParse(
        data['latitude'].toString(),
      );
}

if (data['longitude'] != null) {
  longitude =
      double.tryParse(
        data['longitude'].toString(),
      );
}

debugPrint(
  'lat=${data['latitude']} '
  'lng=${data['longitude']}',
);

              if (userPosition != null &&
                  latitude != null &&
                  longitude != null) {
                final miles =
                    Geolocator.distanceBetween(
                          userPosition.latitude,
                          userPosition.longitude,
                          latitude,
                          longitude,
                        ) /
                        1609.34;

                if (miles < 2) {
                  score += 25;
                } else if (miles < 5) {
                  score += 15;
                } else if (miles < 10) {
                  score += 5;
                }
              }

              if (score > bestScore) {
                bestScore = score;
                bestDoc = doc;
              }
            }

            if (bestDoc == null) {
              return const SizedBox.shrink();
            }

            final data =
                bestDoc!.data()
                    as Map<String, dynamic>;

            return Container(
              padding:
                  const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AppColors.primary,
                    Color(0xFFFF8B50),
                  ],
                ),
                borderRadius:
                    BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔥 Featured Near You',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    data['title'] ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    data['description'] ??
                        '',
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    '${data['attendeeCount'] ?? 0} attending',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
// =====================================================
// SECTION HEADER
// =====================================================

class _CreateOpportunityCard extends StatelessWidget {
  const _CreateOpportunityCard();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const CreateOpportunityScreen(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(24),
          border: Border.all(
            color: Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                0.04,
              ),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary
                    .withOpacity(0.12),
                borderRadius:
                    BorderRadius.circular(
                  16,
                ),
              ),
              child: const Icon(
                Icons.add_circle_outline,
                color: AppColors.primary,
                size: 30,
              ),
            ),

            const SizedBox(width: 16),

            const Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create Opportunity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Create a local event or meetup.',
                    style: TextStyle(
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(
              Icons.chevron_right,
              color: Colors.black38,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionText;
  final VoidCallback onActionTap;

  const _SectionHeader({
    required this.title,
    required this.actionText,
    required this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.charcoal,
            ),
          ),
        ),
        TextButton(
          onPressed: onActionTap,
          child: Text(actionText),
        ),
      ],
    );
  }
}

// =====================================================
// CATEGORY CHIP
// =====================================================

// =====================================================
// CATEGORY CHIP
// =====================================================

class _CategoryChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.onTap,
  });

String emojiFor(String category) {
  switch (category) {
    case 'Fitness & Sport':
      return '💪';

    case 'Family':
      return '👨‍👩‍👧';

    case 'Pets':
      return '🐶';

    case 'Hobbies':
      return '🎨';

    case 'Social':
      return '🎉';

    case 'Volunteering':
      return '❤️';

    case 'Learning':
      return '📚';

    case 'Local Deals':
      return '🏷️';

    default:
      return '📍';
  }
}

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(
        '${emojiFor(label)} $label',
      ),
      onPressed: onTap,
      backgroundColor: Colors.white,
      elevation: 0,
      side: BorderSide(
        color: Colors.grey.shade200,
      ),
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: AppColors.charcoal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

// =====================================================
// QUICK ACTIONS
// =====================================================

class _QuickActions extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onBookingsTap;
  final VoidCallback onMessagesTap;

  const _QuickActions({
    required this.unreadCount,
    required this.onBookingsTap,
    required this.onMessagesTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionCard(
            icon: Icons.calendar_month_outlined,
            title: 'Bookings',
            subtitle: 'View your bookings',
            onTap: onBookingsTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.chat_bubble_outline,
            title: 'Messages',
            subtitle: unreadCount > 0 ? '$unreadCount unread' : 'Inbox',
            urgent: unreadCount > 0,
            onTap: onMessagesTap,
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool urgent;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.urgent = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: urgent ? AppColors.error.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: urgent
                ? AppColors.error.withOpacity(0.25)
                : Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: urgent ? AppColors.error : AppColors.primary,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.charcoal,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// BUSINESS FEED
// =====================================================

class _BusinessFeed extends StatelessWidget {
  const _BusinessFeed();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('businesses')
          .where('isActive', isEqualTo: true)
          .where('isClaimed', isEqualTo: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No businesses serving this area yet.'),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: BusinessCard(
                  businessId: doc.id,
                  businessData: data,
                ),
              );
            },
            childCount: docs.length,
          ),
        );
      },
    );
  }
}

// =====================================================
// BUSINESS OWNER SECTION
// =====================================================
class _BusinessOwnerSection extends StatelessWidget {
  final VoidCallback onClaimTap;
  final VoidCallback onDashboardTap;

  const _BusinessOwnerSection({
    required this.onClaimTap,
    required this.onDashboardTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Own a business?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.charcoal,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Claim your business, manage opportunities and connect with local customers.',
            style: TextStyle(
              color: Colors.black54,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onClaimTap,
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Claim Business'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onDashboardTap,
              icon: const Icon(Icons.business_center_outlined),
              label: const Text('Business Dashboard'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// =====================================================
// SETTINGS SHEET
// =====================================================

class _SettingsSheet extends StatelessWidget {

  const _SettingsSheet();

  Future<void> _logout(BuildContext context) async {

    await FirebaseAuth.instance.signOut();

    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _openUrl(String url) async {

    final uri = Uri.parse(url);

    if (!await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    )) {

      throw Exception(
        'Could not launch $url',
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    return SingleChildScrollView(

      child: Container(

        padding: const EdgeInsets.fromLTRB(
          20,
          18,
          20,
          30,
        ),

        decoration: const BoxDecoration(

          color: AppColors.background,

          borderRadius: BorderRadius.vertical(
            top: Radius.circular(30),
          ),
        ),

        child: Column(

          mainAxisSize: MainAxisSize.min,

          children: [

            Container(

              width: 44,
              height: 5,

              decoration: BoxDecoration(

                color: Colors.black12,

                borderRadius:
                    BorderRadius.circular(999),
              ),
            ),

            const SizedBox(height: 20),

            const Align(

              alignment: Alignment.centerLeft,

              child: Text(

                'Settings',

                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppColors.charcoal,
                ),
              ),
            ),

            const SizedBox(height: 14),

            _SettingsTile(

              icon:
                  Icons.notifications_outlined,

              title: 'Notifications',

              subtitle:
                  'Manage message and booking alerts',

              onTap: () {

                ScaffoldMessenger.of(context)
                    .showSnackBar(

                  const SnackBar(
                    content: Text(
                      'Notification settings coming soon.',
                    ),
                  ),
                );
              },
            ),

            _SettingsTile(

              icon:
                  Icons.location_on_outlined,

              title: 'Location',

              subtitle:
                  'Manage location and postcode search',

              onTap: () {

                ScaffoldMessenger.of(context)
                    .showSnackBar(

                  const SnackBar(
                    content: Text(
                      'Location settings coming soon.',
                    ),
                  ),
                );
              },
            ),

            _SettingsTile(

              icon:
                  Icons.privacy_tip_outlined,

              title: 'Privacy Policy',

              subtitle:
                  'View how LocalLink handles data',

              onTap: () => _openUrl(
                'https://locallinkapp.co.uk/privacy',
              ),
            ),

            _SettingsTile(

              icon:
                  Icons.article_outlined,

              title: 'Terms',

              subtitle:
                  'View LocalLink terms of use',

              onTap: () => _openUrl(
                'https://locallinkapp.co.uk/terms',
              ),
            ),

            _SettingsTile(

              icon:
                  Icons.support_agent_outlined,

              title: 'Support',

              subtitle:
                  'Contact LocalLink support',

              onTap: () => _openUrl(
                'mailto:support@locallinkapp.co.uk',
              ),
            ),
// =====================================================
// DELETE ACCOUNT BUTTON
// =====================================================

const SizedBox(height: 12),

SizedBox(

  width: double.infinity,

  child: OutlinedButton.icon(

    onPressed: () async {

      final confirmed =
          await showDialog<bool>(

        context: context,

        builder: (_) {

          return AlertDialog(

            title: const Text(
              'Delete account?',
            ),

            content: const Text(
              'This permanently deletes your LocalLink account. This action cannot be undone.',
            ),

            actions: [

              TextButton(

                onPressed: () {
                  Navigator.pop(
                    context,
                    false,
                  );
                },

                child: const Text(
                  'Cancel',
                ),
              ),

              ElevatedButton(

                onPressed: () {
                  Navigator.pop(
                    context,
                    true,
                  );
                },

                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      AppColors.error,
                  foregroundColor:
                      Colors.white,
                ),

                child: const Text(
                  'Delete',
                ),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return;

      try {

        final user =
            FirebaseAuth.instance.currentUser;

        if (user == null) return;

        // Delete Firestore user doc
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .delete();

        // Delete Firebase auth account
        await user.delete();

        if (context.mounted) {

          Navigator.pop(context);

          ScaffoldMessenger.of(context)
              .showSnackBar(

            const SnackBar(
              content: Text(
                'Account deleted.',
              ),
            ),
          );
        }

      } catch (e) {

        if (context.mounted) {

          ScaffoldMessenger.of(context)
              .showSnackBar(

            SnackBar(
              content: Text(
                'Delete failed: $e',
              ),
            ),
          );
        }
      }
    },

    icon: const Icon(
      Icons.delete_outline,
    ),

    label: const Text(
      'Delete account',
    ),

    style: OutlinedButton.styleFrom(

      foregroundColor:
          AppColors.error,

      side: BorderSide(
        color:
            AppColors.error.withOpacity(
          0.4,
        ),
      ),

      padding:
          const EdgeInsets.symmetric(
        vertical: 14,
      ),
    ),
  ),
),

            const SizedBox(height: 8),

            SizedBox(

              width: double.infinity,

              child: OutlinedButton.icon(

                onPressed: () =>
                    _logout(context),

                icon: const Icon(
                  Icons.logout,
                ),

                label: const Text(
                  'Log out',
                ),

                style:
                    OutlinedButton.styleFrom(

                  foregroundColor:
                      AppColors.error,

                  side: BorderSide(
                    color: AppColors.error
                        .withOpacity(0.4),
                  ),

                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 14,
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

class _SettingsTile extends StatelessWidget {

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {

    return ListTile(

      contentPadding: EdgeInsets.zero,

      leading: CircleAvatar(

        backgroundColor:
            AppColors.primary.withOpacity(
          0.10,
        ),

        child: Icon(
          icon,
          color: AppColors.primary,
        ),
      ),

      title: Text(

        title,

        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.charcoal,
        ),
      ),

      subtitle: Text(subtitle),

      trailing: const Icon(
        Icons.chevron_right,
      ),

      onTap: onTap,
    );
  }
}

// =====================================================
// OPPORTUNITY FEED
// =====================================================

class _OpportunityFeed extends StatefulWidget {
  const _OpportunityFeed();

  @override
  State<_OpportunityFeed> createState() =>
      _OpportunityFeedState();
}

class _OpportunityFeedState
    extends State<_OpportunityFeed> {
      Position? userPosition;

@override
void initState() {
  super.initState();
  loadLocation();
}

Future<void> loadLocation() async {
  try {
    final position =
        await Geolocator.getCurrentPosition();

    if (!mounted) return;

    setState(() {
      userPosition = position;
    });
  } catch (_) {}
}
  String selectedCategory = 'All';
  String searchText = '';

  final categories = [
  'All',
  'Fitness & Sport',
  'Family',
  'Pets',
  'Hobbies',
  'Social',
  'Volunteering',
  'Learning',
  'Local Deals',
];

Color categoryColor(String category) {
  switch (category) {
    case 'Fitness & Sport':
      return Colors.green;

    case 'Family':
      return Colors.pink;

    case 'Pets':
      return Colors.orange;

    case 'Hobbies':
      return Colors.purple;

    case 'Social':
      return Colors.blue;

    case 'Volunteering':
      return Colors.red;

    case 'Learning':
      return Colors.teal;

    case 'Local Deals':
      return Colors.indigo;

    default:
      return AppColors.primary;
  }
}

  IconData categoryIcon(String category) {
  switch (category) {
    case 'Fitness & Sport':
      return Icons.fitness_center;

    case 'Family':
      return Icons.family_restroom;

    case 'Pets':
      return Icons.pets;

    case 'Hobbies':
      return Icons.palette;

    case 'Social':
      return Icons.groups;

    case 'Volunteering':
      return Icons.favorite;

    case 'Learning':
      return Icons.school;

    case 'Local Deals':
      return Icons.local_offer;

    default:
      return Icons.local_activity;
  }
}

@override
Widget build(BuildContext context) {
  return
      Column(
        children: [
          Padding(
  padding: const EdgeInsets.symmetric(
    horizontal: 20,
  ),
  child: TextField(
    decoration: InputDecoration(
      hintText: 'Search opportunities...',
      prefixIcon: const Icon(Icons.search),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    onChanged: (value) {
      setState(() {
        searchText =
            value.trim().toLowerCase();
      });
    },
  ),
),

const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
              ),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];

                final selected =
                    category == selectedCategory;

                return Padding(
                  padding: const EdgeInsets.only(
                    right: 8,
                  ),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        selectedCategory =
                            category;
                      });
                    },
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('opportunities')
                .where(
                  'isActive',
                  isEqualTo: true,
                )
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Firestore query failed',
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(
                    child:
                        CircularProgressIndicator(),
                  ),
                );
              }

              final docs = snapshot.data!.docs;

             final filteredDocs =
    docs.where((doc) {

  final data =
      doc.data()
          as Map<String, dynamic>;

  final category =
      data['category']
          ?.toString() ?? '';

  final title =
      data['title']
          ?.toString()
          .toLowerCase() ?? '';

  final description =
      data['description']
          ?.toString()
          .toLowerCase() ?? '';

  final matchesCategory =
      selectedCategory == 'All' ||
      category == selectedCategory;

  final matchesSearch =
      searchText.isEmpty ||
      title.contains(searchText) ||
      description.contains(searchText) ||
      category
          .toLowerCase()
          .contains(searchText);

  return matchesCategory &&
      matchesSearch;
}).toList();

              filteredDocs.sort((a, b) {
  final dataA =
      a.data()
          as Map<String, dynamic>;

  final dataB =
      b.data()
          as Map<String, dynamic>;

  double distanceA = 999999;
  double distanceB = 999999;

  final latA = double.tryParse(
    dataA['latitude']
            ?.toString() ??
        '',
  );

  final lngA = double.tryParse(
    dataA['longitude']
            ?.toString() ??
        '',
  );

  final latB = double.tryParse(
    dataB['latitude']
            ?.toString() ??
        '',
  );

  final lngB = double.tryParse(
    dataB['longitude']
            ?.toString() ??
        '',
  );

  if (userPosition != null &&
      latA != null &&
      lngA != null) {
    distanceA =
        Geolocator.distanceBetween(
              userPosition!.latitude,
              userPosition!.longitude,
              latA,
              lngA,
            );
  }

  if (userPosition != null &&
      latB != null &&
      lngB != null) {
    distanceB =
        Geolocator.distanceBetween(
              userPosition!.latitude,
              userPosition!.longitude,
              latB,
              lngB,
            );
  }

  return distanceA.compareTo(
    distanceB,
  );
});

              if (filteredDocs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No opportunities found.',
                  ),
                );
              }

              return Column(
                children:
                    filteredDocs.map((doc) {
                  final data =
                      doc.data()
                          as Map<String, dynamic>;

                  final category =
                      data['category'] ?? '';

                      final eventDate =
    data['eventDate'];

String dateBadge = '';

if (eventDate != null) {
  final date =
      eventDate.toDate();

  final now = DateTime.now();

  final today =
      DateTime(
        now.year,
        now.month,
        now.day,
      );

  final eventDay =
      DateTime(
        date.year,
        date.month,
        date.day,
      );

  final difference =
      eventDay
          .difference(today)
          .inDays;

  if (difference == 0) {
    dateBadge = 'TODAY';
  } else if (difference == 1) {
    dateBadge = 'TOMORROW';
  } else if (difference <= 7) {
    dateBadge = 'THIS WEEK';
  }
}

                      double? milesAway;

final latitude =
    double.tryParse(
      data['latitude']
              ?.toString() ??
          '',
    );

final longitude =
    double.tryParse(
      data['longitude']
              ?.toString() ??
          '',
    );

if (userPosition != null &&
    latitude != null &&
    longitude != null) {

  milesAway =
      Geolocator.distanceBetween(
            userPosition!.latitude,
            userPosition!.longitude,
            latitude,
            longitude,
          ) /
          1609.34;
}

                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(
                        22,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                OpportunityDetailScreen(
                              opportunityId:
                                  doc.id,
                              opportunity:
                                  data,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding:
                            const EdgeInsets.all(
                          16,
                        ),
                        decoration:
                            BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius
                                  .circular(22),
                          border: Border.all(
                            color: Colors
                                .grey.shade200,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withOpacity(
                                0.04,
                              ),
                              blurRadius: 10,
                              offset:
                                  const Offset(
                                0,
                                5,
                              ),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                           (data['photoUrl'] != null &&
        data['photoUrl']
            .toString()
            .isNotEmpty)

    ? ClipRRect(
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        child: Image.network(
          data['photoUrl'],
          width: 70,
          height: 70,
          fit: BoxFit.cover,
        ),
      )

    : Container(
        width: 70,
        height: 70,
        decoration:
            BoxDecoration(
          color:
              categoryColor(
            category,
          ).withOpacity(
            0.12,
          ),
          borderRadius:
              BorderRadius.circular(
            16,
          ),
        ),
        child: Icon(
          categoryIcon(
            category,
          ),
          color:
              categoryColor(
            category,
          ),
        ),
      ),

                            const SizedBox(
                              width: 14,
                            ),

                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                 Column(
  crossAxisAlignment:
      CrossAxisAlignment.start,
  children: [

    if (dateBadge.isNotEmpty)
      Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 4,
        ),
        margin:
            const EdgeInsets.only(
          bottom: 6,
        ),
        decoration: BoxDecoration(
          color:
              AppColors.primary,
          borderRadius:
              BorderRadius.circular(
            999,
          ),
        ),
        child: Text(
          dateBadge,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight:
                FontWeight.w800,
          ),
        ),
      ),

    Text(
      data['title'] ?? '',
      style: const TextStyle(
        fontSize: 18,
        fontWeight:
            FontWeight.w900,
        color:
            AppColors.charcoal,
      ),
    ),
  ],
),

                                  const SizedBox(
                                    height: 4,
                                  ),

                                  Text(
                                    '🏷️ $category',
                                    style:
                                        TextStyle(
                                      color:
                                          categoryColor(
                                        category,
                                      ),
                                      fontWeight:
                                          FontWeight
                                              .w700,
                                    ),
                                  ),

                                  const SizedBox(
                                    height: 8,
                                  ),

                                 Column(
  crossAxisAlignment:
      CrossAxisAlignment.start,
  children: [

    Text(
      data['location'] ?? '',
      style: const TextStyle(
        color: Colors.black54,
      ),
    ),

    if (milesAway != null)
      Padding(
        padding:
            const EdgeInsets.only(
          top: 4,
        ),
        child: Text(
          '${milesAway.toStringAsFixed(1)} miles away',
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight:
                FontWeight.w700,
          ),
        ),
      ),
  ],
),

                                  const SizedBox(
                                    height: 8,
                                  ),

                                  Text(
                                    '${data['attendeeCount'] ?? 0} going',
                                    style:
                                        const TextStyle(
                                      color:
                                          AppColors
                                              .primary,
                                      fontWeight:
                                          FontWeight
                                              .w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                               }).toList(),
              );
            },
          ),
        ],
      );
  }
}