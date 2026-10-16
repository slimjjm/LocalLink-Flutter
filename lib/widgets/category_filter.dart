import 'package:flutter/material.dart';

import '../theme/local_link_design_tokens.dart';
import 'local_link_chip.dart';

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
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: LocalLinkSpacing.xs),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = selectedCategory == category;

          return LocalLinkChip(
            label: category,
            selected: isSelected,
            onSelected: (_) {
              onSelected(category);
            },
          );
        },
      ),
    );
  }
}
