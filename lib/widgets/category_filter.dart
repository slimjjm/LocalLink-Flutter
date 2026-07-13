import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class CategoryFilter extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelected;

  const CategoryFilter({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = selectedCategory == category;

          return ChoiceChip(
            label: Text(category),
            selected: isSelected,
            showCheckmark: false,
            selectedColor: AppColors.primary.withValues(alpha: 0.11),
            backgroundColor: AppColors.card,
            side: BorderSide(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.28)
                  : AppColors.border.withValues(alpha: 0.78),
            ),
            labelStyle: TextStyle(
              color: isSelected ? AppColors.primary : AppColors.textMuted,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            onSelected: (_) {
              onSelected(category);
            },
          );
        },
      ),
    );
  }
}
