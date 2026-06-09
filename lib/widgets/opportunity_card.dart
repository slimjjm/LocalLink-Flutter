import 'package:flutter/material.dart';

class OpportunityCard extends StatelessWidget {

  final String title;
  final String category;
  final String description;
  final String organiser;

  const OpportunityCard({
    super.key,
    required this.title,
    required this.category,
    required this.description,
    required this.organiser,
  });

  @override
  Widget build(BuildContext context) {

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [

            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(category),

            const SizedBox(height: 8),

            Text(description),

            const SizedBox(height: 8),

            Text(
              organiser,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}