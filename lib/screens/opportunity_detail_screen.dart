import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_colors.dart';
import '../services/comment_service.dart';
import '../services/attendee_service.dart';
import '../services/local_link_share_service.dart';
import '../widgets/report_sheet.dart';
import '../utils/helpers.dart';
import 'profile_screen.dart';
import '../services/review_service.dart';
import 'package:locallink_flutter/screens/recurring_series_manager_screen.dart';

Future<Map<String, dynamic>?> showRecurringSeriesManager(
  BuildContext context,
  Map<String, dynamic> opportunity,
) async {
  final eventDate = (opportunity['eventDate'] as Timestamp).toDate();

  final repeatType = opportunity['repeatType'] ?? 'weekly';

  final repeatEndDate = opportunity['repeatEndDate'] == null
      ? null
      : (opportunity['repeatEndDate'] as Timestamp).toDate();

  final dates = <DateTime>[];

  DateTime current = eventDate;

  while (repeatEndDate == null ||
      current.isBefore(repeatEndDate) ||
      current.isAtSameMomentAs(repeatEndDate)) {
    dates.add(current);

    switch (repeatType) {
      case 'daily':
        current = current.add(const Duration(days: 1));
        break;

      case 'weekly':
        current = current.add(const Duration(days: 7));
        break;

      case 'fortnightly':
        current = current.add(const Duration(days: 14));
        break;

      case 'monthly':
        current = DateTime(
          current.year,
          current.month + 1,
          current.day,
          current.hour,
          current.minute,
        );
        break;

      default:
        return null;
    }

    if (dates.length >= 30) break;
  }

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: SizedBox(
          height: 500,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Choose occurrence',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),

              Expanded(
                child: ListView.builder(
                  itemCount: dates.length,
                  itemBuilder: (context, index) {
                    final date = dates[index];

                    return ListTile(
                      leading: const Icon(Icons.event),
                      title: Text('${date.day}/${date.month}/${date.year}'),
                      subtitle: Text(
                        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(context, {
                          'editType': 'occurrence',
                          'date': date,
                        });
                      },
                    );
                  },
                ),
              ),

              const Divider(),

              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Entire Series'),
                subtitle: const Text('Edit recurring template'),
                onTap: () {
                  Navigator.pop(context, {'editType': 'series'});
                },
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    },
  );
}

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

class _OpportunityDetailScreenState extends State<OpportunityDetailScreen> {
  bool isJoining = false;
  bool isGoing = false;
  int attendeeCount = 0;

  final commentService = CommentService();

  final attendeeService = AttendeeService();

  final reviewService = ReviewService();

  final commentController = TextEditingController();

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  Future<void> _reportOpportunity() async {
    final reportedUserId = widget.opportunity['createdBy']?.toString() ?? '';

    if (reportedUserId.isEmpty) {
      return;
    }

    await showReportSheet(
      context: context,
      reportType: 'opportunity',
      targetId: widget.opportunityId,
      targetPath: 'opportunities/${widget.opportunityId}',
      targetPreview: widget.opportunity['title']?.toString(),
      reportedUserId: reportedUserId,
    );
  }

  Future<void> _reportComment({
    required String commentId,
    required Map<String, dynamic> data,
  }) async {
    final reportedUserId = data['userId']?.toString() ?? '';

    if (reportedUserId.isEmpty) {
      return;
    }

    await showReportSheet(
      context: context,
      reportType: 'comment',
      targetId: commentId,
      targetPath: 'opportunities/${widget.opportunityId}/comments/$commentId',
      parentId: widget.opportunityId,
      targetPreview: data['text']?.toString(),
      reportedUserId: reportedUserId,
    );
  }

  Future<void> _editComment({
    required String commentId,
    required String currentText,
  }) async {
    final controller = TextEditingController(text: currentText);

    final save = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Comment'),
          content: TextField(controller: controller, maxLines: 4),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (save != true) return;

    await commentService.updateComment(
      opportunityId: widget.opportunityId,
      commentId: commentId,
      text: controller.text.trim(),
    );
  }

