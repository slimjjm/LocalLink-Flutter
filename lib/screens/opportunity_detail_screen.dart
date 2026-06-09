import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_colors.dart';

class OpportunityDetailScreen extends StatefulWidget {
  final String opportunityId;
  final Map<String, dynamic> opportunity;

  const OpportunityDetailScreen({
    super.key,
    required this.opportunityId,
    required this.opportunity,
  });

  @override
  State<OpportunityDetailScreen> createState() =>
      _OpportunityDetailScreenState();
}

class _OpportunityDetailScreenState
    extends State<OpportunityDetailScreen> {
  bool isJoining = false;
  bool isGoing = false;
  int attendeeCount = 0;

  @override
  void initState() {
    super.initState();

    attendeeCount = int.tryParse(
          widget.opportunity['attendeeCount']?.toString() ?? '0',
        ) ??
        0;

    checkIfGoing();
  }

  Future<void> checkIfGoing() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final attendeeDoc = await FirebaseFirestore.instance
        .collection('opportunities')
        .doc(widget.opportunityId)
        .collection('attendees')
        .doc(user.uid)
        .get();

    if (!mounted) return;

    setState(() {
      isGoing = attendeeDoc.exists;
    });
  }

Future<void> joinOpportunity() async {
  try {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to join.'),
        ),
      );
      return;
    }

    if (isGoing || isJoining) return;

    setState(() {
      isJoining = true;
    });

    final opportunityRef = FirebaseFirestore.instance
        .collection('opportunities')
        .doc(widget.opportunityId);

    final attendeeRef =
        opportunityRef.collection('attendees').doc(user.uid);

    final attendeeDoc = await attendeeRef.get();

    if (!attendeeDoc.exists) {
      await attendeeRef.set({
        'userId': user.uid,
        'joinedAt': Timestamp.now(),
      });

      await opportunityRef.update({
        'attendeeCount': FieldValue.increment(1),
      });

      if (!mounted) return;

      setState(() {
        attendeeCount++;
        isGoing = true;
        isJoining = false;
      });
    } else {
      if (!mounted) return;

      setState(() {
        isGoing = true;
        isJoining = false;
      });
    }
  } catch (e) {
    if (!mounted) return;

    setState(() {
      isJoining = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Unable to join opportunity',
        ),
      ),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    final opportunity = widget.opportunity;

    final title = opportunity['title'] ?? '';
    final description = opportunity['description'] ?? '';
    final category = opportunity['category'] ?? '';
    final location = opportunity['location'] ?? '';
    final organiser = opportunity['organiserName'] ?? '';
    final eventDate = opportunity['eventDate'];
    final photoUrl =
    opportunity['photoUrl'];

    String formattedDate = '';

    if (eventDate != null) {
      final date = eventDate.toDate();

      const months = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];

      formattedDate =
          '${date.day} ${months[date.month]} ${date.year}';
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            if (photoUrl != null &&
    photoUrl.toString().isNotEmpty)
  Container(
    height: 220,
    width: double.infinity,
    margin: const EdgeInsets.only(
      bottom: 20,
    ),
    decoration: BoxDecoration(
      borderRadius:
          BorderRadius.circular(24),
      image: DecorationImage(
        image: NetworkImage(
          photoUrl,
        ),
        fit: BoxFit.cover,
      ),
    ),
  ),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    category,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (formattedDate.isNotEmpty) ...[
              _InfoTile(
                icon: Icons.calendar_month,
                title: 'Date',
                value: formattedDate,
              ),
              const SizedBox(height: 12),
            ],

            _InfoTile(
              icon: Icons.location_on,
              title: 'Location',
              value: location,
            ),

            const SizedBox(height: 12),

            _InfoTile(
              icon: Icons.person,
              title: 'Organiser',
              value: organiser,
            ),

            const SizedBox(height: 12),

            _InfoTile(
              icon: Icons.people,
              title: 'Attending',
              value: '$attendeeCount people',
            ),

            const SizedBox(height: 24),

            const Text(
              'About',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              description,
              style: const TextStyle(
                height: 1.5,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 32),

            const Text(
              'Discussion',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 16),

            const _CommentTile(
              name: 'Sarah',
              comment: 'Can beginners come along?',
            ),

            const SizedBox(height: 12),

            const _CommentTile(
              name: 'Burntwood Runners',
              comment: 'Absolutely. All abilities welcome.',
            ),

            const SizedBox(height: 12),

            const _CommentTile(
              name: 'Tom',
              comment: 'Where do we park?',
            ),

            const SizedBox(height: 12),

            const _CommentTile(
              name: 'Burntwood Runners',
              comment: 'Visitor centre car park.',
            ),

            const SizedBox(height: 24),

           Row(
  children: [
    Expanded(
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Write a comment...',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    ),

    const SizedBox(width: 8),

    Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: const Icon(
          Icons.send,
          color: Colors.white,
        ),
        onPressed: () {
          ScaffoldMessenger.of(context)
              .showSnackBar(
            const SnackBar(
              content: Text(
                'Comments coming soon',
              ),
            ),
          );
        },
      ),
    ),
  ],
),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    isJoining || isGoing
                        ? null
                        : joinOpportunity,
                icon: Icon(
                  isGoing
                      ? Icons.check_circle
                      : Icons.check,
                ),
                label: Text(
                  isJoining
                      ? 'Joining...'
                      : isGoing
                          ? 'Going ✓'
                          : 'I\'m Going',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isGoing
                          ? Colors.green
                          : AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final String name;
  final String comment;

  const _CommentTile({
    required this.name,
    required this.comment,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(comment),
        ],
      ),
    );
  }
}