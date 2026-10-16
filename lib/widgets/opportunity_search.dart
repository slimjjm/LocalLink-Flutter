import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';

class OpportunitySearch extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const OpportunitySearch({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: LocalLinkTextStyles.body,
      decoration: InputDecoration(
        hintText: 'Search activities, services and help',
        hintStyle: LocalLinkTextStyles.secondary.copyWith(
          color: AppColors.textLight,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textMuted,
        ),
        suffixIcon: const Icon(Icons.tune_rounded, color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.elevatedSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LocalLinkSpacing.md,
          vertical: LocalLinkSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
          borderSide: BorderSide(
            color: AppColors.charcoal.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
    );
  }
}
