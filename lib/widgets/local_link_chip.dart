import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';

class LocalLinkChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool>? onSelected;
  final IconData? icon;
  final Color accentColor;

  const LocalLinkChip({
    super.key,
    required this.label,
    this.selected = false,
    this.enabled = true,
    this.onSelected,
    this.icon,
    this.accentColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveEnabled = enabled && onSelected != null;
    final foreground = selected ? accentColor : AppColors.textMuted;
    final background = selected
        ? accentColor.withValues(alpha: 0.11)
        : AppColors.elevatedSurface;

    return Semantics(
      button: effectiveEnabled,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: effectiveEnabled ? () => onSelected?.call(!selected) : null,
          borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
          child: AnimatedContainer(
            duration: LocalLinkMotion.quick,
            curve: LocalLinkMotion.curve,
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(
              horizontal: LocalLinkSpacing.md,
              vertical: LocalLinkSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
              border: Border.all(
                color: selected
                    ? accentColor.withValues(alpha: 0.30)
                    : AppColors.border.withValues(alpha: 0.78),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: foreground, size: 17),
                  const SizedBox(width: LocalLinkSpacing.xs),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LocalLinkTextStyles.label.copyWith(
                      color: enabled ? foreground : AppColors.textLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
