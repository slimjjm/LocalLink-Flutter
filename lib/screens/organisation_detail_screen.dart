import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/organisation.dart';
import '../models/organisation_group.dart';
import '../services/analytics_service.dart';
import '../services/organisation_service.dart';
import '../services/local_discovery_filters.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_image.dart';
import '../widgets/local_link_section_header.dart';
import '../widgets/local_link_states.dart';
import '../widgets/local_link_surface_card.dart';
import 'listing_claim_request_screen.dart';
import 'opportunity_detail_screen.dart';
import 'organisation_management_screen.dart';
import 'organisation_group_screens.dart';

@visibleForTesting
List<QueryDocumentSnapshot<Map<String, dynamic>>>
selectUpcomingOrganisationActivityDocs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
  required DateTime now,
}) => _OrganisationDetailScreenState._uniqueActivityDocs(
  docs.where((doc) {
    final data = doc.data();
    return data['discoveryVisibility'] == 'public' &&
        LocalDiscoveryFilters.isActivityDiscoverable(data, now: now);
  }).toList(),
);

@visibleForTesting
String organisationActivityRecurrenceLabel(Map<String, dynamic> data) =>
    _OrganisationDetailScreenState._recurrenceLabel(data);

class OrganisationDetailScreen extends StatefulWidget {
  const OrganisationDetailScreen({super.key, required this.organisationId});

  final String organisationId;

  @override
  State<OrganisationDetailScreen> createState() =>
      _OrganisationDetailScreenState();
}

class _OrganisationDetailScreenState extends State<OrganisationDetailScreen> {
  final OrganisationService _service = OrganisationService();
  bool _loggedView = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _service.watchOrganisation(widget.organisationId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('This organisation could not be loaded.')),
          );
        }

        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final doc = snapshot.data!;
        if (!doc.exists) {
          return const Scaffold(
            body: Center(child: Text('This organisation is no longer here.')),
          );
        }

        final organisation = Organisation.fromFirestore(doc);
        if (!_loggedView) {
          _loggedView = true;
          LocalLinkAnalytics.instance.discoveryView(
            eventName: 'organisation_view',
            source: 'other',
            category: organisation.category,
          );
        }
        final uid = FirebaseAuth.instance.currentUser?.uid;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Organisation'),
            backgroundColor: AppColors.background,
            foregroundColor: AppColors.charcoal,
            elevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _OrganisationHeader(organisation: organisation),
              const SizedBox(height: LocalLinkSpacing.xl),
              LocalLinkSectionHeader(title: groupCollectionLabel(organisation)),
              const SizedBox(height: LocalLinkSpacing.sm),
              StreamBuilder<List<OrganisationGroup>>(
                stream: _service.watchGroups(widget.organisationId),
                builder: (context, groupSnapshot) {
                  if (groupSnapshot.hasError) {
                    return const SizedBox.shrink();
                  }
                  final groups = groupSnapshot.data ?? const [];
                  if (groups.isEmpty) return const SizedBox.shrink();
                  return Column(
                    children: groups
                        .map(
                          (group) => _OrganisationGroupTile(
                            group: group,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrganisationGroupDetailScreen(
                                  organisation: organisation,
                                  groupId: group.id,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: LocalLinkSpacing.xl),
              const LocalLinkSectionHeader(title: 'Upcoming activities'),
              const SizedBox(height: LocalLinkSpacing.sm),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _service.watchPublicOrganisationActivities(
                  widget.organisationId,
                ),
                builder: (context, activitySnapshot) {
                  if (activitySnapshot.hasError) {
                    return const LocalLinkErrorState(
                      title: 'Activities could not be loaded',
                      message: 'Please try again in a moment.',
                    );
                  }
                  if (!activitySnapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: LocalLinkSpacing.xxl,
                      ),
                      child: LocalLinkLoadingState(label: 'Loading activities'),
                    );
                  }

                  final docs =
                      selectUpcomingOrganisationActivityDocs(
                        activitySnapshot.data!.docs,
                        now: DateTime.now(),
                      )..sort((a, b) {
                        final aDate = a.data()['eventDate'];
                        final bDate = b.data()['eventDate'];
                        if (aDate is Timestamp && bDate is Timestamp) {
                          return aDate.compareTo(bDate);
                        }
                        return 0;
                      });

                  if (docs.isEmpty) {
                    return const LocalLinkEmptyState(
                      icon: Icons.event_busy_outlined,
                      title: 'No activities yet',
                      message:
                          'This organisation has not added any public activities yet.',
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data();
                      return _ActivityTile(
                        title: data['title']?.toString() ?? 'Activity',
                        subtitle: _activitySubtitle(data),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OpportunityDetailScreen(
                                opportunityId: doc.id,
                                opportunity: data,
                              ),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: LocalLinkSpacing.xl),
              _OrganisationOwnershipCard(organisation: organisation, uid: uid),
            ],
          ),
        );
      },
    );
  }

  static String _activitySubtitle(Map<String, dynamic> data) {
    final parts = [
      data['ageGroup']?.toString().trim(),
      _recurrenceLabel(data),
      data['location']?.toString().trim(),
    ].where((part) => part != null && part.isNotEmpty).cast<String>();

    return parts.join(' · ');
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _uniqueActivityDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final bySeries = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    for (final doc in docs) {
      final data = doc.data();
      final seriesId = data['seriesId']?.toString().trim() ?? '';
      final key = data['isRecurring'] == true && seriesId.isNotEmpty
          ? seriesId
          : doc.id;
      final existing = bySeries[key];
      if (existing == null || _compareActivityDate(doc, existing) < 0) {
        bySeries[key] = doc;
      }
    }

    return bySeries.values.toList();
  }

  static int _compareActivityDate(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final aDate = a.data()['eventDate'];
    final bDate = b.data()['eventDate'];
    if (aDate is Timestamp && bDate is Timestamp) {
      return aDate.compareTo(bDate);
    }
    if (aDate is Timestamp) return -1;
    if (bDate is Timestamp) return 1;
    return 0;
  }

  static String _recurrenceLabel(Map<String, dynamic> data) {
    final schedule = data['scheduleText']?.toString().trim() ?? '';
    final eventDate = data['eventDate'];
    final eventTime = data['eventTime']?.toString().trim() ?? '';
    final endTime = data['endTime']?.toString().trim() ?? '';
    final repeatType = data['repeatType']?.toString().trim() ?? '';

    if (data['isRecurring'] == true &&
        eventDate is Timestamp &&
        repeatType == 'weekly') {
      return [
        'Every ${_weekdayName(eventDate.toDate().weekday)}',
        if (eventTime.isNotEmpty)
          '$eventTime${endTime.isEmpty ? '' : ' - $endTime'}',
      ].join(' · ');
    }

    if (schedule.isNotEmpty) return schedule;

    final repeatLabel = switch (repeatType) {
      'daily' => 'Daily',
      'fortnightly' => 'Fortnightly',
      'monthly' => 'Monthly',
      _ => '',
    };

    return [
      if (repeatLabel.isNotEmpty) repeatLabel,
      if (eventTime.isNotEmpty) eventTime,
    ].join(' · ');
  }

  static String _weekdayName(int weekday) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[(weekday - 1).clamp(0, names.length - 1)];
  }
}

