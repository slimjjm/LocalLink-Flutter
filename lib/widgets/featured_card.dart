import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../screens/opportunity_detail_screen.dart';
import '../services/local_discovery_filters.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../utils/distance_helper.dart';
import 'local_link_image.dart';
import 'local_link_surface_card.dart';

class FeaturedCard extends StatelessWidget {
  const FeaturedCard({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Position?>(
      future: LocationService().getCurrentLocation(),
      builder: (context, locationSnapshot) {
        final userPosition = locationSnapshot.data;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('opportunities')
              .where('discoveryVisibility', isEqualTo: 'public')
              .where('isActive', isEqualTo: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const SizedBox.shrink();
            }

            QueryDocumentSnapshot? featured;
            double highestScore = -999999;

            for (final doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              if (!LocalDiscoveryFilters.isActivityDiscoverable(
                data,
                now: DateTime.now(),
              )) {
                continue;
              }

              double score = 0;

              final attendees = (data['attendeeCount'] as num?)?.toInt() ?? 0;

              score += attendees * 3;

              final created = data['createdAt'];

              if (created != null) {
                final days = DateTime.now().difference(created.toDate()).inDays;

                score += (30 - days).clamp(0, 30);
              }

              final lat = double.tryParse(data['latitude']?.toString() ?? '');

              final lng = double.tryParse(data['longitude']?.toString() ?? '');

              if (userPosition != null && lat != null && lng != null) {
                final miles =
                    Geolocator.distanceBetween(
                      userPosition.latitude,
                      userPosition.longitude,
                      lat,
                      lng,
                    ) /
                    1609.34;

                if (miles < 2) {
                  score += 25;
                } else if (miles < 5) {
                  score += 15;
                } else if (miles < 10) {
                  score += 5;
                }
              }

              if (score > highestScore) {
                highestScore = score;
                featured = doc;
              }
            }

            if (featured == null) {
              return const SizedBox.shrink();
            }

            final featuredId = featured.id;
            final data = featured.data() as Map<String, dynamic>;
            final photoUrl = data['photoUrl']?.toString() ?? '';
            final dateLabel = _dateLabel(data);
            final milesAway = userPosition == null
                ? null
                : _milesAway(data, userPosition);
            final attendeeCount = (data['attendeeCount'] as num?)?.toInt() ?? 0;

            return LocalLinkSurfaceCard(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OpportunityDetailScreen(
                      opportunityId: featuredId,
                      opportunity: data,
                    ),
                  ),
                );
              },
              padding: const EdgeInsets.all(0),
              radius: LocalLinkRadius.lg,
              elevated: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    height: 176,
                    child: _FeaturedImage(
                      photoUrl: photoUrl,
                      category: data['category']?.toString() ?? '',
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.11,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    LocalLinkRadius.pill,
                                  ),
                                ),
                                child: Text(
                                  'FEATURED',
                                  style: LocalLinkTextStyles.status.copyWith(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (milesAway != null)
                                _FeaturedMeta(
                                  icon: Icons.near_me_outlined,
                                  label: '${milesAway.toStringAsFixed(1)} mi',
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            data['title'] ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: LocalLinkTextStyles.cardTitle.copyWith(
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Wrap(
                            spacing: 7,
                            runSpacing: 6,
                            children: [
                              if (dateLabel.isNotEmpty)
                                _FeaturedMeta(
                                  icon: Icons.calendar_today_outlined,
                                  label: dateLabel,
                                ),
                              _FeaturedMeta(
                                icon: Icons.people_alt_outlined,
                                label:
                                    '$attendeeCount ${attendeeCount == 1 ? 'going' : 'going'}',
                              ),
                              if ((data['category']?.toString() ?? '')
                                  .isNotEmpty)
                                _FeaturedMeta(
                                  icon: Icons.local_activity_outlined,
                                  label: data['category'].toString(),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            decoration: BoxDecoration(
                              color: AppColors.charcoal,
                              borderRadius: BorderRadius.circular(
                                LocalLinkRadius.sm,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'View details',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(
                                      LocalLinkRadius.xs,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.white,
                                    size: 17,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _dateLabel(Map<String, dynamic> data) {
    final eventDate = data['eventDate'];

    if (eventDate is! Timestamp) {
      return '';
    }

    final date = eventDate.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    final difference = eventDay.difference(today).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Tomorrow';
    if (difference < 7 && difference > 1) return 'This week';

    return '${date.day}/${date.month}';
  }

  double? _milesAway(Map<String, dynamic> data, Position userPosition) {
    final lat = double.tryParse(data['latitude']?.toString() ?? '');
    final lng = double.tryParse(data['longitude']?.toString() ?? '');

    if (lat == null || lng == null) {
      return null;
    }

    return calculateDistanceMiles(
      startLat: userPosition.latitude,
      startLng: userPosition.longitude,
      endLat: lat,
      endLng: lng,
    );
  }
}

class _FeaturedImage extends StatelessWidget {
  final String photoUrl;
  final String category;

  const _FeaturedImage({required this.photoUrl, required this.category});

  @override
  Widget build(BuildContext context) {
    return LocalLinkImage(
      imageUrl: photoUrl,
      aspectRatio: 112 / 176,
      fallbackIcon: Icons.local_activity_outlined,
      accentColor: AppColors.primary,
      semanticLabel: category.isEmpty ? 'Featured activity' : category,
    );
  }
}

class _FeaturedMeta extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeaturedMeta({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: LocalLinkSpacing.xxs),
          Text(
            label,
            style: LocalLinkTextStyles.metadata.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
