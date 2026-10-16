import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import 'local_link_surface_card.dart';

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
      child: LocalLinkSurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.all(LocalLinkSpacing.md),
        radius: LocalLinkRadius.lg,
        child: Row(
          children: [
            LocalLinkIconBadge(icon: icon, size: 42),
            const SizedBox(width: LocalLinkSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: LocalLinkTextStyles.bodyStrong),
                  const SizedBox(height: LocalLinkSpacing.xxs),
                  Text(subtitle, style: LocalLinkTextStyles.metadata),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.charcoal.withValues(alpha: 0.34),
            ),
          ],
        ),
      ),
    );
  }
}
