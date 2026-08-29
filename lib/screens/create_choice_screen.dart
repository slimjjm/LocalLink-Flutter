import 'package:flutter/material.dart';

import '../services/business_access_service.dart';
import '../theme/app_colors.dart';
import 'add_service_screen.dart';
import 'business_onboarding_screen.dart';
import 'business_post_availability_gate_screen.dart';
import 'create_opportunity_screen.dart';
import 'customer_service_request_screen.dart';
import 'post_availability_screen.dart';
import 'post_service_request_screen.dart';

class CreateChoiceScreen extends StatelessWidget {
  const CreateChoiceScreen({super.key});

  void _openActivity(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateOpportunityScreen()),
    );
  }

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

  void _openAvailableTime(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BusinessPostAvailabilityGateScreen(),
      ),
    );
  }

  void _openRequest(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PostServiceRequestScreen()),
    );
  }

  void _openServiceRequest(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CustomerServiceRequestScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Create'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'What do you want to create?',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose the path that matches what local people will see.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          const _CreateSectionTitle('Services'),
          _CreateChoiceCard(
            icon: Icons.manage_search_outlined,
            title: 'Request a service',
            subtitle: 'Tell local providers what you need.',
            color: AppColors.serviceGreen,
            onTap: () => _openServiceRequest(context),
          ),
          const SizedBox(height: 14),
          _CreateChoiceCard(
            icon: Icons.design_services_outlined,
            title: 'Offer a service',
            subtitle: 'Let local people book what you offer.',
            color: AppColors.serviceGreen,
            onTap: () => _openOfferService(context),
          ),
          const SizedBox(height: 14),
          _CreateChoiceCard(
            icon: Icons.campaign_outlined,
            title: 'Share a service time',
            subtitle: 'Publish a bookable opening for one of your services.',
            color: AppColors.serviceGreen,
            onTap: () => _openAvailableTime(context),
          ),
          const SizedBox(height: 24),
          const _CreateSectionTitle('Activities'),
          _CreateChoiceCard(
            icon: Icons.groups_2_outlined,
            title: 'Host an activity',
            subtitle: 'Create a meetup, class, club or local event.',
            color: AppColors.activityBlue,
            onTap: () => _openActivity(context),
          ),
          const SizedBox(height: 24),
          const _CreateSectionTitle('Community'),
          _CreateChoiceCard(
            icon: Icons.manage_search_outlined,
            title: 'Lost / found',
            subtitle: 'Ask neighbours about a lost pet, keys or found item.',
            color: AppColors.primary,
            onTap: () => _openRequest(context),
          ),
          const SizedBox(height: 14),
          _CreateChoiceCard(
            icon: Icons.card_giftcard_outlined,
            title: 'Free items',
            subtitle: 'Offer or ask for neighbour-to-neighbour free items.',
            color: AppColors.primary,
            onTap: () => _openRequest(context),
          ),
        ],
      ),
    );
  }
}

class _CreateSectionTitle extends StatelessWidget {
  const _CreateSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          letterSpacing: 0,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CreateChoiceCard extends StatelessWidget {
  const _CreateChoiceCard({
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
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.26)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.charcoal,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        height: 1.32,
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
    );
  }
}
