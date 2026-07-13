import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const HeaderIconButton({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(17);

    final button = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.border.withValues(alpha: 0.72)),
      ),
      child: Icon(icon, color: AppColors.charcoal, size: 22),
    );

    if (onTap == null) {
      return button;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: borderRadius, onTap: onTap, child: button),
    );
  }
}
