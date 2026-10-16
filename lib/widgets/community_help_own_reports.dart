import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/community_help_lifecycle.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';

typedef CommunityHelpReportsLoader =
    Stream<List<DocumentSnapshot<Map<String, dynamic>>>> Function(
      String userId,
    );

/// Created reports and verified claims only; errors never mean an empty list.
class CommunityHelpOwnReports extends StatefulWidget {
  const CommunityHelpOwnReports({
    super.key,
    required this.userId,
    required this.reportBuilder,
    this.loadReports,
  });

  // Anonymous users are represented by null by the calling screen.
  final String? userId;
  final Widget Function(DocumentSnapshot<Map<String, dynamic>>) reportBuilder;
  final CommunityHelpReportsLoader? loadReports;

  static Stream<List<DocumentSnapshot<Map<String, dynamic>>>> watchReports(
    String userId,
  ) => FirebaseFirestore.instance
      .collection('communityHelpPosts')
      .where('createdBy', isEqualTo: userId)
      .limit(30)
      .snapshots()
      .asyncMap((createdSnapshot) async {
        final claimedSnapshot = await FirebaseFirestore.instance
            .collection('communityHelpPosts')
            .where('communityAdded', isEqualTo: true)
            .where('claimStatus', isEqualTo: 'approved')
            .where('ownerId', isEqualTo: userId)
            .limit(30)
            .get();
        return <String, DocumentSnapshot<Map<String, dynamic>>>{
          for (final doc in createdSnapshot.docs) doc.id: doc,
          for (final doc in claimedSnapshot.docs) doc.id: doc,
        }.values.toList();
      });

  @override
  State<CommunityHelpOwnReports> createState() =>
      _CommunityHelpOwnReportsState();
}

class _CommunityHelpOwnReportsState extends State<CommunityHelpOwnReports> {
  Stream<List<DocumentSnapshot<Map<String, dynamic>>>>? _reports;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CommunityHelpOwnReports oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _load();
  }

  void _load() {
    _attempt++;
    final userId = widget.userId;
    if (userId == null) {
      _reports = null;
      return;
    }
    try {
      _reports = (widget.loadReports ?? CommunityHelpOwnReports.watchReports)(
        userId,
      );
    } catch (error, stack) {
      _reports = Stream.error(error, stack);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId == null) return const SizedBox.shrink();

    return StreamBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
      key: ValueKey(_attempt),
      stream: _reports,
      builder: (context, snapshot) {
        final docs = snapshot.data?.toList() ?? [];
        docs.sort((a, b) {
          final aCreated = CommunityHelpLifecycle.asDateTime(
            a.data()?['createdAt'],
          );
          final bCreated = CommunityHelpLifecycle.asDateTime(
            b.data()?['createdAt'],
          );
          if (aCreated != null && bCreated != null) {
            return bCreated.compareTo(aCreated);
          }
          return 0;
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your reports',
              style: TextStyle(
                color: AppColors.charcoal,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            if (snapshot.hasError)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "We couldn't load your reports. Please try again.",
                    style: LocalLinkTextStyles.metadata,
                  ),
                  TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('Try again'),
                  ),
                ],
              )
            else if (!snapshot.hasData)
              const Center(child: CircularProgressIndicator())
            else if (docs.isEmpty)
              const Text(
                'Reports you create or claim will appear here.',
                style: LocalLinkTextStyles.metadata,
              )
            else
              ...docs
                  .take(6)
                  .map(
                    (doc) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: widget.reportBuilder(doc),
                    ),
                  ),
          ],
        );
      },
    );
  }
}
