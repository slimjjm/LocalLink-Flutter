import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/community_activity_hero.dart';
import '../widgets/featured_card.dart';
import '../widgets/home_action_drawer.dart';
import '../widgets/opportunity_feed.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/welcome_header.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 128),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        WelcomeHeader(),
                        SizedBox(height: 28),
                        _HomeIntro(),
                        SizedBox(height: 22),
                        FeaturedCard(),
                        SizedBox(height: 28),
                        CommunityActivityHero(),
                        SizedBox(height: 34),
                        OpportunityFeed(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            HomeActionDrawer(onSettingsTap: _openSettings),
          ],
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
            fontSize: 32,
            height: 1.02,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 10),
        Text(
          'Find something interesting nearby and join in when it feels right.',
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
