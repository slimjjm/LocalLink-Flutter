import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';

class LocalLinkSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const LocalLinkSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: subtitle == null
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: LocalLinkTextStyles.sectionTitle),
              if (subtitle != null) ...[
                const SizedBox(height: LocalLinkSpacing.xs),
                Text(subtitle!, style: LocalLinkTextStyles.secondary),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: LocalLinkSpacing.md),
          IconTheme.merge(
            data: const IconThemeData(color: AppColors.charcoal, size: 20),
            child: trailing!,
          ),
        ],
      ],
    );
  }
}
