import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';

class LocalLinkSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final double radius;
  final bool elevated;

  const LocalLinkSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LocalLinkSpacing.lg),
    this.onTap,
    this.color = AppColors.card,
    this.radius = LocalLinkRadius.lg,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    return Material(
      color: color,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: AppColors.border.withValues(alpha: 0.74)),
            boxShadow: elevated ? LocalLinkDepth.subtle : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

class LocalLinkIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const LocalLinkIconBadge({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.08)),
      ),
      child: Icon(icon, color: color, size: size <= 38 ? 18 : 21),
    );
  }
}

class LocalLinkSheetHandle extends StatelessWidget {
  const LocalLinkSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 5,
      decoration: BoxDecoration(
        color: AppColors.charcoal.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
      ),
    );
  }
}
