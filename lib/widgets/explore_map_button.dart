import 'package:flutter/material.dart';

import '../screens/opportunity_map_screen.dart';
import '../theme/app_colors.dart';

class ExploreMapButton extends StatelessWidget {
  const ExploreMapButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: const Icon(Icons.map_outlined),
        label: const Text('Explore on Map'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.charcoal,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(58),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OpportunityMapScreen()),
          );
        },
      ),
    );
  }
}
