import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'business_detail_screen.dart';
import 'organisation_detail_screen.dart';
import 'opportunity_detail_screen.dart';
import 'post_service_request_screen.dart';

Stream<int> pendingListingClaimCountStream({FirebaseFirestore? firestore}) {
  final db = firestore ?? FirebaseFirestore.instance;
  return db
      .collection('listingClaims')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((snapshot) => snapshot.docs.length);
}

Stream<List<ClaimReviewItem>> pendingListingClaimsStream({
  FirebaseFirestore? firestore,
}) {
  final db = firestore ?? FirebaseFirestore.instance;
  return db
      .collection('listingClaims')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((snapshot) {
        final claims = snapshot.docs
            .map((doc) => ClaimReviewItem.fromMap(doc.id, doc.data()))
            .toList();
        claims.sort(
          (a, b) => _timestampMillis(
            b.createdAt,
          ).compareTo(_timestampMillis(a.createdAt)),
        );
        return claims;
      });
}

class ClaimReviewItem {
  const ClaimReviewItem({
    required this.id,
    required this.listingId,
    required this.listingType,
    required this.listingTitle,
    required this.claimantName,
    required this.relationship,
    required this.email,
    required this.phone,
    required this.createdAt,
  });

  final String id;
  final String listingId;
  final String listingType;
  final String listingTitle;
  final String claimantName;
  final String relationship;
  final String email;
  final String phone;
  final Object? createdAt;

  factory ClaimReviewItem.fromMap(String id, Map<String, dynamic> data) {
    return ClaimReviewItem(
      id: id,
      listingId: _text(data['listingId']),
      listingType: _text(data['listingType']),
      listingTitle: _text(data['listingTitle']),
      claimantName: _text(data['claimantName']),
      relationship: _text(data['relationship']),
      email: _text(data['businessEmail']).isNotEmpty
          ? _text(data['businessEmail'])
          : _text(data['claimantEmail']),
      phone: _text(data['businessPhone']),
      createdAt: data['createdAt'],
    );
  }

  String get listingTypeLabel {
    switch (listingType) {
      case 'business':
        return 'Business';
      case 'organisation':
        return 'Organisation';
      case 'community_help_missing_pet':
        return 'Missing pet';
      case 'opportunity':
        return 'Event';
      default:
        return listingType.isEmpty ? 'Listing' : listingType;
    }
  }
}

class ClaimRequestsModerationCard extends StatelessWidget {
  const ClaimRequestsModerationCard({
    super.key,
    required this.countStream,
    required this.onTap,
  });

  final Stream<int> countStream;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: countStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final loading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;

        return _ClaimSurface(
          onTap: onTap,
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.primary,
                child: Icon(Icons.assignment_ind_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Claim requests',
                      style: TextStyle(
                        color: AppColors.charcoal,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Review ownership requests for businesses and organisations.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loading
                          ? 'Loading claims...'
                          : count == 0
                          ? 'No pending claims'
                          : '$count pending',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        );
      },
    );
  }
}

class ClaimReviewScreen extends StatelessWidget {
  const ClaimReviewScreen({super.key});

  Future<void> _openListing(BuildContext context, ClaimReviewItem claim) async {
    if (claim.listingId.isEmpty) return;
    if (claim.listingType == 'business') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessDetailScreen(businessId: claim.listingId),
        ),
      );
      return;
    }

    if (claim.listingType == 'organisation') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              OrganisationDetailScreen(organisationId: claim.listingId),
        ),
      );
      return;
    }

    if (claim.listingType == 'community_help_missing_pet') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PostServiceRequestScreen(initialPostId: claim.listingId),
        ),
      );
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('opportunities')
        .doc(claim.listingId)
        .get();
    if (!context.mounted || !doc.exists || doc.data() == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OpportunityDetailScreen(
          opportunityId: claim.listingId,
          opportunity: doc.data()!,
        ),
      ),
    );
  }

  Future<void> _reviewClaim({
    required BuildContext context,
    required ClaimReviewItem claim,
    required bool approve,
  }) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('reviewListingClaim')
          .call({'claimId': claim.id, 'approve': approve});

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Claim approved.' : 'Claim rejected.'),
        ),
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Claim review failed: $error');
        debugPrint('$stackTrace');
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Claim could not be reviewed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Claim requests'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: ClaimReviewList(
        claimsStream: pendingListingClaimsStream(),
        onOpen: (claim) => _openListing(context, claim),
        onApprove: (claim) =>
            _reviewClaim(context: context, claim: claim, approve: true),
        onReject: (claim) =>
            _reviewClaim(context: context, claim: claim, approve: false),
      ),
    );
  }
}

class ClaimReviewList extends StatelessWidget {
  const ClaimReviewList({
    super.key,
    required this.claimsStream,
    required this.onOpen,
    required this.onApprove,
    required this.onReject,
  });

  final Stream<List<ClaimReviewItem>> claimsStream;
  final ValueChanged<ClaimReviewItem> onOpen;
  final ValueChanged<ClaimReviewItem> onApprove;
  final ValueChanged<ClaimReviewItem> onReject;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClaimReviewItem>>(
      stream: claimsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Claim requests could not be loaded.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final claims = snapshot.data!;
        if (claims.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No pending claims'),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          itemCount: claims.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final claim = claims[index];
            return ClaimReviewCard(
              claim: claim,
              onOpen: () => onOpen(claim),
              onApprove: () => onApprove(claim),
              onReject: () => onReject(claim),
            );
          },
        );
      },
    );
  }
}

class ClaimReviewCard extends StatelessWidget {
  const ClaimReviewCard({
    super.key,
    required this.claim,
    required this.onOpen,
    required this.onApprove,
    required this.onReject,
  });

  final ClaimReviewItem claim;
  final VoidCallback onOpen;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return _ClaimSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  claim.listingTitle.isEmpty
                      ? claim.listingId
                      : claim.listingTitle,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _ClaimTypeBadge(label: claim.listingTypeLabel),
            ],
          ),
          const SizedBox(height: 8),
          _ClaimDetail(label: 'Claimant', value: claim.claimantName),
          _ClaimDetail(label: 'Role', value: claim.relationship),
          _ClaimDetail(label: 'Email', value: claim.email),
          _ClaimDetail(label: 'Phone', value: claim.phone),
          _ClaimDetail(label: 'Submitted', value: _dateLabel(claim.createdAt)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: onOpen,
                child: const Text('View listing'),
              ),
              FilledButton(onPressed: onApprove, child: const Text('Approve')),
              FilledButton.tonal(
                onPressed: onReject,
                child: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClaimSurface extends StatelessWidget {
  const _ClaimSurface({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.72)),
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _ClaimTypeBadge extends StatelessWidget {
  const _ClaimTypeBadge({required this.label});

  final String label;

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

class _ClaimDetail extends StatelessWidget {
  const _ClaimDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _dateLabel(Object? value) {
  if (value is! Timestamp) return '';
  final date = value.toDate();
  return '${date.day}/${date.month}/${date.year}';
}

int _timestampMillis(Object? value) {
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  return 0;
}

String _text(Object? value) => value?.toString().trim() ?? '';
