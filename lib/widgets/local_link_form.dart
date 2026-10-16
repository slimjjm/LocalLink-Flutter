import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import 'local_link_surface_card.dart';

class LocalLinkFormSection extends StatelessWidget {
  final String title;
  final String? helperText;
  final List<Widget> children;

  const LocalLinkFormSection({
    super.key,
    required this.title,
    this.helperText,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      radius: LocalLinkRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: LocalLinkTextStyles.label),
          if (helperText != null) ...[
            const SizedBox(height: LocalLinkSpacing.xs),
            Text(helperText!, style: LocalLinkTextStyles.metadata),
          ],
          const SizedBox(height: LocalLinkSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

class LocalLinkFormField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hintText;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  const LocalLinkFormField({
    super.key,
    this.controller,
    required this.label,
    this.hintText,
    this.maxLines = 1,
    this.onChanged,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      keyboardType: keyboardType,
      style: LocalLinkTextStyles.body,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        filled: true,
        fillColor: AppColors.elevatedSurface,
        labelStyle: LocalLinkTextStyles.metadata,
        hintStyle: LocalLinkTextStyles.secondary.copyWith(
          color: AppColors.textLight,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LocalLinkSpacing.md,
          vertical: LocalLinkSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LocalLinkRadius.md),
          borderSide: LocalLinkBorders.subtle,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LocalLinkRadius.md),
          borderSide: LocalLinkBorders.subtle,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LocalLinkRadius.md),
          borderSide: LocalLinkBorders.selected(AppColors.primary),
        ),
      ),
    );
  }
}

class LocalLinkSelectionRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  const LocalLinkSelectionRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.elevatedSurface,
      borderRadius: BorderRadius.circular(LocalLinkRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(
            horizontal: LocalLinkSpacing.md,
            vertical: LocalLinkSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LocalLinkRadius.md),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.72)),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: AppColors.textMuted, size: 20),
                const SizedBox(width: LocalLinkSpacing.sm),
              ],
              Expanded(child: Text(label, style: LocalLinkTextStyles.metadata)),
              const SizedBox(width: LocalLinkSpacing.md),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: LocalLinkTextStyles.bodyStrong,
                ),
              ),
              const SizedBox(width: LocalLinkSpacing.xs),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LocalLinkDateTimeRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const LocalLinkDateTimeRow({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LocalLinkSelectionRow(
      label: label,
      value: value,
      icon: Icons.event_rounded,
      onTap: onTap,
    );
  }
}
