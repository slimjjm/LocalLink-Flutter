import 'package:flutter/material.dart';

import '../screens/my_opportunities_screen.dart';
import '../theme/app_colors.dart';
import 'local_link_surface_card.dart';

class MyOpportunitiesCard extends StatelessWidget {
  const MyOpportunitiesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyOpportunitiesScreen()),
        );
      },
      padding: const EdgeInsets.all(15),
      elevated: false,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalLinkIconBadge(icon: Icons.event_available_rounded, size: 40),
          SizedBox(height: 12),
          Text(
            'Joined',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'View your local plans',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
