import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/trust_safety_service.dart';
import '../theme/app_colors.dart';

const List<String> localLinkReportReasons = [
  'Spam',
  'Harassment or abusive behaviour',
  'Inappropriate content',
  'Scam or fraud',
  'False information',
  'Unsafe behaviour',
  'Other',
];

Future<void> showReportSheet({
  required BuildContext context,
  required String reportType,
  required String targetId,
  required String reportedUserId,
  String? targetPath,
  String? parentId,
  String? targetPreview,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(
      reportType: reportType,
      targetId: targetId,
      reportedUserId: reportedUserId,
      targetPath: targetPath,
      parentId: parentId,
      targetPreview: targetPreview,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  final String reportType;
  final String targetId;
  final String reportedUserId;
  final String? targetPath;
  final String? parentId;
  final String? targetPreview;

  const _ReportSheet({
    required this.reportType,
    required this.targetId,
    required this.reportedUserId,
    this.targetPath,
    this.parentId,
    this.targetPreview,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final TrustSafetyService _trustSafetyService = TrustSafetyService();
  final TextEditingController _descriptionController = TextEditingController();

  String _selectedReason = localLinkReportReasons.first;
  bool _submitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to report this.')),
      );
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await _trustSafetyService.submitReport(
        reportType: widget.reportType,
        targetId: widget.targetId,
        reportedUserId: widget.reportedUserId,
        reporterUserId: user.uid,
        reason: _selectedReason,
        description: _descriptionController.text,
        targetPath: widget.targetPath,
        parentId: widget.parentId,
        targetPreview: widget.targetPreview,
      );

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Thanks for helping keep LocalLink safe. We will review your report.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Report failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Report this',
                style: TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Tell us what feels wrong. Reports are reviewed by LocalLink.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: _selectedReason,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                items: localLinkReportReasons
                    .map(
                      (reason) =>
                          DropdownMenuItem(value: reason, child: Text(reason)),
                    )
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (reason) {
                        if (reason == null) return;

                        setState(() {
                          _selectedReason = reason;
                        });
                      },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _descriptionController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'Add details (optional)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.charcoal,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(_submitting ? 'Submitting...' : 'Submit report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
