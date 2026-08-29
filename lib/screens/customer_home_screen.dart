import 'package:flutter/material.dart';

import '../screens/add_service_screen.dart';
import '../screens/business_list_screen.dart';
import '../screens/business_onboarding_screen.dart';
import '../screens/business_post_availability_gate_screen.dart';
import '../screens/create_opportunity_screen.dart';
import '../screens/post_availability_screen.dart';
import '../screens/post_service_request_screen.dart';
import '../services/business_access_service.dart';
import '../theme/app_colors.dart';
import '../widgets/community_activity_hero.dart';
import '../widgets/featured_card.dart';
import '../widgets/opportunity_feed.dart';
import '../widgets/welcome_header.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    WelcomeHeader(),
                    SizedBox(height: 20),
                    _HomeIntro(),
                    SizedBox(height: 16),
                    _HomePrimaryActions(),
                    SizedBox(height: 18),
                    FeaturedCard(),
                    SizedBox(height: 20),
                    CommunityActivityHero(),
                    SizedBox(height: 24),
                    OpportunityFeed(),
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

class _HomePrimaryActions extends StatelessWidget {
  const _HomePrimaryActions();

  Future<void> _openOfferService(BuildContext context) async {
    final business = await BusinessAccessService.loadLinkedBusiness();

    if (!context.mounted) return;

    if (business != null && business.exists) {
      final result = await Navigator.push<AddServiceResult>(
        context,
        MaterialPageRoute(
          builder: (_) => AddServiceScreen(businessId: business.id),
        ),
      );

      if (!context.mounted) return;

      if (result?.nextStep == AddServiceNextStep.shareNow) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostAvailabilityScreen(
              businessId: result!.businessId,
              initialServiceId: result.serviceId,
            ),
          ),
        );
      }

      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BusinessOnboardingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _HomeActionCard(
                icon: Icons.search_rounded,
                title: 'Find a service',
                subtitle: 'Local help near you',
                color: AppColors.serviceGreen,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const BusinessListScreen(useCurrentLocation: true),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HomeActionCard(
                icon: Icons.design_services_outlined,
                title: 'Offer a service',
                subtitle: 'Let people book you',
                color: AppColors.serviceGreen,
                onTap: () => _openOfferService(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _HomeActionCard(
                icon: Icons.groups_2_outlined,
                title: 'Activities',
                subtitle: 'Discover or host',
                color: AppColors.activityBlue,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateOpportunityScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HomeActionCard(
                icon: Icons.volunteer_activism_outlined,
                title: 'Community help',
                subtitle: 'Lost, found & free',
                color: AppColors.primary,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PostServiceRequestScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        FutureBuilder(
          future: BusinessAccessService.loadLinkedBusiness(),
          builder: (context, snapshot) {
            final business = snapshot.data;
            if (business == null || !business.exists) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const BusinessPostAvailabilityGateScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.event_available_rounded, size: 18),
                  label: const Text('Share an available service time'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.serviceGreen,
                    side: BorderSide(
                      color: AppColors.serviceGreen.withValues(alpha: 0.35),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
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
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(height: 9),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 15,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeIntro extends StatelessWidget {
  const _HomeIntro();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Explore your community',
          style: TextStyle(
            color: AppColors.charcoal,
            fontSize: 28,
            height: 1.02,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Book trusted local help, offer what you do, and join in with nearby community life.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 15,
            height: 1.38,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
