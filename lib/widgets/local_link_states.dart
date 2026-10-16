import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import 'local_link_button.dart';

class LocalLinkLoadingState extends StatelessWidget {
  final String? label;

  const LocalLinkLoadingState({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          if (label != null) ...[
            const SizedBox(height: LocalLinkSpacing.md),
            Text(label!, style: LocalLinkTextStyles.secondary),
          ],
        ],
      ),
    );
  }
}

class LocalLinkEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const LocalLinkEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(LocalLinkSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textMuted, size: 38),
          const SizedBox(height: LocalLinkSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: LocalLinkTextStyles.cardTitle,
          ),
          const SizedBox(height: LocalLinkSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: LocalLinkTextStyles.secondary,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: LocalLinkSpacing.lg),
            LocalLinkButton(
              label: actionLabel!,
              onPressed: onAction,
              variant: LocalLinkButtonVariant.secondary,
            ),
          ],
        ],
      ),
    );
  }
}

class LocalLinkErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const LocalLinkErrorState({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return LocalLinkEmptyState(
      icon: Icons.error_outline_rounded,
      title: title,
      message: message,
      actionLabel: onRetry == null ? null : 'Try again',
      onAction: onRetry,
    );
  }
}

class LocalLinkSkeleton extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;

  const LocalLinkSkeleton({
    super.key,
    required this.height,
    this.width,
    this.radius = LocalLinkRadius.md,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}