class _OrganisationGroupTile extends StatelessWidget {
  const _OrganisationGroupTile({required this.group, required this.onTap});

  final OrganisationGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
      child: LocalLinkSurfaceCard(
        onTap: onTap,
        elevated: false,
        padding: const EdgeInsets.all(LocalLinkSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: LocalLinkImage(
                imageUrl: group.imageUrl,
                fallbackIcon: Icons.account_tree_outlined,
                accentColor: AppColors.activityBlue,
                semanticLabel: '${group.name} image',
              ),
            ),
            const SizedBox(width: LocalLinkSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.name, style: LocalLinkTextStyles.cardTitle),
                  const SizedBox(height: LocalLinkSpacing.xxs),
                  Text(
                    [
                      if (group.ageLabel.isNotEmpty) group.ageLabel,
                      if (group.subcategory.isNotEmpty) group.subcategory,
                      '${group.memberCount} members',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LocalLinkTextStyles.metadata,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _OrganisationOwnershipCard extends StatelessWidget {
  const _OrganisationOwnershipCard({required this.organisation, this.uid});

  final Organisation organisation;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    if (organisation.isManagedBy(uid)) {
      return _ClaimSurface(
        label: 'Managed',
        text: 'You can manage this organisation and its linked activities.',
        action: LocalLinkButton(
          label: 'Manage',
          icon: Icons.manage_accounts_outlined,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    OrganisationManagementScreen(organisation: organisation),
              ),
            );
          },
          variant: LocalLinkButtonVariant.secondary,
        ),
      );
    }

    if (organisation.isClaimed) {
      return const _ClaimSurface(
        label: 'Claimed',
        text: 'This organisation is managed by its organiser on LocalLink.',
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _ClaimSurface(
        label: 'Unclaimed organisation',
        text: 'Is this your organisation? Sign in to request access.',
        action: LocalLinkButton(
          label: 'Claim this organisation',
          icon: Icons.verified_user_outlined,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ListingClaimRequestScreen(
                  listingType: 'organisation',
                  listingId: organisation.id,
                  listingTitle: organisation.name,
                ),
              ),
            );
          },
          variant: LocalLinkButtonVariant.secondary,
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('listingClaims')
          .where('listingType', isEqualTo: 'organisation')
          .where('listingId', isEqualTo: organisation.id)
          .where('claimantUserId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.data?.docs.isNotEmpty == true) {
          return const _ClaimSurface(
            label: 'Claim pending',
            text: 'A moderator is reviewing your organisation claim.',
          );
        }

        return _ClaimSurface(
          label: 'Is this your organisation?',
          text:
              'Request access once. After approval you can manage the organisation and its linked activities.',
          action: LocalLinkButton(
            label: 'Claim this organisation',
            icon: Icons.verified_user_outlined,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ListingClaimRequestScreen(
                    listingType: 'organisation',
                    listingId: organisation.id,
                    listingTitle: organisation.name,
                  ),
                ),
              );
            },
            variant: LocalLinkButtonVariant.secondary,
          ),
        );
      },
    );
  }
}

