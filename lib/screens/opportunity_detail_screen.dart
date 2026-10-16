import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/activity_categories.dart';
import '../theme/app_colors.dart';
import '../services/analytics_service.dart';
import '../services/auth_required_action.dart';
import '../services/comment_service.dart';
import '../services/community_group_service.dart';
import '../services/attendee_service.dart';
import '../services/local_link_share_service.dart';
import '../widgets/report_sheet.dart';
import '../utils/helpers.dart';
import 'listing_claim_request_screen.dart';
import 'profile_screen.dart';
import '../services/review_service.dart';
import '../theme/local_link_design_tokens.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_image.dart';
import '../widgets/local_link_section_header.dart';
import '../widgets/local_link_surface_card.dart';
import 'business_detail_screen.dart';
import 'package:locallink_flutter/screens/recurring_series_manager_screen.dart';

const List<String> _communityAudienceValues = [
  'Babies & Toddlers',
  'Children',
  'Teenagers',
  'Adults',
  'Older Adults',
  'Families',
  'All Ages',
];

const int _challengeEntryPhotoMaxBytes = 8 * 1024 * 1024;

List<String> _normaliseStringList(Object? value) {
  final values = <String>[];
  if (value is Iterable) {
    values.addAll(value.map((item) => item.toString()));
  } else if (value is String) {
    values.addAll(value.split(RegExp(r'[,;]')));
  }

  final seen = <String>{};
  return values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .where((value) => seen.add(value.toLowerCase()))
      .toList(growable: false);
}

List<String> _normaliseTags(Iterable<String> tags) {
  final seen = <String>{};
  return tags
      .map((tag) => tag.trim())
      .where((tag) => tag.length >= 2)
      .map((tag) => tag.length > 32 ? tag.substring(0, 32).trim() : tag)
      .where((tag) => seen.add(tag.toLowerCase()))
      .take(8)
      .toList(growable: false);
}

int? _readAge(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

bool _looksYouthAudience(Iterable<String> audience, String category) {
  final values = [
    category,
    ...audience,
  ].map((value) => value.toLowerCase()).join(' ');
  return values.contains('baby') ||
      values.contains('toddler') ||
      values.contains('children') ||
      values.contains('teen') ||
      values.contains('family');
}

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

String _opportunityManagerId(Map<String, dynamic> opportunity) {
  final organiserId = opportunity['organiserId']?.toString().trim() ?? '';
  if (organiserId.isNotEmpty) return organiserId;
  return opportunity['createdBy']?.toString().trim() ?? '';
}

bool _canManageOpportunity(Map<String, dynamic> opportunity, String? uid) {
  if (uid == null || uid.isEmpty) return false;
  if (_opportunityManagerId(opportunity) == uid) return true;
  final groupLeaderUserIds = opportunity['groupLeaderUserIds'];
  if (groupLeaderUserIds is Iterable &&
      groupLeaderUserIds.map((item) => item.toString()).contains(uid)) {
    return true;
  }

  final createdBy = opportunity['createdBy']?.toString();
  if (createdBy != uid) return false;

  final moderatorSeeded = opportunity['createdByModerator'] == true;
  final claimed = opportunity['listingOwnershipStatus'] == 'claimed';
  return !(moderatorSeeded && claimed);
}

bool _isYouthOrApprovalGroup(Map<String, dynamic> opportunity) {
  if (opportunity['followerAccess'] == 'approval_required') return true;
  final values = [
    opportunity['category'],
    opportunity['audience'],
    if (opportunity['tags'] is Iterable) ...(opportunity['tags'] as Iterable),
  ].map((value) => value?.toString().toLowerCase() ?? '');

  return values.any(
    (value) =>
        value.contains('youth') ||
        value.contains('child') ||
        value.contains('teen') ||
        value.contains('family') ||
        value.contains('scout'),
  );
}

String _activityKindLabel(String kind) {
  return switch (kind) {
    'session' => 'Session',
    'event' => 'Event',
    'fixture' => 'Fixture',
    'community_challenge' => 'Community challenge',
    _ => 'Activity',
  };
}

bool _isCommunityChallenge(Map<String, dynamic> opportunity) {
  return opportunity['activityKind']?.toString() == 'community_challenge';
}

DateTime? _timestampDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  return null;
}

bool _challengeIsClosed(Map<String, dynamic> opportunity) {
  final closesAt = _timestampDate(opportunity['challengeClosesAt']);
  return closesAt != null && !closesAt.isAfter(DateTime.now());
}

String _formatChallengeDate(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.day}/${date.month}/${date.year} $hour:$minute';
}