  Future<void> _deleteComment(String commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Comment?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await commentService.deleteComment(
      opportunityId: widget.opportunityId,
      commentId: commentId,
    );
  }

  @override
  void initState() {
    super.initState();

    attendeeCount =
        int.tryParse(widget.opportunity['attendeeCount']?.toString() ?? '0') ??
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please log in to join.')));
        return;
      }

      if (isGoing || isJoining) return;

      setState(() {
        isJoining = true;
      });

      final opportunityRef = FirebaseFirestore.instance
          .collection('opportunities')
          .doc(widget.opportunityId);

      final attendeeRef = opportunityRef.collection('attendees').doc(user.uid);

      var joinedNow = false;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final attendeeDoc = await transaction.get(attendeeRef);

        if (attendeeDoc.exists) {
          return;
        }

        transaction.set(attendeeRef, {
          'userId': user.uid,
          'userName': user.displayName ?? 'User',
          'photoUrl': user.photoURL,
          'joinedAt': Timestamp.now(),
        });

        transaction.update(opportunityRef, {
          'attendeeCount': FieldValue.increment(1),
        });

        joinedNow = true;
      });

      if (joinedNow) {
        final organiserId = widget.opportunity['createdBy'];

        if (organiserId != null && organiserId != user.uid) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(organiserId)
              .collection('notifications')
              .add({
                'type': 'opportunity_join',
                'title': 'New attendee',
                'body':
                    '${user.displayName ?? 'Someone'} joined "${widget.opportunity['title'] ?? 'your activity'}"',
                'createdAt': Timestamp.now(),
                'isRead': false,
                'opportunityId': widget.opportunityId,
                'userId': user.uid,
              });
        }

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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to join activity')));
    }
  }

  Future<void> _postComment() async {
    final text = commentController.text.trim();

    if (text.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    await commentService.addComment(
      opportunityId: widget.opportunityId,
      userId: user.uid,
      userName: user.displayName ?? 'User',
      text: text,
    );
    final organiserId = widget.opportunity['createdBy'];

    if (organiserId != null && organiserId != user.uid) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(organiserId)
          .collection('notifications')
          .add({
            'type': 'opportunity_comment',

            'title': 'New comment',

            'body':
                '${user.displayName ?? 'Someone'} commented on "${widget.opportunity['title'] ?? 'your activity'}"',

            'createdAt': Timestamp.now(),

            'isRead': false,

            'opportunityId': widget.opportunityId,

            'userId': user.uid,
          });
    }

    commentController.clear();
  }

  String formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();

    final difference = DateTime.now().difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} mins ago';
    }

    if (difference.inHours < 24) {
      return '${difference.inHours} hrs ago';
    }

    if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    }

    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final opportunity = widget.opportunity;

    final title = opportunity['title'] ?? '';
    final description = opportunity['description'] ?? '';
    final category = opportunity['category'] ?? '';
    final location = opportunity['location'] ?? '';
    final organiser = opportunity['organiserName'] ?? '';
    final eventDate = opportunity['eventDate'];
    final eventTime = opportunity['eventTime'] ?? '';
    final photoUrl = opportunity['photoUrl'];

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

      formattedDate = '${date.day} ${months[date.month]} ${date.year}';
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: () async {
              try {
                await LocalLinkShareService().shareItem(
                  item: LocalLinkShareItem(
                    type: LocalLinkShareItemType.activity,
                    id: widget.opportunityId,
                    data: widget.opportunity,
                  ),
                );
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sharing could not be started.'),
                  ),
                );
              }
            },
          ),

          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) async {
              if (value == 'report') {
                await _reportOpportunity();
              }
            },
            itemBuilder: (context) {
              return const [
                PopupMenuItem(value: 'report', child: Text('Report activity')),
              ];
            },
          ),

          if (FirebaseAuth.instance.currentUser?.uid ==
              widget.opportunity['createdBy'])
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                String editChoice = 'single';

                if (widget.opportunity['isRecurring'] == true) {
                  final result = await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RecurringSeriesManagerScreen(
                        opportunityId: widget.opportunityId,
                        seriesId: widget.opportunity['seriesId'],
                      ),
                    ),
                  );

                  if (result == null) {
                    return;
                  }

                  editChoice = result['editType'];
                }
                final titleController = TextEditingController(
                  text: widget.opportunity['title'],
                );

                final descriptionController = TextEditingController(
                  text: widget.opportunity['description'],
                );

                final save = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('Edit Activity'),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: titleController,
                              decoration: const InputDecoration(
                                labelText: 'Title',
                              ),
                            ),

                            const SizedBox(height: 12),

                            TextField(
                              controller: descriptionController,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: 'Description',
                              ),
                            ),
                            const SizedBox(height: 12),

                            ElevatedButton.icon(
                              icon: const Icon(Icons.calendar_month),
                              label: const Text('Change Date'),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime(2035),
                                );

                                if (picked == null) return;

                                await FirebaseFirestore.instance
                                    .collection('opportunities')
                                    .doc(widget.opportunityId)
                                    .update({
                                      'eventDate': Timestamp.fromDate(picked),
                                    });
                              },
                            ),

                            ElevatedButton.icon(
                              icon: const Icon(Icons.access_time),
                              label: const Text('Change Time'),
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.now(),
                                );

                                if (picked == null) return;

                                await FirebaseFirestore.instance
                                    .collection('opportunities')
                                    .doc(widget.opportunityId)
                                    .update({
                                      'eventTime': picked.format(context),
                                    });
                              },
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context, false);
                          },
                          child: const Text('Cancel'),
                        ),

                        TextButton(
                          onPressed: () {
                            Navigator.pop(context, true);
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    );
                  },
                );

                if (save != true) return;

                final currentRef = FirebaseFirestore.instance
                    .collection('opportunities')
                    .doc(widget.opportunityId);

                await currentRef.update({
                  'title': titleController.text.trim(),

                  'description': descriptionController.text.trim(),
                });

                if (widget.opportunity['isRecurring'] == true &&
                    editChoice == 'series') {
                  final currentSnapshot = await currentRef.get();

                  final nextOccurrenceId = currentSnapshot
                      .data()?['nextOccurrenceId'];

                  if (nextOccurrenceId != null) {
                    await FirebaseFirestore.instance
                        .collection('opportunities')
                        .doc(nextOccurrenceId)
                        .update({
                          'title': titleController.text.trim(),

                          'description': descriptionController.text.trim(),
                        });
                  }
                }

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Activity updated')),
                );
              },
            ),
          if (widget.opportunity['isRecurring'] == true)
            IconButton(
              icon: const Icon(Icons.event_busy),
              tooltip: 'End Series',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('End Recurring Series?'),
                      content: const Text(
                        'No further occurrences will be created.\n\nExisting occurrences will remain.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context, false);
                          },
                          child: const Text('Cancel'),
                        ),

                        TextButton(
                          onPressed: () {
                            Navigator.pop(context, true);
                          },
                          child: const Text('End Series'),
                        ),
                      ],
                    );
                  },
                );

                if (confirm != true) {
                  return;
                }

                await FirebaseFirestore.instance
                    .collection('opportunities')
                    .doc(widget.opportunityId)
                    .update({
                      'seriesStatus': 'ended',

                      'updatedAt': FieldValue.serverTimestamp(),
                    });

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Recurring series ended.')),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Delete Activity?'),
                    content: const Text('This cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context, false);
                        },
                        child: const Text('Cancel'),
                      ),

                      TextButton(
                        onPressed: () {
                          Navigator.pop(context, true);
                        },
                        child: const Text('Delete'),
                      ),
                    ],
                  );
                },
              );

              if (confirm != true) return;

              await FirebaseFirestore.instance
                  .collection('opportunities')
                  .doc(widget.opportunityId)
                  .delete();

              if (!mounted) return;

              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photoUrl != null && photoUrl.toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.network(
                    photoUrl,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        height: 220,
                        width: double.infinity,
                        color: AppColors.activityBlue.withValues(alpha: 0.08),
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 220,
                        width: double.infinity,
                        color: AppColors.activityBlue.withValues(alpha: 0.10),
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.activityBlue,
                        ),
                      );
                    },
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      category,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
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

            if (eventTime.toString().isNotEmpty) ...[
              _InfoTile(
                icon: Icons.access_time,
                title: 'Time',
                value: eventTime.toString(),
              ),
              const SizedBox(height: 12),
            ],

            _InfoTile(
              icon: Icons.location_on,
              title: 'Location',
              value: location,
            ),

            const SizedBox(height: 12),

            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.opportunity['createdBy'])
                  .get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox();
                }

                final userData = snapshot.data!.data() as Map<String, dynamic>?;

                final photoUrl = userData?['photoUrl'];

                final averageRating = (userData?['averageRating'] ?? 0)
                    .toDouble();

                final reviewCount = userData?['reviewCount'] ?? 0;

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(
                          userId: widget.opportunity['createdBy'],
                          userName: organiser,
                          photoUrl: photoUrl,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        photoUrl != null && photoUrl.toString().isNotEmpty
                            ? CircleAvatar(
                                radius: 28,
                                backgroundImage: NetworkImage(photoUrl),
                                onBackgroundImageError:
                                    (exception, stackTrace) {},
                              )
                            : CircleAvatar(
                                radius: 28,
                                child: Text(
                                  safeInitial(
                                    userData?['userName']?.toString() ??
                                        organiser,
                                  ),
                                ),
                              ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userData?['userName']?.toString() ?? organiser,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),

                              const SizedBox(height: 4),

                              Text('$reviewCount reviews'),
                            ],
                          ),
                        ),

                        Column(
                          children: [
                            const Icon(Icons.star, color: Colors.amber),

                            Text(averageRating.toStringAsFixed(1)),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('savedOpportunities')
                  .doc(widget.opportunityId)
                  .snapshots(),
              builder: (context, snapshot) {
                final isSaved = snapshot.data?.exists ?? false;

                return SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: Icon(
                      isSaved ? Icons.bookmark : Icons.bookmark_border,
                    ),
                    label: Text(isSaved ? 'Saved' : 'Save Activity'),
                    onPressed: () async {
                      if (uid == null) return;

                      final ref = FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .collection('savedOpportunities')
                          .doc(widget.opportunityId);

                      if (isSaved) {
                        await ref.delete();
                      } else {
                        await ref.set({
                          'opportunityId': widget.opportunityId,
                          'savedAt': Timestamp.now(),
                        });
                      }
                    },
                  ),
                );
              },
            ),

            const SizedBox(height: 12),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.star_outline),
                label: const Text('Review Organiser'),
                onPressed: () async {
                  final user = FirebaseAuth.instance.currentUser;

                  if (user == null) return;

                  final alreadyReviewed = await reviewService.hasReviewed(
                    organiserId: widget.opportunity['createdBy'],
                    reviewerId: user.uid,
                  );

                  if (alreadyReviewed) {
                    if (!mounted) return;

                    final attendeeDoc = await FirebaseFirestore.instance
                        .collection('opportunities')
                        .doc(widget.opportunityId)
                        .collection('attendees')
                        .doc(user.uid)
                        .get();

                    if (!attendeeDoc.exists) {
                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('You must attend before reviewing'),
                        ),
                      );

                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'You have already reviewed this organiser',
                        ),
                      ),
                    );

                    return;
                  }

                  int rating = 5;

                  final controller = TextEditingController();

                  final submit = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return StatefulBuilder(
                        builder: (context, setDialogState) {
                          return AlertDialog(
                            title: const Text('Review Organiser'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DropdownButton<int>(
                                  value: rating,
                                  isExpanded: true,
                                  items: [1, 2, 3, 4, 5]
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text('$e Stars'),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }

                                    setDialogState(() {
                                      rating = value;
                                    });
                                  },
                                ),

                                const SizedBox(height: 12),

                                TextField(
                                  controller: controller,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    hintText: 'Write review',
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context, false);
                                },
                                child: const Text('Cancel'),
                              ),

                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context, true);
                                },
                                child: const Text('Submit'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );

                  if (submit != true) return;

                  await reviewService.addReview(
                    organiserId: widget.opportunity['createdBy'],

                    reviewerId: user.uid,

                    reviewerName: user.displayName ?? 'User',

                    rating: rating,

                    text: controller.text.trim(),
                  );

                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Review submitted')),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            _InfoTile(
              icon: Icons.people,
              title: 'Attending',
              value: attendeeCount == 0
                  ? 'No attendees yet'
                  : attendeeCount == 1
                  ? '1 attendee'
                  : '$attendeeCount attendees',
            ),
            const SizedBox(height: 12),

            const Text(
              'Who\'s Going',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot>(
              stream: attendeeService.attendeesStream(widget.opportunityId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox();
                }

                final attendees = snapshot.data!.docs;

                if (attendees.isEmpty) {
                  return const SizedBox();
                }

                return SizedBox(
                  height: 95,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: attendees.length,
                    itemBuilder: (context, index) {
                      final data =
                          attendees[index].data() as Map<String, dynamic>;

                      final fullName = data['userName'] ?? 'User';

                      final name = fullName.split(' ').first;

                      final photoUrl = data['photoUrl'];

                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileScreen(
                                userId: data['userId'],
                                userName: data['userName'] ?? 'User',
                                photoUrl: data['photoUrl'],
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Column(
                            children: [
                              photoUrl != null && photoUrl.toString().isNotEmpty
                                  ? CircleAvatar(
                                      radius: 24,
                                      backgroundImage: NetworkImage(photoUrl),
                                      onBackgroundImageError:
                                          (exception, stackTrace) {},
                                    )
                                  : CircleAvatar(
                                      radius: 22,
                                      child: Text(safeInitial(name)),
                                    ),

                              const SizedBox(height: 4),

                              SizedBox(
                                width: 70,
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            const Text(
              'About',

              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 12),

            Text(
              description,
              style: const TextStyle(height: 1.5, fontSize: 16),
            ),

            const SizedBox(height: 32),

            const SizedBox(height: 24),

            const Text(
              'Discussion',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            StreamBuilder<QuerySnapshot>(
              stream: commentService.commentsStream(widget.opportunityId),

              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final comments = snapshot.data!.docs;

                if (comments.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Be the first to comment'),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final data = comments[index].data() as Map<String, dynamic>;
                    final commentId = comments[index].id;

                    final currentUser = FirebaseAuth.instance.currentUser;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ProfileScreen(
                                          userId: data['userId'],
                                          userName: data['userName'] ?? 'User',
                                          photoUrl: null,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    data['userName'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),

                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_horiz),
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      await _editComment(
                                        commentId: commentId,
                                        currentText:
                                            data['text']?.toString() ?? '',
                                      );
                                    }

                                    if (value == 'delete') {
                                      await _deleteComment(commentId);
                                    }

                                    if (value == 'report') {
                                      await _reportComment(
                                        commentId: commentId,
                                        data: data,
                                      );
                                    }
                                  },
                                  itemBuilder: (context) {
                                    final isOwner =
                                        currentUser?.uid == data['userId'];

                                    return [
                                      if (isOwner)
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit comment'),
                                        ),
                                      if (isOwner)
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete comment'),
                                        ),
                                      if (!isOwner)
                                        const PopupMenuItem(
                                          value: 'report',
                                          child: Text('Report comment'),
                                        ),
                                    ];
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),

                            Text(data['text'] ?? ''),

                            const SizedBox(height: 8),

                            Text(
                              formatTimestamp(data['createdAt'] as Timestamp),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 16),

            TextField(
              controller: commentController,
              decoration: InputDecoration(
                hintText: 'Write a comment',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () async {
                    await _postComment();
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isJoining || isGoing ? null : joinOpportunity,
                icon: Icon(isGoing ? Icons.check_circle : Icons.check),
                label: Text(
                  isJoining
                      ? 'Joining...'
                      : isGoing
                      ? 'Going ✓'
                      : 'I\'m Going',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isGoing ? Colors.green : AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
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
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
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

  const _CommentTile({required this.name, required this.comment});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(comment),
        ],
      ),
    );
  }
}
