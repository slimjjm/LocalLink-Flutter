import 'package:flutter/material.dart';

import '../screens/create_opportunity_screen.dart';
import '../theme/app_colors.dart';
import 'local_link_surface_card.dart';

class CreateOpportunityCard extends StatelessWidget {
  const CreateOpportunityCard({super.key});

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateOpportunityScreen()),
        );
      },
      padding: const EdgeInsets.all(15),
      elevated: false,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalLinkIconBadge(icon: Icons.add_circle_outline_rounded, size: 40),
          SizedBox(height: 12),
          Text(
            'Create',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Start a local opportunity',
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
