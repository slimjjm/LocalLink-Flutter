import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'local_link_surface_card.dart';

class PostcodeSearchCard extends StatelessWidget {
  final VoidCallback onTap;

  const PostcodeSearchCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
      child: Row(
        children: [
          const LocalLinkIconBadge(icon: Icons.location_on_outlined, size: 44),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search another area',
                  style: TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Use a postcode to discover what is nearby',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.charcoal.withOpacity(0.36),
          ),
        ],
      ),
    );
  }
}
