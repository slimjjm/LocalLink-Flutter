import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';

enum LocalLinkButtonVariant { primary, secondary, quiet, destructive }

class LocalLinkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final LocalLinkButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final bool expand;

  const LocalLinkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = LocalLinkButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final colors = _LocalLinkButtonColors.forVariant(variant, enabled);
    final content = AnimatedSwitcher(
      duration: LocalLinkMotion.quick,
      child: isLoading
          ? SizedBox(
              key: const ValueKey('loading'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(colors.foreground),
              ),
            )
          : Row(
              key: const ValueKey('content'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19),
                  const SizedBox(width: LocalLinkSpacing.xs),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Material(
          color: colors.background,
          borderRadius: BorderRadius.circular(LocalLinkRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Container(
              width: expand ? double.infinity : null,
              padding: const EdgeInsets.symmetric(
                horizontal: LocalLinkSpacing.md,
                vertical: LocalLinkSpacing.sm,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(LocalLinkRadius.md),
                border: colors.border,
              ),
              child: DefaultTextStyle.merge(
                style: LocalLinkTextStyles.button.copyWith(
                  color: colors.foreground,
                ),
                textAlign: TextAlign.center,
                child: IconTheme.merge(
                  data: IconThemeData(color: colors.foreground),
                  child: Center(widthFactor: expand ? null : 1, child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalLinkButtonColors {
  final Color background;
  final Color foreground;
  final Border? border;

  const _LocalLinkButtonColors({
    required this.background,
    required this.foreground,
    this.border,
  });

  static _LocalLinkButtonColors forVariant(
    LocalLinkButtonVariant variant,
    bool enabled,
  ) {
    if (!enabled) {
      return const _LocalLinkButtonColors(
        background: AppColors.secondarySurface,
        foreground: AppColors.textLight,
        border: Border.fromBorderSide(LocalLinkBorders.standard),
      );
    }

    switch (variant) {
      case LocalLinkButtonVariant.primary:
        return const _LocalLinkButtonColors(
          background: AppColors.buttonPrimary,
          foreground: AppColors.buttonText,
        );
      case LocalLinkButtonVariant.secondary:
        return const _LocalLinkButtonColors(
          background: AppColors.card,
          foreground: AppColors.charcoal,
          border: Border.fromBorderSide(LocalLinkBorders.standard),
        );
      case LocalLinkButtonVariant.quiet:
        return const _LocalLinkButtonColors(
          background: Colors.transparent,
          foreground: AppColors.charcoal,
        );
      case LocalLinkButtonVariant.destructive:
        return const _LocalLinkButtonColors(
          background: AppColors.lostSoft,
          foreground: AppColors.error,
          border: Border.fromBorderSide(BorderSide(color: AppColors.lostSoft)),
        );
    }
  }
}
