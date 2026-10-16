import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../screens/opportunity_detail_screen.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import 'local_link_image.dart';
import 'local_link_surface_card.dart';

class OpportunityCard extends StatelessWidget {
  final String opportunityId;
  final Map<String, dynamic> data;
  final Position? userPosition;

  const OpportunityCard({
    super.key,
    required this.opportunityId,
    required this.data,
    required this.userPosition,
  });

  Color _categoryColor(String category) {
    switch (category) {
      case 'Fitness & Sport':
        return Colors.green;
      case 'Family':
        return Colors.pink;
      case 'Pets':
        return Colors.orange;
      case 'Hobbies':
        return Colors.purple;
      case 'Social':
        return AppColors.activityBlue;
      case 'Volunteering':
        return Colors.red;
      case 'Learning':
        return Colors.teal;
      case 'Local Deals':
        return Colors.indigo;
      default:
        return AppColors.activityBlue;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Fitness & Sport':
        return Icons.fitness_center;
      case 'Family':
        return Icons.family_restroom;
      case 'Pets':
        return Icons.pets;
      case 'Hobbies':
        return Icons.palette;
      case 'Social':
        return Icons.groups;
      case 'Volunteering':
        return Icons.favorite;
      case 'Learning':
        return Icons.school;
      case 'Local Deals':
        return Icons.local_offer;
      default:
        return Icons.local_activity;
    }
  }

  String _dateBadge() {
    final rawEventDate = data['eventDate'];

    DateTime? date;

    if (rawEventDate is Timestamp) {
      date = rawEventDate.toDate();
    } else if (rawEventDate is DateTime) {
      date = rawEventDate;
    }

    if (date == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    final difference = eventDay.difference(today).inDays;

    if (difference == 0) return 'TODAY';
    if (difference == 1) return 'TOMORROW';
    if (difference <= 7 && difference > 1) return 'THIS WEEK';

    return '';
  }

  String _relativePostedAt() {
    final rawCreatedAt = data['createdAt'];

    DateTime? createdAt;
    if (rawCreatedAt is Timestamp) {
      createdAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is DateTime) {
      createdAt = rawCreatedAt;
    }

    if (createdAt == null) return '';

    final difference = DateTime.now().difference(createdAt);
    if (difference.inMinutes < 1) return 'Posted just now';
    if (difference.inMinutes < 60) {
      return 'Posted ${difference.inMinutes} mins ago';
    }
    if (difference.inHours < 24) {
      return 'Posted ${difference.inHours}h ago';
    }
    if (difference.inDays < 7) {
      return 'Posted ${difference.inDays}d ago';
    }
    return '';
  }

  String _organiserName() {
    final possibleNames = [
      data['organiserName'],
      data['organizerName'],
      data['hostName'],
      data['createdByName'],
      data['businessName'],
    ];

    for (final value in possibleNames) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }

    return '';
  }

  double? _milesAway() {
    if (userPosition == null) return null;

    final latitude = double.tryParse(data['latitude']?.toString() ?? '');

    final longitude = double.tryParse(data['longitude']?.toString() ?? '');

    if (latitude == null || longitude == null) {
      return null;
    }

    return Geolocator.distanceBetween(
          userPosition!.latitude,
          userPosition!.longitude,
          latitude,
          longitude,
        ) /
        1609.34;
  }

  @override
  Widget build(BuildContext context) {
    final title = data['title']?.toString() ?? '';
    final category = data['category']?.toString() ?? '';
    final location = data['location']?.toString() ?? '';
    final photoUrl = data['photoUrl']?.toString() ?? '';

    final attendeeCount = (data['attendeeCount'] as num?)?.toInt() ?? 0;

    final commentCount = (data['commentCount'] as num?)?.toInt() ?? 0;

    final badge = _dateBadge();
    final milesAway = _milesAway();
    final colour = _categoryColor(category);
    final organiserName = _organiserName();
    final postedAt = _relativePostedAt();

    return LocalLinkSurfaceCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OpportunityDetailScreen(
              opportunityId: opportunityId,
              opportunity: data,
            ),
          ),
        );
      },
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      radius: LocalLinkRadius.lg,
      elevated: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OpportunityImage(
            photoUrl: photoUrl,
            colour: colour,
            icon: _categoryIcon(category),
          ),
          const SizedBox(width: LocalLinkSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _ActivityBadge(),
                    const SizedBox(width: LocalLinkSpacing.xs),
                    if (badge.isNotEmpty) ...[
                      _DateBadge(label: badge),
                      const SizedBox(width: LocalLinkSpacing.xs),
                    ],
                    if (category.isNotEmpty)
                      Flexible(
                        child: Text(
                          category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colour,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: LocalLinkSpacing.xs),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LocalLinkTextStyles.cardTitle.copyWith(fontSize: 16),
                ),
                if (organiserName.isNotEmpty || postedAt.isNotEmpty) ...[
                  const SizedBox(height: LocalLinkSpacing.xxs),
                  Text(
                    [
                      if (organiserName.isNotEmpty) 'By $organiserName',
                      if (postedAt.isNotEmpty) postedAt,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LocalLinkTextStyles.metadata,
                  ),
                ],
                if (location.isNotEmpty) ...[
                  const SizedBox(height: LocalLinkSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 16,
                        color: AppColors.charcoal.withValues(alpha: 0.48),
                      ),
                      const SizedBox(width: LocalLinkSpacing.xxs),
                      Expanded(
                        child: Text(
                          location,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: LocalLinkTextStyles.metadata.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: LocalLinkSpacing.xs),
                Wrap(
                  spacing: LocalLinkSpacing.sm,
                  runSpacing: LocalLinkSpacing.xs,
                  children: [
                    if (milesAway != null)
                      _MetaItem(
                        icon: Icons.near_me_outlined,
                        label: '${milesAway.toStringAsFixed(1)} miles',
                      ),
                    if (attendeeCount > 0)
                      _MetaItem(
                        icon: Icons.people_alt_outlined,
                        label: '$attendeeCount going',
                      ),
                    if (commentCount > 0)
                      _MetaItem(
                        icon: Icons.chat_bubble_outline_rounded,
                        label:
                            '$commentCount ${commentCount == 1 ? 'comment' : 'comments'}',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OpportunityImage extends StatelessWidget {
  final String photoUrl;
  final Color colour;
  final IconData icon;

  const _OpportunityImage({
    required this.photoUrl,
    required this.colour,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: LocalLinkImage(
        imageUrl: photoUrl,
        fallbackIcon: icon,
        accentColor: colour,
        semanticLabel: 'Activity image',
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  final String label;

  const _DateBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.xs,
        vertical: LocalLinkSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.activityBlue.withValues(alpha: 0.12),
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

class _ActivityBadge extends StatelessWidget {
  const _ActivityBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.xs,
        vertical: LocalLinkSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.activityBlue.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
      ),
      child: Text(
        'Activity',
        style: LocalLinkTextStyles.status.copyWith(
          color: AppColors.activityBlue,
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.charcoal.withValues(alpha: 0.54)),
        const SizedBox(width: LocalLinkSpacing.xxs),
        Text(label, style: LocalLinkTextStyles.metadata.copyWith(fontSize: 12)),
      ],
    );
  }
}
