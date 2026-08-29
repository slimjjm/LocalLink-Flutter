import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MyOpportunitiesScreen extends StatelessWidget {
  const MyOpportunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please sign in.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Activities')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Created By Me',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 12),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('opportunities')
                  .where('createdBy', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return const _EmptyCard(
                    text: 'You have not created any activities yet.',
                  );
                }

                return Column(
                  children: docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;

                    return _OpportunityTile(
                      title: data['title'] ?? '',
                      subtitle: data['location'] ?? '',
                      attendeeCount:
                          (data['attendeeCount'] as num?)?.toInt() ?? 0,
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 32),

            const Text(
              'Going To',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 12),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collectionGroup('attendees')
                  .snapshots(),
              builder: (context, attendeeSnapshot) {
                if (!attendeeSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final attendeeDocs = attendeeSnapshot.data!.docs;

                final myAttendees = attendeeDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;

                  return data['userId'] == uid;
                }).toList();

                if (myAttendees.isEmpty) {
                  return const _EmptyCard(
                    text: 'You have not joined any activities yet.',
                  );
                }

                return Column(
                  children: myAttendees.map((attendee) {
                    final opportunityRef = attendee.reference.parent.parent;

                    if (opportunityRef == null) {
                      return const SizedBox.shrink();
                    }

                    return FutureBuilder<DocumentSnapshot>(
                      future: opportunityRef.get(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || !snapshot.data!.exists) {
                          return const SizedBox.shrink();
                        }

                        final data =
                            snapshot.data!.data() as Map<String, dynamic>;

                        return _OpportunityTile(
                          title: data['title'] ?? '',
                          subtitle: data['location'] ?? '',
                          attendeeCount:
                              (data['attendeeCount'] as num?)?.toInt() ?? 0,
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// EMPTY CARD
// =====================================================

class _EmptyCard extends StatelessWidget {
  final String text;

  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
    );
  }
}

// =====================================================
// OPPORTUNITY TILE
// =====================================================

class _OpportunityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final int attendeeCount;

  const _OpportunityTile({
    required this.title,
    required this.subtitle,
    required this.attendeeCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.event_available, size: 28),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 4),

                Text(subtitle, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$attendeeCount going',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: 4),

              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ],
      ),
    );
  }
}