String _fixtureVenueLabel(String venue) {
  return switch (venue) {
    'away' => 'Away',
    'neutral' => 'Neutral',
    _ => 'Home',
  };
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
  bool canManageLinkedOrganisation = false;
  int attendeeCount = 0;

  final commentService = CommentService();

  final attendeeService = AttendeeService();

  final reviewService = ReviewService();
  final communityGroupService = CommunityGroupService();
  final ImagePicker imagePicker = ImagePicker();

  final commentController = TextEditingController();
  XFile? selectedEntryImage;
  Uint8List? selectedEntryImageBytes;
  bool isSubmittingEntry = false;

  Future<void> _loadLinkedOrganisationAccess() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final organisationId = widget.opportunity['organisationId']
        ?.toString()
        .trim();
    if (uid == null ||
        uid.isEmpty ||
        organisationId == null ||
        organisationId.isEmpty) {
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('organisations')
          .doc(organisationId)
          .get();
      final data = snapshot.data();
      if (data == null) return;

      final adminUserIds = data['adminUserIds'];
      final canManage =
          data['listingOwnershipStatus'] == 'claimed' &&
          (data['ownerId']?.toString() == uid ||
              (adminUserIds is Iterable &&
                  adminUserIds.map((item) => item.toString()).contains(uid)));

      if (!mounted) return;
      setState(() => canManageLinkedOrganisation = canManage);
    } catch (_) {
      if (!mounted) return;
      setState(() => canManageLinkedOrganisation = false);
    }
  }

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  Future<void> _runChallengeEntryAction({
    required Future<void> Function() action,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      await action();
      return;
    }

    await AuthRequiredAction.run(
      context,
      action: () async {
        if (!mounted) return;
        await action();
      },
    );
  }

  Future<void> _pickEntryImage() {
    return _runChallengeEntryAction(action: _pickEntryImageForRegisteredUser);
  }

  Future<void> _pickEntryImageForRegisteredUser() async {
    final picked = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (picked == null) return;

    final bytes = await picked.readAsBytes();

    if (bytes.lengthInBytes >= _challengeEntryPhotoMaxBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose a photo smaller than 8 MB.'),
        ),
      );
      return;
    }

    setState(() {
      selectedEntryImage = picked;
      selectedEntryImageBytes = bytes;
    });
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

  Future<void> _deleteComment(
    String commentId, {
    bool isChallengeEntry = false,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isChallengeEntry ? 'Delete entry?' : 'Delete comment?'),
          content: Text(
            isChallengeEntry
                ? 'This will remove your competition entry and photo.'
                : 'This cannot be undone.',
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
    LocalLinkAnalytics.instance.discoveryView(
      eventName: 'activity_view',
      source: 'other',
      category: widget.opportunity['category']?.toString() ?? '',
    );
    if (_isCommunityChallenge(widget.opportunity)) {
      LocalLinkAnalytics.instance.challengeViewed(
        challengeId: widget.opportunityId,
        category: widget.opportunity['category']?.toString() ?? '',
        location: widget.opportunity['location']?.toString() ?? '',
        supportedBusinessId:
            widget.opportunity['supportedByBusinessId']?.toString() ?? '',
      );
    }

    checkIfGoing();
    _loadLinkedOrganisationAccess();
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

      if (user == null || user.isAnonymous) {
        await AuthRequiredAction.run(context, action: joinOpportunity);
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
        // The backend creates the organiser notification after attendance commits.

        if (!mounted) return;

        setState(() {
          attendeeCount++;
          isGoing = true;
          isJoining = false;
        });
        await LocalLinkAnalytics.instance
            .logEvent('activity_attendance_started', {
              'source': 'activity_detail',
              if ((widget.opportunity['category']?.toString().trim() ?? '')
                  .isNotEmpty)
                'category': widget.opportunity['category'].toString(),
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

  Future<void> _postComment({bool asChallengeEntry = false}) async {
    final text = commentController.text.trim();
    final image = selectedEntryImage;
    final imageBytes = selectedEntryImageBytes;

    if (asChallengeEntry) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) {
        await _runChallengeEntryAction(
          action: () => _postComment(asChallengeEntry: true),
        );
        return;
      }
    }

    if (text.isEmpty && image == null) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    if (asChallengeEntry && _challengeIsClosed(widget.opportunity)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entries are closed.')));
      return;
    }

    setState(() {
      isSubmittingEntry = true;
    });

    String? imageUrl;
    String? imagePath;
    var debugStage = 'COMP_ENTRY_SUBMISSION_START';

    try {
      void logEntryStage(
        String stage, [
        Map<String, Object?> details = const {},
      ]) {
        debugStage = stage;
        _logChallengeEntryStage(stage, details);
      }

      final commentRef = commentService.newCommentReference(
        widget.opportunityId,
      );
      logEntryStage(debugStage, {
        'isChallengeEntry': asChallengeEntry,
        'authState': user.isAnonymous ? 'anonymous' : 'signed_in',
        'providerIds': user.providerData
            .map((provider) => provider.providerId)
            .toList(growable: false),
        'opportunityId': widget.opportunityId,
        'commentId': commentRef.id,
        'hasText': text.isNotEmpty,
        'hasImage': image != null,
      });

      if (image != null && imageBytes != null) {
        if (imageBytes.lengthInBytes >= _challengeEntryPhotoMaxBytes) {
          throw StateError('Please choose a photo smaller than 8 MB.');
        }

        debugStage = 'COMP_ENTRY_STORAGE_UPLOAD_START';
        imagePath =
            'opportunityCommentPhotos/${widget.opportunityId}/${user.uid}/${commentRef.id}.jpg';
        logEntryStage(debugStage, {
          'path': _redactedChallengeEntryImagePath(
            opportunityId: widget.opportunityId,
            commentId: commentRef.id,
          ),
          'contentType': 'image/jpeg',
          'metadataKeys': ['ownerId', 'opportunityId', 'commentId'],
          'bytes': imageBytes.lengthInBytes,
        });
        final ref = FirebaseStorage.instance.ref().child(imagePath);
        await ref.putData(
          imageBytes,
          SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: {
              'ownerId': user.uid,
              'opportunityId': widget.opportunityId,
              'commentId': commentRef.id,
            },
          ),
        );
        debugStage = 'COMP_ENTRY_STORAGE_UPLOAD_OK';
        logEntryStage(debugStage, {
          'path': _redactedChallengeEntryImagePath(
            opportunityId: widget.opportunityId,
            commentId: commentRef.id,
          ),
        });
        imageUrl = await ref.getDownloadURL();
      }

      debugStage = 'COMP_ENTRY_TRANSACTION_START';
      logEntryStage(debugStage, {
        'opportunityPath': 'opportunities/${widget.opportunityId}',
        'commentPath':
            'opportunities/${widget.opportunityId}/comments/${commentRef.id}',
        'entryPath':
            'opportunities/${widget.opportunityId}/entries/<current-user>',
      });
      await commentService.addComment(
        opportunityId: widget.opportunityId,
        commentId: commentRef.id,
        userId: user.uid,
        userName: user.displayName ?? 'User',
        text: text,
        imageUrl: imageUrl,
        imagePath: imagePath,
        createChallengeEntry: asChallengeEntry,
        debugLog: logEntryStage,
      );
      debugStage = 'COMP_ENTRY_TRANSACTION_OK';
      logEntryStage(debugStage, {
        'opportunityId': widget.opportunityId,
        'commentId': commentRef.id,
      });

      if (asChallengeEntry) {
        debugStage = 'COMP_ENTRY_ANALYTICS_START';
        logEntryStage(debugStage, {'event': 'challenge_entry_submitted'});
        await LocalLinkAnalytics.instance.challengeEntrySubmitted(
          challengeId: widget.opportunityId,
          category: widget.opportunity['category']?.toString() ?? '',
          location: widget.opportunity['location']?.toString() ?? '',
          supportedBusinessId:
              widget.opportunity['supportedByBusinessId']?.toString() ?? '',
        );
        debugStage = 'COMP_ENTRY_ANALYTICS_OK';
        logEntryStage(debugStage);
      }

      commentController.clear();
      if (!mounted) return;
      setState(() {
        selectedEntryImage = null;
        selectedEntryImageBytes = null;
      });

      if (asChallengeEntry) {
        debugStage = 'COMP_ENTRY_SUCCESS_DIALOG_START';
        logEntryStage(debugStage);
        await _showEntrySuccess();
      }
    } catch (error, stackTrace) {
      _logChallengeEntryError(debugStage, error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) {
        setState(() {
          isSubmittingEntry = false;
        });
      }
    }
  }

  void _logChallengeEntryStage(
    String stage, [
    Map<String, Object?> details = const {},
  ]) {
    if (kDebugMode) {
      debugPrint('ChallengeEntryDebug: $stage ${_debugDetails(details)}');
    }
    _logChallengeEntryCrashlytics(stage, details);
  }

  void _logChallengeEntryError(
    String stage,
    Object error,
    StackTrace stackTrace,
  ) {
    if (error is FirebaseException) {
      if (kDebugMode) {
        debugPrint(
          'ChallengeEntryDebug: error stage=$stage plugin=${error.plugin} '
          'code=${error.code} message=${error.message}',
        );
      }
      _recordChallengeEntryCrashlyticsError(
        stage: stage,
        error: error,
        stackTrace: stackTrace,
        details: {
          'plugin': error.plugin,
          'code': error.code,
          'message': error.message ?? '',
        },
      );
      return;
    }
    if (kDebugMode) {
      debugPrint(
        'ChallengeEntryDebug: error stage=$stage type=${error.runtimeType}',
      );
    }
    _recordChallengeEntryCrashlyticsError(
      stage: stage,
      error: error,
      stackTrace: stackTrace,
      details: {'type': error.runtimeType.toString()},
    );
  }

  void _logChallengeEntryCrashlytics(
    String stage,
    Map<String, Object?> details,
  ) {
    if (kIsWeb || Firebase.apps.isEmpty) return;
    unawaited(
      FirebaseCrashlytics.instance.log(
        'ChallengeEntryDebug: $stage ${_debugDetails(details)}',
      ),
    );
  }

  void _recordChallengeEntryCrashlyticsError({
    required String stage,
    required Object error,
    required StackTrace stackTrace,
    required Map<String, Object?> details,
  }) {
    if (kIsWeb || Firebase.apps.isEmpty) return;
    unawaited(
      FirebaseCrashlytics.instance.setCustomKey('comp_entry_stage', stage),
    );
    unawaited(
      FirebaseCrashlytics.instance.setCustomKey(
        'comp_entry_opportunity_id',
        widget.opportunityId,
      ),
    );
    for (final entry in details.entries) {
      unawaited(
        FirebaseCrashlytics.instance.setCustomKey(
          'comp_entry_${entry.key}',
          entry.value?.toString() ?? '',
        ),
      );
    }
    unawaited(
      FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        reason: 'competition_entry_submission_failed',
        fatal: false,
      ),
    );
  }

  String _debugDetails(Map<String, Object?> details) {
    if (details.isEmpty) return '{}';
    return details.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
  }

  String _redactedChallengeEntryImagePath({
    required String opportunityId,
    required String commentId,
  }) {
    return 'opportunityCommentPhotos/$opportunityId/<current-user>/$commentId.jpg';
  }

  Future<void> _showEntrySuccess() async {
    final closesAt = _timestampDate(widget.opportunity['challengeClosesAt']);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('You\'re in!'),
          content: Text(
            closesAt == null
                ? 'Your entry has been added.'
                : 'Your entry has been added. Entries close ${_formatChallengeDate(closesAt)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Stay here'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('See what\'s happening nearby'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _followGroup() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to follow.')),
      );
      return;
    }

    final requiresReason = _isYouthOrApprovalGroup(widget.opportunity);
    var reason = '';
    var explanation = '';

    if (requiresReason) {
      final request = await showDialog<_FollowRequestInput>(
        context: context,
        builder: (_) => const _FollowRequestDialog(),
      );
      if (request == null) return;
      reason = request.reason;
      explanation = request.explanation;
    }

    try {
      final status = await communityGroupService.follow(
        opportunityId: widget.opportunityId,
        reason: reason,
        explanation: explanation,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'pending'
                ? 'Follow request sent.'
                : 'You are now following this group.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow request could not be sent.')),
      );
    }
  }

  Future<void> _unfollowGroup() async {
    try {
      await communityGroupService.unfollow(opportunityId: widget.opportunityId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are no longer following.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update following.')),
      );
    }
  }

  Future<void> _publishAnnouncement() async {
    final input = await showDialog<_AnnouncementInput>(
      context: context,
      builder: (_) => const _AnnouncementDialog(),
    );
    if (input == null) return;

    try {
      await communityGroupService.publishAnnouncement(
        opportunityId: widget.opportunityId,
        title: input.title,
        body: input.body,
        important: input.important,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Update published.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update could not be published.')),
      );
    }
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
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = currentUser?.uid;
    final registeredUid = currentUser == null || currentUser.isAnonymous
        ? null
        : currentUser.uid;

    final opportunity = widget.opportunity;

    final title = opportunity['title'] ?? '';
    final description = opportunity['description'] ?? '';
    final category = opportunity['category'] ?? '';
    final location = opportunity['location'] ?? '';
    final groupName = opportunity['groupName']?.toString().trim() ?? '';
    final activityKind = opportunity['activityKind']?.toString().trim() ?? '';
    final isChallenge = _isCommunityChallenge(opportunity);
    final challengeClosed = _challengeIsClosed(opportunity);
    final challengeClosesAt = _timestampDate(opportunity['challengeClosesAt']);
    final opponentName = opportunity['opponentName']?.toString().trim() ?? '';
    final fixtureVenue = opportunity['fixtureVenue']?.toString().trim() ?? '';
    final organiser = opportunity['organiserName'] ?? '';
    final eventDate = opportunity['eventDate'];
    final eventTime = opportunity['eventTime'] ?? '';
    final photoUrl = opportunity['photoUrl'];
    final organiserUserId = _opportunityManagerId(opportunity);
    final canManageOpportunity =
        _canManageOpportunity(opportunity, uid) || canManageLinkedOrganisation;
    final isUnclaimedListing =
        opportunity['createdByModerator'] == true &&
        opportunity['listingOwnershipStatus'] != 'claimed';

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
        foregroundColor: AppColors.charcoal,
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
                if (isChallenge) {
                  await LocalLinkAnalytics.instance.challengeShared(
                    challengeId: widget.opportunityId,
                    category: widget.opportunity['category']?.toString() ?? '',
                    location: widget.opportunity['location']?.toString() ?? '',
                    supportedBusinessId:
                        widget.opportunity['supportedByBusinessId']
                            ?.toString() ??
                        '',
                  );
                }
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

          if (canManageOpportunity)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
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
                  if (!context.mounted) {
                    return;
                  }
                }
                final titleController = TextEditingController(
                  text: widget.opportunity['title'],
                );

                final descriptionController = TextEditingController(
                  text: widget.opportunity['description'],
                );
                final customTagController = TextEditingController();
                var editCategory = ActivityCategories.normalise(
                  widget.opportunity['category']?.toString(),
                );
                if (editCategory.isEmpty) {
                  editCategory = 'Other';
                }
                final categoryOptions = [
                  if (editCategory.isNotEmpty &&
                      !ActivityCategories.values.contains(editCategory))
                    editCategory,
                  ...ActivityCategories.values,
                ];
                var editAudience = _normaliseStringList(
                  widget.opportunity['audienceValues'] ??
                      widget.opportunity['audience'],
                );
                if (editAudience.isEmpty &&
                    widget.opportunity['audience'] == null) {
                  editAudience = const [];
                }
                var editTags = _normaliseTags(
                  _normaliseStringList(widget.opportunity['tags']),
                );
                var editFollowerAccess =
                    widget.opportunity['followerAccess']?.toString() ??
                    (_looksYouthAudience(editAudience, editCategory)
                        ? 'approval_required'
                        : 'open');
                if (editFollowerAccess != 'approval_required') {
                  editFollowerAccess = 'open';
                }
                final minimumAgeController = TextEditingController(
                  text:
                      _readAge(
                        widget.opportunity['minimumAge'] ??
                            widget.opportunity['ageMinimum'],
                      )?.toString() ??
                      '',
                );
                final maximumAgeController = TextEditingController(
                  text:
                      _readAge(
                        widget.opportunity['maximumAge'] ??
                            widget.opportunity['ageMaximum'],
                      )?.toString() ??
                      '',
                );
                var editRepeatType =
                    widget.opportunity['repeatType']?.toString() ?? 'none';
                DateTime? editRepeatEndDate;
                final existingRepeatEnd = widget.opportunity['repeatEndDate'];
                if (existingRepeatEnd is Timestamp) {
                  editRepeatEndDate = existingRepeatEnd.toDate();
                }

                final save = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return StatefulBuilder(
                      builder: (context, setDialogState) {
                        return AlertDialog(
                          backgroundColor: AppColors.background,
                          insetPadding: const EdgeInsets.symmetric(
                            horizontal: LocalLinkSpacing.md,
                            vertical: LocalLinkSpacing.xl,
                          ),
                          title: Text(
                            'Edit activity',
                            style: LocalLinkTextStyles.sectionTitle,
                          ),
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
                                  autocorrect: true,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: const InputDecoration(
                                    labelText: 'Description',
                                  ),
                                ),
                                const SizedBox(height: 12),

                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  initiallyExpanded: true,
                                  title: const Text(
                                    'Discovery & audience',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  children: [
                                    DropdownButtonFormField<String>(
                                      initialValue:
                                          categoryOptions.contains(editCategory)
                                          ? editCategory
                                          : 'Other',
                                      decoration: const InputDecoration(
                                        labelText: 'Primary category',
                                      ),
                                      items: categoryOptions
                                          .map(
                                            (category) => DropdownMenuItem(
                                              value: category,
                                              child: Text(category),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setDialogState(() {
                                          editCategory = value;
                                          if (widget.opportunity['followerAccess'] ==
                                                  null &&
                                              _looksYouthAudience(
                                                editAudience,
                                                editCategory,
                                              )) {
                                            editFollowerAccess =
                                                'approval_required';
                                          }
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: _communityAudienceValues.map((
                                          audience,
                                        ) {
                                          final selected = editAudience
                                              .contains(audience);
                                          return FilterChip(
                                            label: Text(audience),
                                            selected: selected,
                                            onSelected: (value) {
                                              setDialogState(() {
                                                if (value) {
                                                  editAudience =
                                                      _normaliseStringList([
                                                        ...editAudience,
                                                        audience,
                                                      ]);
                                                } else {
                                                  editAudience = editAudience
                                                      .where(
                                                        (item) =>
                                                            item != audience,
                                                      )
                                                      .toList(growable: false);
                                                }
                                                if (widget.opportunity['followerAccess'] ==
                                                        null &&
                                                    _looksYouthAudience(
                                                      editAudience,
                                                      editCategory,
                                                    )) {
                                                  editFollowerAccess =
                                                      'approval_required';
                                                }
                                              });
                                            },
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: minimumAgeController,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              labelText: 'Min age',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: TextField(
                                            controller: maximumAgeController,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              labelText: 'Max age',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children:
                                            ActivityCategories.suggestionsFor(
                                              editCategory,
                                            ).map((tag) {
                                              final selected = editTags
                                                  .contains(tag);
                                              return FilterChip(
                                                label: Text(tag),
                                                selected: selected,
                                                onSelected: (value) {
                                                  setDialogState(() {
                                                    if (value) {
                                                      editTags = _normaliseTags(
                                                        [...editTags, tag],
                                                      );
                                                    } else {
                                                      editTags = editTags
                                                          .where(
                                                            (item) =>
                                                                item != tag,
                                                          )
                                                          .toList(
                                                            growable: false,
                                                          );
                                                    }
                                                  });
                                                },
                                              );
                                            }).toList(),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Help people find this activity',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: customTagController,
                                            autocorrect: true,
                                            textCapitalization:
                                                TextCapitalization.words,
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Word or phrase people might search for',
                                              hintText:
                                                  'Beginners, Outdoor, Dementia friendly, Walking, Choir',
                                            ),
                                            onSubmitted: (value) {
                                              final next = value.trim();
                                              if (next.isEmpty) return;
                                              setDialogState(() {
                                                editTags = _normaliseTags([
                                                  ...editTags,
                                                  next,
                                                ]);
                                                customTagController.clear();
                                              });
                                            },
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Add word or phrase',
                                          icon: const Icon(Icons.add),
                                          onPressed: () {
                                            final next = customTagController
                                                .text
                                                .trim();
                                            if (next.isEmpty) return;
                                            setDialogState(() {
                                              editTags = _normaliseTags([
                                                ...editTags,
                                                next,
                                              ]);
                                              customTagController.clear();
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    if (editTags.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: editTags.map((tag) {
                                            return InputChip(
                                              label: Text(tag),
                                              onDeleted: () {
                                                setDialogState(() {
                                                  editTags = editTags
                                                      .where(
                                                        (item) => item != tag,
                                                      )
                                                      .toList(growable: false);
                                                });
                                              },
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<String>(
                                      initialValue: editFollowerAccess,
                                      decoration: const InputDecoration(
                                        labelText: 'Follower access',
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'open',
                                          child: Text('Open following'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'approval_required',
                                          child: Text('Approval required'),
                                        ),
                                      ],
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setDialogState(() {
                                          editFollowerAccess = value;
                                        });
                                      },
                                    ),
                                    if (_looksYouthAudience(
                                      editAudience,
                                      editCategory,
                                    ))
                                      const Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Text(
                                          'For youth or family groups, approval required is recommended.',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                DropdownButtonFormField<String>(
                                  initialValue: editRepeatType,
                                  decoration: const InputDecoration(
                                    labelText: 'Repeats',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'none',
                                      child: Text('Does not repeat'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'daily',
                                      child: Text('Daily'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'weekly',
                                      child: Text('Weekly'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'fortnightly',
                                      child: Text('Fortnightly'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'monthly',
                                      child: Text('Monthly'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setDialogState(() {
                                      editRepeatType = value;
                                      if (value == 'none') {
                                        editRepeatEndDate = null;
                                      }
                                    });
                                  },
                                ),
                                if (editRepeatType != 'none') ...[
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.event_repeat_outlined,
                                    ),
                                    label: Text(
                                      editRepeatEndDate == null
                                          ? 'Repeat end date'
                                          : 'Ends ${editRepeatEndDate!.day}/${editRepeatEndDate!.month}/${editRepeatEndDate!.year}',
                                    ),
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            editRepeatEndDate ?? DateTime.now(),
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime(2035),
                                      );

                                      if (picked == null) return;

                                      setDialogState(() {
                                        editRepeatEndDate = picked;
                                      });
                                    },
                                  ),
                                ],
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
                                          'eventDate': Timestamp.fromDate(
                                            picked,
                                          ),
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
                                    if (!context.mounted) return;

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

                            FilledButton(
                              onPressed: () {
                                Navigator.pop(context, true);
                              },
                              child: const Text('Save'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );

                if (save != true) return;

                final minimumAge = minimumAgeController.text.trim().isEmpty
                    ? null
                    : int.tryParse(minimumAgeController.text.trim());
                final maximumAge = maximumAgeController.text.trim().isEmpty
                    ? null
                    : int.tryParse(maximumAgeController.text.trim());

                if ((minimumAgeController.text.trim().isNotEmpty &&
                        minimumAge == null) ||
                    (maximumAgeController.text.trim().isNotEmpty &&
                        maximumAge == null)) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Please enter ages as whole numbers.'),
                    ),
                  );
                  return;
                }

                if ((minimumAge != null && minimumAge < 0) ||
                    (maximumAge != null && maximumAge < 0)) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Age cannot be negative.')),
                  );
                  return;
                }

                if (minimumAge != null &&
                    maximumAge != null &&
                    minimumAge > maximumAge) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Minimum age cannot exceed maximum age.'),
                    ),
                  );
                  return;
                }

                final normalisedTags = _normaliseTags(editTags);
                final normalisedAudience = _normaliseStringList(editAudience);
                final discoveryUpdate = <String, Object?>{
                  'category': editCategory,
                  'audience': normalisedAudience.isEmpty
                      ? null
                      : normalisedAudience.join(', '),
                  'audienceValues': normalisedAudience,
                  'tags': normalisedTags,
                  'minimumAge': minimumAge ?? FieldValue.delete(),
                  'maximumAge': maximumAge ?? FieldValue.delete(),
                  'ageMinimum': minimumAge ?? FieldValue.delete(),
                  'ageMaximum': maximumAge ?? FieldValue.delete(),
                  'followerAccess': editFollowerAccess,
                };

                final currentRef = FirebaseFirestore.instance
                    .collection('opportunities')
                    .doc(widget.opportunityId);

                await currentRef.update({
                  'title': titleController.text.trim(),

                  'description': descriptionController.text.trim(),

                  ...discoveryUpdate,

                  'isRecurring': editRepeatType != 'none',

                  'repeatType': editRepeatType,

                  'repeatEndDate': editRepeatEndDate == null
                      ? null
                      : Timestamp.fromDate(editRepeatEndDate!),

                  'seriesId':
                      widget.opportunity['seriesId'] ?? widget.opportunityId,
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

                          ...discoveryUpdate,

                          'isRecurring': editRepeatType != 'none',

                          'repeatType': editRepeatType,

                          'repeatEndDate': editRepeatEndDate == null
                              ? null
                              : Timestamp.fromDate(editRepeatEndDate!),
                        });
                  }
                }

                if (!context.mounted) return;

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

                if (!context.mounted) return;

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

              if (!context.mounted) return;

              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          LocalLinkSpacing.lg,
          LocalLinkSpacing.sm,
          LocalLinkSpacing.lg,
          LocalLinkSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ActivityHeroCard(
              title: title.toString(),
              category: category.toString(),
              organiser: organiser.toString(),
              formattedDate: formattedDate,
              eventTime: eventTime.toString(),
              location: location.toString(),
              photoUrl: photoUrl?.toString(),
            ),

            const SizedBox(height: LocalLinkSpacing.md),

            if (isUnclaimedListing) ...[
              _UnclaimedOpportunityCard(
                opportunityId: widget.opportunityId,
                title: title.toString(),
              ),
              const SizedBox(height: LocalLinkSpacing.md),
            ],

            _GroupFollowCard(
              opportunityId: widget.opportunityId,
              uid: uid,
              followerCount:
                  int.tryParse(
                    widget.opportunity['followerCount']?.toString() ?? '0',
                  ) ??
                  0,
              requiresApproval: _isYouthOrApprovalGroup(widget.opportunity),
              service: communityGroupService,
              onFollow: _followGroup,
              onUnfollow: _unfollowGroup,
            ),

            const SizedBox(height: LocalLinkSpacing.md),

            if (canManageOpportunity) ...[
              _FollowRequestsPanel(
                opportunityId: widget.opportunityId,
                service: communityGroupService,
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkButton(
                label: 'Publish group update',
                icon: Icons.campaign_outlined,
                variant: LocalLinkButtonVariant.secondary,
                onPressed: _publishAnnouncement,
                expand: true,
              ),
              const SizedBox(height: LocalLinkSpacing.md),
            ],

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

            if (groupName.isNotEmpty) ...[
              _InfoTile(
                icon: Icons.account_tree_outlined,
                title: 'Group',
                value: groupName,
              ),
              const SizedBox(height: 12),
            ],

            if (activityKind.isNotEmpty && activityKind != 'activity') ...[
              _InfoTile(
                icon: activityKind == 'fixture'
                    ? Icons.sports_score_outlined
                    : Icons.event_available_outlined,
                title: 'Type',
                value: _activityKindLabel(activityKind),
              ),
              const SizedBox(height: 12),
            ],

            if (isChallenge && challengeClosesAt != null) ...[
              _InfoTile(
                icon: challengeClosed
                    ? Icons.lock_clock_outlined
                    : Icons.hourglass_bottom_rounded,
                title: challengeClosed ? 'Entries closed' : 'Entries close',
                value: _formatChallengeDate(challengeClosesAt),
              ),
              const SizedBox(height: 12),
            ],

            if (isChallenge &&
                (opportunity['prizeDescription']?.toString().trim() ?? '')
                    .isNotEmpty) ...[
              _InfoTile(
                icon: Icons.card_giftcard_outlined,
                title: 'Optional prize',
                value: opportunity['prizeDescription'].toString(),
              ),
              const SizedBox(height: 12),
            ],

            if (isChallenge &&
                (opportunity['businessId']?.toString().trim() ?? '')
                    .isNotEmpty) ...[
              _ChallengeBusinessCard(
                challengeId: widget.opportunityId,
                opportunity: opportunity,
                relationLabel: 'Hosted by',
                businessIdField: 'businessId',
                businessNameField: 'businessName',
                businessImageField: 'businessImageUrl',
              ),
              const SizedBox(height: 12),
            ],

            if (isChallenge &&
                (opportunity['supportedByBusinessId']?.toString().trim() ?? '')
                    .isNotEmpty) ...[
              _ChallengeBusinessCard(
                challengeId: widget.opportunityId,
                opportunity: opportunity,
                relationLabel: 'Supported by',
                businessIdField: 'supportedByBusinessId',
                businessNameField: 'supportedByBusinessName',
                businessImageField: 'supportedByBusinessImageUrl',
                prizeTextField: 'supportedByBusinessPrizeText',
                logSupportedBusinessOpen: true,
              ),
              const SizedBox(height: 12),
            ],

            if (isChallenge && canManageOpportunity) ...[
              _EligibleEntriesCount(opportunityId: widget.opportunityId),
              const SizedBox(height: 12),
            ],

            if (activityKind == 'fixture' && opponentName.isNotEmpty) ...[
              _InfoTile(
                icon: Icons.shield_outlined,
                title: 'Opponent',
                value: opponentName,
              ),
              const SizedBox(height: 12),
            ],

            if (activityKind == 'fixture' && fixtureVenue.isNotEmpty) ...[
              _InfoTile(
                icon: Icons.place_outlined,
                title: 'Home / away',
                value: _fixtureVenueLabel(fixtureVenue),
              ),
              const SizedBox(height: 12),
            ],

            if (!isUnclaimedListing && organiserUserId.isNotEmpty)
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(organiserUserId)
                    .get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox();
                  }

                  final userData =
                      snapshot.data!.data() as Map<String, dynamic>?;

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
                            userId: organiserUserId,
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
                                  userData?['userName']?.toString() ??
                                      organiser,
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
                        await LocalLinkAnalytics.instance.activitySaved(
                          source: 'activity_detail',
                          category:
                              widget.opportunity['category']?.toString() ?? '',
                        );
                      }
                    },
                  ),
                );
              },
            ),

            const SizedBox(height: 12),
            const SizedBox(height: 12),

            if (!isUnclaimedListing && organiserUserId.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Review Organiser'),
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;

                    if (user == null) return;

                    final alreadyReviewed = await reviewService.hasReviewed(
                      organiserId: organiserUserId,
                      reviewerId: user.uid,
                    );

                    if (!context.mounted) return;

                    if (alreadyReviewed) {
                      final attendeeDoc = await FirebaseFirestore.instance
                          .collection('opportunities')
                          .doc(widget.opportunityId)
                          .collection('attendees')
                          .doc(user.uid)
                          .get();

                      if (!context.mounted) return;

                      if (!attendeeDoc.exists) {
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

                    if (!context.mounted) return;

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

                    try {
                      await reviewService.addReview(
                        opportunityId: widget.opportunityId,
                        organiserId: organiserUserId,

                        reviewerId: user.uid,

                        reviewerName: user.displayName ?? 'User',

                        rating: rating,

                        text: controller.text.trim(),
                      );
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'We could not submit your review. Please try again.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (!context.mounted) return;

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

            const LocalLinkSectionHeader(title: 'Who is going'),

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

            const LocalLinkSectionHeader(title: 'About'),

            const SizedBox(height: LocalLinkSpacing.sm),

            LocalLinkSurfaceCard(
              elevated: false,
              padding: const EdgeInsets.all(LocalLinkSpacing.md),
              child: Text(
                description.toString().trim().isEmpty
                    ? 'No description has been added yet.'
                    : description.toString(),
                style: LocalLinkTextStyles.body,
              ),
            ),

            const SizedBox(height: 24),

            _AnnouncementsPanel(
              opportunityId: widget.opportunityId,
              service: communityGroupService,
            ),

            const SizedBox(height: 24),

            LocalLinkSectionHeader(
              title: isChallenge ? 'Entries' : 'Discussion',
            ),

            const SizedBox(height: 12),

            StreamBuilder<QuerySnapshot>(
              stream: commentService.commentsStream(widget.opportunityId),

              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final comments = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['deleted'] != true &&
                      data['moderationStatus'] != 'removed';
                }).toList();

                if (comments.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      isChallenge
                          ? 'Be the first to add an entry'
                          : 'Be the first to comment',
                    ),
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
                                      await _deleteComment(
                                        commentId,
                                        isChallengeEntry:
                                            data['isChallengeEntry'] == true,
                                      );
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
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text(
                                            data['isChallengeEntry'] == true
                                                ? 'Edit entry'
                                                : 'Edit comment',
                                          ),
                                        ),
                                      if (isOwner)
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text(
                                            data['isChallengeEntry'] == true
                                                ? 'Delete entry'
                                                : 'Delete comment',
                                          ),
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

                            if ((data['imageUrl']?.toString().trim() ?? '')
                                .isNotEmpty) ...[
                              AspectRatio(
                                aspectRatio: 4 / 3,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    LocalLinkRadius.sm,
                                  ),
                                  child: LocalLinkImage(
                                    imageUrl: data['imageUrl']?.toString(),
                                    fallbackIcon: Icons.image_not_supported,
                                    semanticLabel: isChallenge
                                        ? 'Challenge entry image'
                                        : 'Comment image',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],

                            if ((data['text']?.toString().trim() ?? '')
                                .isNotEmpty)
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

            if (isChallenge)
              _ChallengeEntryComposer(
                uid: registeredUid,
                opportunityId: widget.opportunityId,
                closed: challengeClosed,
                allowPhotoEntries:
                    widget.opportunity['allowPhotoEntries'] != false,
                controller: commentController,
                selectedImage: selectedEntryImage,
                selectedImageBytes: selectedEntryImageBytes,
                isSubmitting: isSubmittingEntry,
                onPickImage: _pickEntryImage,
                onClearImage: () => setState(() {
                  selectedEntryImage = null;
                  selectedEntryImageBytes = null;
                }),
                onSubmit: () => _postComment(asChallengeEntry: true),
              )
            else
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

            LocalLinkButton(
              label: isJoining
                  ? 'Joining...'
                  : isGoing
                  ? 'Going'
                  : 'I\'m going',
              icon: isGoing
                  ? Icons.check_circle_rounded
                  : Icons.check_circle_outline_rounded,
              isLoading: isJoining,
              onPressed: isJoining || isGoing ? null : joinOpportunity,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChallengeEntryComposer extends StatelessWidget {
  const _ChallengeEntryComposer({
    required this.uid,
    required this.opportunityId,
    required this.closed,
    required this.allowPhotoEntries,
    required this.controller,
    required this.selectedImage,
    required this.selectedImageBytes,
    required this.isSubmitting,
    required this.onPickImage,
    required this.onClearImage,
    required this.onSubmit,
  });

  final String? uid;
  final String opportunityId;
  final bool closed;
  final bool allowPhotoEntries;
  final TextEditingController controller;
  final XFile? selectedImage;
  final Uint8List? selectedImageBytes;
  final bool isSubmitting;
  final VoidCallback onPickImage;
  final VoidCallback onClearImage;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    if (closed) {
      return const LocalLinkSurfaceCard(
        elevated: false,
        padding: EdgeInsets.all(LocalLinkSpacing.md),
        child: Row(
          children: [
            Icon(Icons.lock_clock_outlined, color: AppColors.textMuted),
            SizedBox(width: LocalLinkSpacing.sm),
            Expanded(child: Text('Entries closed')),
          ],
        ),
      );
    }

    if (uid == null || uid!.isEmpty) {
      return LocalLinkSurfaceCard(
        elevated: false,
        padding: const EdgeInsets.all(LocalLinkSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add your entry', style: LocalLinkTextStyles.bodyStrong),
            const SizedBox(height: LocalLinkSpacing.xs),
            const Text('Sign in to add a photo or submit an entry.'),
            const SizedBox(height: LocalLinkSpacing.sm),
            Row(
              children: [
                if (allowPhotoEntries)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isSubmitting ? null : onPickImage,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Add photo'),
                    ),
                  ),
                if (allowPhotoEntries)
                  const SizedBox(width: LocalLinkSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isSubmitting ? null : onSubmit,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Submit entry'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('opportunities')
          .doc(opportunityId)
          .collection('entries')
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        final entryData = snapshot.data?.data() as Map<String, dynamic>?;
        final removed =
            entryData?['deleted'] == true ||
            entryData?['moderationStatus'] == 'removed' ||
            entryData?['status'] == 'removed';

        if (removed) {
          return const LocalLinkSurfaceCard(
            elevated: false,
            padding: EdgeInsets.all(LocalLinkSpacing.md),
            child: Row(
              children: [
                Icon(Icons.policy_outlined, color: AppColors.textMuted),
                SizedBox(width: LocalLinkSpacing.sm),
                Expanded(
                  child: Text(
                    'Your entry has been removed from this challenge.',
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.data?.exists == true) {
          return const LocalLinkSurfaceCard(
            elevated: false,
            padding: EdgeInsets.all(LocalLinkSpacing.md),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success),
                SizedBox(width: LocalLinkSpacing.sm),
                Expanded(
                  child: Text(
                    'You have already entered this challenge. Your entry is shown above.',
                  ),
                ),
              ],
            ),
          );
        }

        return LocalLinkSurfaceCard(
          elevated: false,
          padding: const EdgeInsets.all(LocalLinkSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add your entry', style: LocalLinkTextStyles.bodyStrong),
              const SizedBox(height: LocalLinkSpacing.sm),
              TextField(
                controller: controller,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Add a caption',
                  border: OutlineInputBorder(),
                ),
              ),
              if (selectedImageBytes != null) ...[
                const SizedBox(height: LocalLinkSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(LocalLinkRadius.sm),
                  child: Image.memory(
                    selectedImageBytes!,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onClearImage,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Remove photo'),
                  ),
                ),
              ],
              const SizedBox(height: LocalLinkSpacing.sm),
              Row(
                children: [
                  if (allowPhotoEntries)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isSubmitting ? null : onPickImage,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(
                          selectedImage == null ? 'Add photo' : 'Change photo',
                        ),
                      ),
                    ),
                  if (allowPhotoEntries)
                    const SizedBox(width: LocalLinkSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isSubmitting ? null : onSubmit,
                      icon: const Icon(Icons.send_rounded),
                      label: Text(isSubmitting ? 'Adding...' : 'Submit entry'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChallengeBusinessCard extends StatelessWidget {
  const _ChallengeBusinessCard({
    required this.challengeId,
    required this.opportunity,
    required this.relationLabel,
    required this.businessIdField,
    required this.businessNameField,
    required this.businessImageField,
    this.prizeTextField = '',
    this.logSupportedBusinessOpen = false,
  });

  final String challengeId;
  final Map<String, dynamic> opportunity;
  final String relationLabel;
  final String businessIdField;
  final String businessNameField;
  final String businessImageField;
  final String prizeTextField;
  final bool logSupportedBusinessOpen;

  @override
  Widget build(BuildContext context) {
    final businessId = opportunity[businessIdField]?.toString().trim() ?? '';
    final businessName =
        opportunity[businessNameField]?.toString().trim() ?? 'Local business';
    final imageUrl = opportunity[businessImageField]?.toString().trim() ?? '';
    final prizeText = prizeTextField.isEmpty
        ? ''
        : opportunity[prizeTextField]?.toString().trim() ?? '';

    return LocalLinkSurfaceCard(
      elevated: false,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(LocalLinkRadius.md),
        onTap: businessId.isEmpty
            ? null
            : () async {
                if (logSupportedBusinessOpen) {
                  await LocalLinkAnalytics.instance
                      .challengeSupportedBusinessOpened(
                        challengeId: challengeId,
                        supportedBusinessId: businessId,
                        category: opportunity['category']?.toString() ?? '',
                        location: opportunity['location']?.toString() ?? '',
                      );
                }
                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        BusinessDetailScreen(businessId: businessId),
                  ),
                );
              },
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: LocalLinkImage(
                imageUrl: imageUrl,
                fallbackIcon: Icons.storefront_outlined,
                semanticLabel: relationLabel,
              ),
            ),
            const SizedBox(width: LocalLinkSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(relationLabel, style: LocalLinkTextStyles.metadata),
                  const SizedBox(height: LocalLinkSpacing.xxs),
                  Text(businessName, style: LocalLinkTextStyles.bodyStrong),
                  if (prizeText.isNotEmpty) ...[
                    const SizedBox(height: LocalLinkSpacing.xxs),
                    Text('Prize: $prizeText'),
                  ],
                ],
              ),
            ),
            if (businessId.isNotEmpty) const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _EligibleEntriesCount extends StatelessWidget {
  const _EligibleEntriesCount({required this.opportunityId});

  final String opportunityId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('opportunities')
          .doc(opportunityId)
          .collection('entries')
          .where('eligible', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length;
        return _InfoTile(
          icon: Icons.emoji_events_outlined,
          title: 'Eligible entries',
          value: count == null ? 'Loading...' : '$count',
        );
      },
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
    return LocalLinkSurfaceCard(
      elevated: false,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.activityBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(LocalLinkRadius.sm),
            ),
            child: Icon(icon, color: AppColors.activityBlue, size: 20),
          ),
          const SizedBox(width: LocalLinkSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: LocalLinkTextStyles.metadata),
                const SizedBox(height: LocalLinkSpacing.xxs),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LocalLinkTextStyles.bodyStrong,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityHeroCard extends StatelessWidget {
  const _ActivityHeroCard({
    required this.title,
    required this.category,
    required this.organiser,
    required this.formattedDate,
    required this.eventTime,
    required this.location,
    required this.photoUrl,
  });

  final String title;
  final String category;
  final String organiser;
  final String formattedDate;
  final String eventTime;
  final String location;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final schedule = [
      if (formattedDate.isNotEmpty) formattedDate,
      if (eventTime.isNotEmpty) eventTime,
    ].join(' · ');

    return LocalLinkSurfaceCard(
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      radius: LocalLinkRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalLinkImage(
            imageUrl: photoUrl,
            aspectRatio: 16 / 9,
            fallbackIcon: Icons.local_activity_rounded,
            accentColor: AppColors.activityBlue,
            semanticLabel: 'Activity image',
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          Wrap(
            spacing: LocalLinkSpacing.xs,
            runSpacing: LocalLinkSpacing.xs,
            children: [
              _HeroPill(
                label: 'Activity',
                icon: Icons.local_activity_rounded,
                color: AppColors.activityBlue,
              ),
              if (category.isNotEmpty)
                _HeroPill(
                  label: category,
                  icon: Icons.category_outlined,
                  color: AppColors.primary,
                ),
            ],
          ),
          const SizedBox(height: LocalLinkSpacing.sm),
          Text(
            title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: LocalLinkTextStyles.screenTitle.copyWith(fontSize: 28),
          ),
          if (organiser.isNotEmpty) ...[
            const SizedBox(height: LocalLinkSpacing.xs),
            Text(
              'Hosted by $organiser',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: LocalLinkTextStyles.secondary,
            ),
          ],
          const SizedBox(height: LocalLinkSpacing.md),
          if (schedule.isNotEmpty)
            _HeroMeta(icon: Icons.event_rounded, label: schedule),
          if (location.isNotEmpty) ...[
            if (schedule.isNotEmpty)
              const SizedBox(height: LocalLinkSpacing.xs),
            _HeroMeta(icon: Icons.place_outlined, label: location),
          ],
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.xs,
        vertical: LocalLinkSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: LocalLinkSpacing.xxs),
          Text(label, style: LocalLinkTextStyles.status.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.activityBlue),
        const SizedBox(width: LocalLinkSpacing.xs),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LocalLinkTextStyles.bodyStrong,
          ),
        ),
      ],
    );
  }
}

class _GroupFollowCard extends StatelessWidget {
  const _GroupFollowCard({
    required this.opportunityId,
    required this.uid,
    required this.followerCount,
    required this.requiresApproval,
    required this.service,
    required this.onFollow,
    required this.onUnfollow,
  });

  final String opportunityId;
  final String? uid;
  final int followerCount;
  final bool requiresApproval;
  final CommunityGroupService service;
  final VoidCallback onFollow;
  final VoidCallback onUnfollow;

  @override
  Widget build(BuildContext context) {
    if (uid == null || uid!.isEmpty) {
      return _FollowShell(
        followerCount: followerCount,
        title: requiresApproval ? 'Request to follow' : 'Follow group',
        subtitle:
            'Follow means you want updates from this organisation. It does not mark you as attending events.',
        action: LocalLinkButton(
          label: 'Sign in to follow',
          icon: Icons.notifications_active_outlined,
          variant: LocalLinkButtonVariant.secondary,
          onPressed: onFollow,
          expand: true,
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: service.followState(opportunityId: opportunityId, userId: uid!),
      builder: (context, followerSnapshot) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: service.followRequestState(
            opportunityId: opportunityId,
            userId: uid!,
          ),
          builder: (context, requestSnapshot) {
            final following =
                followerSnapshot.data?.data()?['status'] == 'approved';
            final pending =
                requestSnapshot.data?.data()?['status'] == 'pending';

            return _FollowShell(
              followerCount: followerCount,
              title: following
                  ? 'Following this group'
                  : pending
                  ? 'Follow request pending'
                  : requiresApproval
                  ? 'Request to follow'
                  : 'Follow group',
              subtitle:
                  'Follow means you want group updates. Attend is still only for a specific activity.',
              action: following
                  ? LocalLinkButton(
                      label: 'Unfollow',
                      icon: Icons.notifications_off_outlined,
                      variant: LocalLinkButtonVariant.secondary,
                      onPressed: onUnfollow,
                      expand: true,
                    )
                  : LocalLinkButton(
                      label: pending ? 'Pending' : 'Follow',
                      icon: Icons.notifications_active_outlined,
                      onPressed: pending ? null : onFollow,
                      expand: true,
                    ),
            );
          },
        );
      },
    );
  }
}

class _FollowShell extends StatelessWidget {
  const _FollowShell({
    required this.followerCount,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final int followerCount;
  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.notifications_active_outlined,
            color: AppColors.activityBlue,
          ),
          const SizedBox(width: LocalLinkSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: LocalLinkTextStyles.cardTitle.copyWith(fontSize: 16),
                ),
                const SizedBox(height: LocalLinkSpacing.xxs),
                Text(subtitle, style: LocalLinkTextStyles.secondary),
                if (followerCount > 0) ...[
                  const SizedBox(height: LocalLinkSpacing.xs),
                  Text(
                    '$followerCount followers',
                    style: LocalLinkTextStyles.metadata,
                  ),
                ],
                const SizedBox(height: LocalLinkSpacing.sm),
                action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowRequestsPanel extends StatelessWidget {
  const _FollowRequestsPanel({
    required this.opportunityId,
    required this.service,
  });

  final String opportunityId;
  final CommunityGroupService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: service.followRequests(opportunityId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final requests = snapshot.data!.docs
            .where(
              (doc) => (doc.data()['status']?.toString() ?? '') == 'pending',
            )
            .toList(growable: false);
        if (requests.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Follow requests',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              ...requests.map((doc) {
                final data = doc.data();
                final reason = data['reason']?.toString() ?? '';
                final name = data['userName']?.toString() ?? 'LocalLink member';
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (reason.isNotEmpty)
                              Text(
                                reason,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => service.reviewFollowRequest(
                          opportunityId: opportunityId,
                          followerId: doc.id,
                          approve: false,
                        ),
                        child: const Text('Decline'),
                      ),
                      FilledButton(
                        onPressed: () => service.reviewFollowRequest(
                          opportunityId: opportunityId,
                          followerId: doc.id,
                          approve: true,
                        ),
                        child: const Text('Approve'),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _AnnouncementsPanel extends StatelessWidget {
  const _AnnouncementsPanel({
    required this.opportunityId,
    required this.service,
  });

  final String opportunityId;
  final CommunityGroupService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: service.announcements(opportunityId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Updates',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            ...snapshot.data!.docs.map((doc) {
              final data = doc.data();
              final important = data['importance'] == 'important';
              final title = data['title']?.toString() ?? 'Update';
              final body = data['body']?.toString() ?? '';
              final createdAt = data['createdAt'];

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: important
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: important
                        ? AppColors.primary.withValues(alpha: 0.22)
                        : AppColors.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          important
                              ? Icons.warning_amber_rounded
                              : Icons.campaign_outlined,
                          size: 18,
                          color: important
                              ? AppColors.primary
                              : AppColors.activityBlue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.charcoal,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (createdAt is Timestamp)
                          Text(
                            _shortDate(createdAt),
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(body, style: const TextStyle(height: 1.35)),
                    ],
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  String _shortDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Today';
    }
    return '${date.day}/${date.month}';
  }
}

class _FollowRequestInput {
  const _FollowRequestInput({required this.reason, required this.explanation});

  final String reason;
  final String explanation;
}

class _FollowRequestDialog extends StatefulWidget {
  const _FollowRequestDialog();

  @override
  State<_FollowRequestDialog> createState() => _FollowRequestDialogState();
}

class _FollowRequestDialogState extends State<_FollowRequestDialog> {
  final _explanationController = TextEditingController();
  String _reason = 'Parent/carer';

  @override
  void dispose() {
    _explanationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request to follow'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Why would you like to follow this group? Do not include child names or private details.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            items: const [
              DropdownMenuItem(
                value: 'Parent/carer',
                child: Text('Parent/carer'),
              ),
              DropdownMenuItem(
                value: 'Grandparent/family member',
                child: Text('Grandparent/family member'),
              ),
              DropdownMenuItem(
                value: 'Interested in joining',
                child: Text('Interested in joining'),
              ),
              DropdownMenuItem(value: 'Volunteer', child: Text('Volunteer')),
              DropdownMenuItem(
                value: 'Local supporter',
                child: Text('Local supporter'),
              ),
              DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _reason = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _explanationController,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Optional note',
              hintText: 'Keep it brief',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _FollowRequestInput(
              reason: _reason,
              explanation: _explanationController.text.trim(),
            ),
          ),
          child: const Text('Send request'),
        ),
      ],
    );
  }
}

class _AnnouncementInput {
  const _AnnouncementInput({
    required this.title,
    required this.body,
    required this.important,
  });

  final String title;
  final String body;
  final bool important;
}

class _AnnouncementDialog extends StatefulWidget {
  const _AnnouncementDialog();

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _important = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Publish group update'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Update'),
          ),
          SwitchListTile(
            value: _important,
            contentPadding: EdgeInsets.zero,
            title: const Text('Important update'),
            onChanged: (value) => setState(() => _important = value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final body = _bodyController.text.trim();
            if (body.isEmpty) return;
            Navigator.pop(
              context,
              _AnnouncementInput(
                title: _titleController.text.trim(),
                body: body,
                important: _important,
              ),
            );
          },
          child: const Text('Publish'),
        ),
      ],
    );
  }
}

class _UnclaimedOpportunityCard extends StatelessWidget {
  const _UnclaimedOpportunityCard({
    required this.opportunityId,
    required this.title,
  });

  final String opportunityId;
  final String title;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      color: AppColors.primary.withValues(alpha: 0.07),
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unclaimed listing',
            style: LocalLinkTextStyles.label.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: LocalLinkSpacing.xxs),
          Text(
            'This event has not yet been claimed by its organiser.',
            style: LocalLinkTextStyles.secondary,
          ),
          const SizedBox(height: LocalLinkSpacing.sm),
          LocalLinkButton(
            label: 'Claim this event',
            icon: Icons.verified_user_outlined,
            variant: LocalLinkButtonVariant.secondary,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ListingClaimRequestScreen(
                    listingType: 'opportunity',
                    listingId: opportunityId,
                    listingTitle: title,
                  ),
                ),
              );
            },
            expand: true,
          ),
        ],
      ),
    );
  }
}