class _ClaimSurface extends StatelessWidget {
  const _ClaimSurface({required this.label, required this.text, this.action});

  final String label;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      color: AppColors.activitySoft,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: LocalLinkTextStyles.label.copyWith(
              color: AppColors.activityBlue,
            ),
          ),
          const SizedBox(height: LocalLinkSpacing.xs),
          Text(text, style: LocalLinkTextStyles.secondary),
          if (action != null) ...[
            const SizedBox(height: LocalLinkSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}

class _OrganisationHeader extends StatelessWidget {
  const _OrganisationHeader({required this.organisation});

  final Organisation organisation;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      padding: const EdgeInsets.all(LocalLinkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Logo(imageUrl: organisation.imageUrl),
              const SizedBox(width: LocalLinkSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      organisation.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: LocalLinkTextStyles.screenTitle.copyWith(
                        fontSize: 26,
                      ),
                    ),
                    const SizedBox(height: LocalLinkSpacing.xs),
                    Wrap(
                      spacing: LocalLinkSpacing.xs,
                      runSpacing: LocalLinkSpacing.xs,
                      children: [
                        if (organisation.category.isNotEmpty)
                          _Pill(label: organisation.category),
                        for (final tag in organisation.subcategories)
                          _Pill(label: tag),
                        if (organisation.publicLocation.isNotEmpty)
                          _Pill(label: organisation.publicLocation),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (organisation.description.isNotEmpty) ...[
            const SizedBox(height: LocalLinkSpacing.md),
            Text(organisation.description, style: LocalLinkTextStyles.body),
          ],
          const SizedBox(height: LocalLinkSpacing.md),
          Wrap(
            spacing: LocalLinkSpacing.md,
            runSpacing: LocalLinkSpacing.xs,
            children: [
              if (organisation.location.isNotEmpty)
                _Meta(icon: Icons.place_outlined, label: organisation.location),
              if (organisation.phone.isNotEmpty)
                _Meta(icon: Icons.phone_outlined, label: organisation.phone),
              if (organisation.website.isNotEmpty)
                _Meta(
                  icon: Icons.language_outlined,
                  label: organisation.website,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      height: 74,
      child: LocalLinkImage(
        imageUrl: imageUrl,
        fallbackIcon: Icons.groups_2_outlined,
        accentColor: AppColors.activityBlue,
        semanticLabel: 'Organisation image',
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.xs,
        vertical: LocalLinkSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.activityBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
      ),
      child: Text(
        label,
        style: LocalLinkTextStyles.status.copyWith(
          color: AppColors.activityBlue,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LocalLinkTextStyles.metadata,
          ),
        ),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
      child: LocalLinkSurfaceCard(
        onTap: onTap,
        elevated: false,
        padding: const EdgeInsets.all(LocalLinkSpacing.md),
        child: Row(
          children: [
            const LocalLinkIconBadge(
              icon: Icons.local_activity_outlined,
              color: AppColors.activityBlue,
              size: 42,
            ),
            const SizedBox(width: LocalLinkSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LocalLinkTextStyles.cardTitle,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: LocalLinkSpacing.xxs),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LocalLinkTextStyles.metadata,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
