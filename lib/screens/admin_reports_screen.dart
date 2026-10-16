import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/admin_access_service.dart';
import '../theme/app_colors.dart';
import 'claim_review_screen.dart';
import 'moderator_populate_area_screen.dart';
import 'opportunity_detail_screen.dart';
import 'profile_screen.dart';

class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({super.key});

  Future<void> _updateReport({
    required String reportId,
    required String status,
    required String actionTaken,
    String? moderatorNote,
  }) async {
    final moderator = FirebaseAuth.instance.currentUser;

    await FirebaseFirestore.instance.collection('reports').doc(reportId).set({
      'status': status,
      'actionTaken': actionTaken,
      'moderatorNote': moderatorNote,
      'resolvedAt': Timestamp.now(),
      'resolvedBy': moderator?.uid,
    }, SetOptions(merge: true));
  }

  Future<void> _removeOpportunity({
    required String reportId,
    required String opportunityId,
    required ModerationRemovalReason reason,
  }) async {
    await FirebaseFunctions.instance
        .httpsCallable('moderateReportedContent')
        .call({
          'reportId': reportId,
          'action': 'remove_opportunity',
          'targetId': opportunityId,
          'reasonCode': reason.code,
          'publicText': reason.publicText,
        });
  }

  Future<void> _deleteComment({
    required String reportId,
    required String? targetPath,
    required ModerationRemovalReason reason,
  }) async {
    if (targetPath == null || targetPath.isEmpty) {
      throw Exception('This report does not include a comment path.');
    }

    await FirebaseFunctions.instance
        .httpsCallable('moderateReportedContent')
        .call({
          'reportId': reportId,
          'action': 'remove_comment',
          'targetPath': targetPath,
          'reasonCode': reason.code,
          'publicText': reason.publicText,
        });
  }

  Future<void> _banUser({
    required String reportId,
    required String userId,
    required ModerationRemovalReason reason,
  }) async {
    await FirebaseFunctions.instance.httpsCallable('banUserForReport').call({
      'reportId': reportId,
      'userId': userId,
      'reasonCode': reason.code,
      'publicText': reason.publicText,
    });
  }

  Future<ModerationRemovalReason?> _selectRemovalReason({
    required BuildContext context,
    required String title,
  }) {
    return showDialog<ModerationRemovalReason>(
      context: context,
      builder: (_) => _ModerationReasonDialog(title: title),
    );
  }

  Future<void> _confirmAction({
    required BuildContext context,
    required String title,
    required String message,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await action();

      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Moderation action saved.')));
    } on _ModerationActionCancelled {
      return;
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Action failed: $error')));
    }
  }

  Future<void> _openReportTarget(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final reportType = data['reportType']?.toString() ?? '';

    try {
      if (reportType == 'profile') {
        await _openProfileTarget(context, data);
        return;
      }

      if (reportType == 'opportunity' || reportType == 'comment') {
        await _openOpportunityTarget(context, data);
        return;
      }

      _showTargetMessage(context, 'This report type cannot be opened yet.');
    } catch (error) {
      if (!context.mounted) return;

      _showTargetMessage(context, 'Unable to open reported item: $error');
    }
  }

  Future<void> _openOpportunityTarget(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final reportType = data['reportType']?.toString() ?? '';
    final opportunityId = reportType == 'comment'
        ? _commentParentId(data)
        : data['targetId']?.toString() ?? '';

    if (opportunityId.isEmpty) {
      _showTargetMessage(
        context,
        'This report does not include an opportunity.',
      );
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('opportunities')
        .doc(opportunityId)
        .get();

    if (!context.mounted) return;

    if (!doc.exists || doc.data() == null) {
      _showTargetMessage(context, 'That opportunity is no longer available.');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OpportunityDetailScreen(
          opportunityId: doc.id,
          opportunity: doc.data()!,
        ),
      ),
    );
  }

  Future<void> _openProfileTarget(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final userId =
        data['targetId']?.toString() ??
        data['reportedUserId']?.toString() ??
        '';

    if (userId.isEmpty) {
      _showTargetMessage(context, 'This report does not include a profile.');
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();

    if (!context.mounted) return;

    final userData = doc.data();
    final userName =
        userData?['userName']?.toString() ??
        userData?['displayName']?.toString() ??
        data['targetPreview']?.toString() ??
        'Deleted User';

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userId: userId,
          userName: userName,
          photoUrl: userData?['photoUrl']?.toString(),
        ),
      ),
    );
  }

  String _commentParentId(Map<String, dynamic> data) {
    final parentId = data['parentId']?.toString() ?? '';

    if (parentId.isNotEmpty) {
      return parentId;
    }

    final targetPath = data['targetPath']?.toString() ?? '';
    final parts = targetPath.split('/');
    final opportunityIndex = parts.indexOf('opportunities');

    if (opportunityIndex == -1 || opportunityIndex + 1 >= parts.length) {
      return '';
    }

    return parts[opportunityIndex + 1];
  }

  void _showTargetMessage(BuildContext context, String message) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AdminAccessService().isCurrentUserAdmin(),
      builder: (context, accessSnapshot) {
        if (!accessSnapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (accessSnapshot.data != true) {
          return const Scaffold(
            body: Center(child: Text('You do not have access to this area.')),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            title: const Text('Moderation'),
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('reports')
                .where('status', isEqualTo: 'open')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error;
                if (kDebugMode) {
                  debugPrint('AdminReportsScreen failed to load reports.');
                  debugPrint('AdminReportsScreen error: $error');
                  debugPrint(
                    'AdminReportsScreen stack: ${snapshot.stackTrace}',
                  );
                }

                return _ReportsError(message: _reportsErrorMessage(error));
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final reports = snapshot.data!.docs;

              if (reports.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    const _PopulateAreaCard(),
                    const SizedBox(height: 16),
                    ClaimRequestsModerationCard(
                      countStream: pendingListingClaimCountStream(),
                      onTap: () => _openClaimRequests(context),
                    ),
                    const SizedBox(height: 16),
                    const _EmptyReports(),
                  ],
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                itemCount: reports.length + 2,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const _PopulateAreaCard();
                  }
                  if (index == 1) {
                    return ClaimRequestsModerationCard(
                      countStream: pendingListingClaimCountStream(),
                      onTap: () => _openClaimRequests(context),
                    );
                  }

                  final report = reports[index - 2];
                  final data = report.data() as Map<String, dynamic>;

                  return _ReportCard(
                    reportId: report.id,
                    data: data,
                    onOpenTarget: () => _openReportTarget(context, data),
                    onDismiss: () => _confirmAction(
                      context: context,
                      title: 'Dismiss report?',
                      message:
                          'This marks the report as dismissed without taking action.',
                      action: () => _updateReport(
                        reportId: report.id,
                        status: 'dismissed',
                        actionTaken: 'dismissed',
                      ),
                    ),
                    onResolve: () => _confirmAction(
                      context: context,
                      title: 'Mark resolved?',
                      message:
                          'This closes the report without changing the reported content.',
                      action: () => _updateReport(
                        reportId: report.id,
                        status: 'resolved',
                        actionTaken: 'reviewed_no_action',
                      ),
                    ),
                    onRemoveOpportunity: () => _confirmAction(
                      context: context,
                      title: 'Remove opportunity?',
                      message:
                          'This sets the opportunity inactive so it no longer appears publicly.',
                      action: () async {
                        final reason = await _selectRemovalReason(
                          context: context,
                          title: 'Reason for removal',
                        );
                        if (reason == null) {
                          throw const _ModerationActionCancelled();
                        }
                        await _removeOpportunity(
                          reportId: report.id,
                          opportunityId: data['targetId']?.toString() ?? '',
                          reason: reason,
                        );
                      },
                    ),
                    onDeleteComment: () => _confirmAction(
                      context: context,
                      title: 'Remove comment?',
                      message:
                          'This hides the comment publicly while keeping a moderation record.',
                      action: () async {
                        final reason = await _selectRemovalReason(
                          context: context,
                          title: 'Reason for removal',
                        );
                        if (reason == null) {
                          throw const _ModerationActionCancelled();
                        }
                        await _deleteComment(
                          reportId: report.id,
                          targetPath: data['targetPath']?.toString(),
                          reason: reason,
                        );
                      },
                    ),
                    onBanUser: () => _confirmAction(
                      context: context,
                      title: 'Ban user?',
                      message:
                          'This marks the reported user as banned in Firestore.',
                      action: () async {
                        final reason = await _selectRemovalReason(
                          context: context,
                          title: 'Reason for restriction',
                        );
                        if (reason == null) {
                          throw const _ModerationActionCancelled();
                        }
                        await _banUser(
                          reportId: report.id,
                          userId: data['reportedUserId']?.toString() ?? '',
                          reason: reason,
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

Future<void> _openClaimRequests(BuildContext context) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ClaimReviewScreen()),
  );
}

class _ModerationActionCancelled implements Exception {
  const _ModerationActionCancelled();
}

class ModerationRemovalReason {
  const ModerationRemovalReason({required this.code, required this.publicText});

  final String code;
  final String publicText;
}

class _ReasonOption {
  const _ReasonOption(this.code, this.label);

  final String code;
  final String label;
}

const _moderationReasonOptions = [
  _ReasonOption('duplicate_content', 'Duplicate content'),
  _ReasonOption(
    'incorrect_or_misleading',
    'Incorrect or misleading information',
  ),
  _ReasonOption('inappropriate_content', 'Inappropriate content'),
  _ReasonOption('spam_or_advertising', 'Spam or advertising'),
  _ReasonOption('safety_concern', 'Safety concern'),
  _ReasonOption('not_suitable', 'Not suitable for LocalLink'),
  _ReasonOption('other', 'Other'),
];

class _ModerationReasonDialog extends StatefulWidget {
  const _ModerationReasonDialog({required this.title});

  final String title;

  @override
  State<_ModerationReasonDialog> createState() =>
      _ModerationReasonDialogState();
}

class _ModerationReasonDialogState extends State<_ModerationReasonDialog> {
  String _selectedCode = _moderationReasonOptions.first.code;
  final _explanationController = TextEditingController();

  @override
  void dispose() {
    _explanationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _moderationReasonOptions.firstWhere(
      (option) => option.code == _selectedCode,
    );
    final requiresExplanation = _selectedCode == 'other';
    final explanation = _explanationController.text.trim();

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedCode,
            decoration: const InputDecoration(labelText: 'Public reason'),
            items: _moderationReasonOptions
                .map(
                  (option) => DropdownMenuItem(
                    value: option.code,
                    child: Text(option.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedCode = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _explanationController,
            minLines: 2,
            maxLines: 4,
            maxLength: 180,
            decoration: InputDecoration(
              labelText: requiresExplanation
                  ? 'Public explanation'
                  : 'Optional public explanation',
              hintText:
                  'Shown to the creator. Do not include reporter or moderator details.',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: requiresExplanation && explanation.isEmpty
              ? null
              : () {
                  Navigator.pop(
                    context,
                    ModerationRemovalReason(
                      code: selected.code,
                      publicText: explanation.isEmpty
                          ? selected.label
                          : explanation,
                    ),
                  );
                },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String reportId;
  final Map<String, dynamic> data;
  final VoidCallback onDismiss;
  final VoidCallback onResolve;
  final VoidCallback onRemoveOpportunity;
  final VoidCallback onDeleteComment;
  final VoidCallback onBanUser;
  final VoidCallback onOpenTarget;

  const _ReportCard({
    required this.reportId,
    required this.data,
    required this.onDismiss,
    required this.onResolve,
    required this.onRemoveOpportunity,
    required this.onDeleteComment,
    required this.onBanUser,
    required this.onOpenTarget,
  });

  @override
  Widget build(BuildContext context) {
    final reportType = data['reportType']?.toString() ?? 'unknown';
    final reason = data['reason']?.toString() ?? 'No reason';
    final description = data['description']?.toString().trim() ?? '';
    final targetPreview = data['targetPreview']?.toString().trim() ?? '';
    final targetId = data['targetId']?.toString() ?? '';
    final reportedUserId = data['reportedUserId']?.toString() ?? '';
    final reporterUserId = data['reporterUserId']?.toString() ?? '';
    final createdAt = data['createdAt'];

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onOpenTarget,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.72)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _TypeBadge(label: reportType),
                  const Spacer(),
                  Text(
                    _dateLabel(createdAt),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                reason,
                style: const TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (targetPreview.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  targetPreview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (description.isNotEmpty) ...[
                const SizedBox(height: 9),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _IdLine(label: 'Target', value: targetId),
              _IdLine(label: 'Reported user', value: reportedUserId),
              _IdLine(label: 'Reporter', value: reporterUserId),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onOpenTarget,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(
                      reportType == 'comment'
                          ? 'Open discussion'
                          : 'Open target',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: onDismiss,
                    child: const Text('Dismiss'),
                  ),
                  OutlinedButton(
                    onPressed: onResolve,
                    child: const Text('Resolve'),
                  ),
                  if (reportType == 'opportunity')
                    FilledButton(
                      onPressed: onRemoveOpportunity,
                      child: const Text('Remove opportunity'),
                    ),
                  if (reportType == 'comment')
                    FilledButton(
                      onPressed: onDeleteComment,
                      child: const Text('Delete comment'),
                    ),
                  FilledButton.tonal(
                    onPressed: onBanUser,
                    child: const Text('Ban user'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dateLabel(dynamic value) {
    if (value is! Timestamp) {
      return '';
    }

    final date = value.toDate();
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _PopulateAreaCard extends StatelessWidget {
  const _PopulateAreaCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ModeratorPopulateAreaScreen(),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.72)),
          ),
          child: const Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.primary,
                child: Icon(Icons.add_location_alt_outlined),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Populate Area',
                      style: TextStyle(
                        color: AppColors.charcoal,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Add and manage unclaimed businesses, organisations and events.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String label;

  const _TypeBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _IdLine extends StatelessWidget {
  final String label;
  final String value;

  const _IdLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _reportsErrorMessage(Object? error) {
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'You do not have permission to view moderation reports. Please check that your admin access is active.';
  }

  return 'Reports could not be loaded. Please try again in a moment.';
}

class _ReportsError extends StatelessWidget {
  const _ReportsError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              color: AppColors.textMuted,
              size: 34,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReports extends StatelessWidget {
  const _EmptyReports();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_user_outlined,
              color: AppColors.textMuted,
              size: 38,
            ),
            SizedBox(height: 12),
            Text(
              'No open reports',
              style: TextStyle(
                color: AppColors.charcoal,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'New user reports will appear here for review.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
