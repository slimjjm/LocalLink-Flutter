import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_colors.dart';
import 'opportunity_detail_screen.dart';

class SavedOpportunitiesScreen extends StatelessWidget {
  const SavedOpportunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid =
        FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(
          child: Text('Please log in.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Saved Opportunities'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('savedOpportunities')
            .orderBy(
              'savedAt',
              descending: true,
            )
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final savedDocs =
              snapshot.data!.docs;

          if (savedDocs.isEmpty) {
            return const Center(
              child: Text(
                'No saved opportunities yet',
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: savedDocs.length,
            itemBuilder: (context, index) {
              final data =
                  savedDocs[index].data()
                      as Map<String, dynamic>;

              final opportunityId =
                  data['opportunityId'];

              if (opportunityId == null) {
                return const SizedBox();
              }

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('opportunities')
                    .doc(opportunityId)
                    .get(),
                builder: (context, oppSnapshot) {
                  if (!oppSnapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: LinearProgressIndicator(),
                    );
                  }

                  if (!oppSnapshot.data!.exists) {
                    return const SizedBox();
                  }

                  final opportunity =
                      oppSnapshot.data!.data()
                          as Map<String, dynamic>;

                  final title =
                      opportunity['title'] ?? '';

                  final category =
                      opportunity['category'] ?? '';

                  final location =
                      opportunity['location'] ?? '';

                  return Card(
                    margin: const EdgeInsets.only(
                      bottom: 12,
                    ),
                    child: ListTile(
                      title: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '$category\n$location',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(
                        Icons.chevron_right,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                OpportunityDetailScreen(
                              opportunityId:
                                  opportunityId,
                              opportunity:
                                  opportunity,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}