import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import 'local_link_button.dart';
import 'local_link_surface_card.dart';

class LocalLinkSheetScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final String? primaryLabel;
  final VoidCallback? onPrimaryPressed;
  final bool primaryLoading;

  const LocalLinkSheetScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.primaryLabel,
    this.onPrimaryPressed,
    this.primaryLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: LocalLinkMotion.standard,
        curve: LocalLinkMotion.curve,
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(LocalLinkRadius.sheet),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: LocalLinkSpacing.sm),
                const LocalLinkSheetHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    LocalLinkSpacing.lg,
                    LocalLinkSpacing.lg,
                    LocalLinkSpacing.lg,
                    LocalLinkSpacing.md,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: LocalLinkTextStyles.sectionTitle,
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: LocalLinkSpacing.xs),
                              Text(
                                subtitle!,
                                style: LocalLinkTextStyles.secondary,
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      LocalLinkSpacing.lg,
                      0,
                      LocalLinkSpacing.lg,
                      LocalLinkSpacing.xl,
                    ),
                    child: child,
                  ),
                ),
                if (primaryLabel != null)
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                      LocalLinkSpacing.lg,
                      LocalLinkSpacing.md,
                      LocalLinkSpacing.lg,
                      LocalLinkSpacing.lg,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      border: Border(
                        top: BorderSide(
                          color: AppColors.border.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                    child: LocalLinkButton(
                      label: primaryLabel!,
                      onPressed: onPrimaryPressed,
                      isLoading: primaryLoading,
                      expand: true,
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
