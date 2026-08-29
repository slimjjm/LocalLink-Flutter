import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/business_access_service.dart';
import '../theme/app_colors.dart';
import 'business_bookings_screen.dart';
import 'business_calendar_screen.dart';
import 'business_onboarding_screen.dart';
import 'business_profile_screen.dart';
import 'business_service_requests_screen.dart';
import 'business_services_screen.dart';
import 'customer_bookings_screen.dart';
import 'customer_service_request_screen.dart';
import 'my_opportunities_screen.dart';
import 'post_availability_screen.dart';
import 'post_service_request_screen.dart';
import 'profile_screen.dart';
import 'saved_opportunities_screen.dart';

class MyLocalLinkScreen extends StatefulWidget {
  const MyLocalLinkScreen({super.key});

  @override
  State<MyLocalLinkScreen> createState() => _MyLocalLinkScreenState();
}

class _MyLocalLinkScreenState extends State<MyLocalLinkScreen> {
  late Future<DocumentSnapshot<Map<String, dynamic>>?> _businessFuture;

  @override
  void initState() {
    super.initState();
    _businessFuture = BusinessAccessService.loadLinkedBusiness();
  }

  void _refreshBusiness() {
    setState(() {
      _businessFuture = BusinessAccessService.loadLinkedBusiness();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            const Text(
              'My LocalLink',
              style: TextStyle(
                color: AppColors.charcoal,
                fontSize: 30,
                height: 1.02,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Manage what you have joined, saved, posted and offered.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            const _SectionHeader('Your activity'),
            _ActionTile(
              icon: Icons.calendar_today_outlined,
              title: 'Bookings',
              subtitle: 'Upcoming and past bookings',
              color: AppColors.serviceGreen,
              onTap: () => _push(context, const CustomerBookingsScreen()),
            ),
            _ActionTile(
              icon: Icons.groups_2_outlined,
              title: 'Activities',
              subtitle: 'Joined and hosted activities',
              color: AppColors.activityBlue,
              onTap: () => _push(context, const MyOpportunitiesScreen()),
            ),
            _ActionTile(
              icon: Icons.bookmark_border_rounded,
              title: 'Saved',
              subtitle: 'Saved Pages, activities and services',
              color: AppColors.primary,
              onTap: () => _push(context, const SavedOpportunitiesScreen()),
            ),
            _ActionTile(
              icon: Icons.volunteer_activism_outlined,
              title: 'Community Help',
              subtitle: 'Lost, found and free item posts',
              color: AppColors.primary,
              onTap: () => _push(context, const PostServiceRequestScreen()),
            ),
            _ActionTile(
              icon: Icons.manage_search_outlined,
              title: 'Service requests',
              subtitle: 'Requests you have posted for local providers',
              color: AppColors.serviceGreen,
              onTap: () => _push(context, const CustomerServiceRequestScreen()),
            ),
            if (user != null)
              _ActionTile(
                icon: Icons.person_outline_rounded,
                title: 'Profile',
                subtitle: 'Your LocalLink identity',
                color: AppColors.charcoal,
                onTap: () => _push(
                  context,
                  ProfileScreen(
                    userId: user.uid,
                    userName: user.displayName ?? 'User',
                    photoUrl: user.photoURL,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            const _SectionHeader('Your business'),
            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
              future: _businessFuture,
              builder: (context, snapshot) {
                final business = snapshot.data;

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _BusinessLoadingCard();
                }

                if (business == null || !business.exists) {
                  return _NoBusinessCard(onCreated: _refreshBusiness);
                }

                return _BusinessSection(business: business);
              },
            ),
          ],
        ),
      ),
    );
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _BusinessSection extends StatelessWidget {
  const _BusinessSection({required this.business});

  final DocumentSnapshot<Map<String, dynamic>> business;

  @override
  Widget build(BuildContext context) {
    final data = business.data() ?? {};
    final name = data['businessName']?.toString().trim();
    final businessId = business.id;

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.serviceGreen.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.serviceGreen.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: AppColors.serviceGreen,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name?.isNotEmpty == true ? name! : 'Your Page',
                      style: const TextStyle(
                        color: AppColors.charcoal,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Manage the services people can book from you.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _ActionTile(
          icon: Icons.storefront_outlined,
          title: 'Business profile',
          subtitle: 'Update your public Page',
          color: AppColors.serviceGreen,
          onTap: () =>
              _push(context, BusinessProfileScreen(businessId: businessId)),
        ),
        _ActionTile(
          icon: Icons.handshake_outlined,
          title: 'Services',
          subtitle: 'Manage what customers can book',
          color: AppColors.serviceGreen,
          onTap: () =>
              _push(context, BusinessServicesScreen(businessId: businessId)),
        ),
        _ActionTile(
          icon: Icons.event_available_outlined,
          title: 'Share time',
          subtitle: 'Publish a bookable service opening',
          color: AppColors.serviceGreen,
          onTap: () =>
              _push(context, PostAvailabilityScreen(businessId: businessId)),
        ),
        _ActionTile(
          icon: Icons.calendar_month_outlined,
          title: 'Diary',
          subtitle: 'See your business calendar',
          color: AppColors.primary,
          onTap: () =>
              _push(context, BusinessCalendarScreen(businessId: businessId)),
        ),
        _ActionTile(
          icon: Icons.calendar_today_outlined,
          title: 'Business bookings',
          subtitle: 'Manage appointments and booking requests',
          color: AppColors.primary,
          onTap: () =>
              _push(context, BusinessBookingsScreen(businessId: businessId)),
        ),
        _ActionTile(
          icon: Icons.campaign_outlined,
          title: 'Customer requests',
          subtitle: 'Find nearby people looking for help',
          color: AppColors.warning,
          onTap: () => _push(
            context,
            BusinessServiceRequestsScreen(businessId: businessId),
          ),
        ),
      ],
    );
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _NoBusinessCard extends StatelessWidget {
  const _NoBusinessCard({required this.onCreated});

  final VoidCallback onCreated;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Offer services on LocalLink',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create a business presence when you are ready to take local enquiries or bookings.',
            style: TextStyle(
              color: AppColors.textMuted,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BusinessOnboardingScreen(),
                ),
              );
              onCreated();
            },
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Create business presence'),
          ),
        ],
      ),
    );
  }
}

class _BusinessLoadingCard extends StatelessWidget {
  const _BusinessLoadingCard();

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
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          SizedBox(width: 12),
          Text('Checking business access...'),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.charcoal,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.charcoal,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          height: 1.28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
