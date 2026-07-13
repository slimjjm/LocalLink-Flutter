import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../screens/opportunity_detail_screen.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
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
              radius: 30,
              elevated: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FeaturedImage(
                    photoUrl: photoUrl,
                    category: data['category']?.toString() ?? '',
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
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
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'FEATURED NEARBY',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
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
                        const SizedBox(height: 18),
                        Text(
                          data['title'] ?? '',
                          style: const TextStyle(
                            color: AppColors.charcoal,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            height: 1.04,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 9,
                          runSpacing: 8,
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
                            if ((data['category']?.toString() ?? '').isNotEmpty)
                              _FeaturedMeta(
                                icon: Icons.local_activity_outlined,
                                label: data['category'].toString(),
                              ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Text(
                          data['description'] ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 15,
                            height: 1.42,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          decoration: BoxDecoration(
                            color: AppColors.charcoal,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              _AvatarStack(count: attendeeCount),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'View details and join',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 19,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

    return Geolocator.distanceBetween(
          userPosition.latitude,
          userPosition.longitude,
          lat,
          lng,
        ) /
        1609.34;
  }
}

class _FeaturedImage extends StatelessWidget {
  final String photoUrl;
  final String category;

  const _FeaturedImage({required this.photoUrl, required this.category});

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isNotEmpty) {
      return AspectRatio(
        aspectRatio: 1.62,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _FeaturedFallback(category: category);
              },
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x22000000)],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _FeaturedFallback(category: category);
  }
}

class _FeaturedFallback extends StatelessWidget {
  final String category;

  const _FeaturedFallback({required this.category});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.62,
      child: Container(
        decoration: const BoxDecoration(color: AppColors.surface),
        child: Stack(
          children: [
            Positioned(
              right: -22,
              top: -28,
              child: _SoftCircle(size: 132, color: AppColors.primary),
            ),
            Positioned(
              left: 18,
              bottom: 18,
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.local_activity_outlined,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
            ),
            Positioned(
              left: 92,
              right: 18,
              bottom: 22,
              child: Text(
                category.isEmpty ? 'Local discovery' : category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
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
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  final int count;

  const _AvatarStack({required this.count});

  @override
  Widget build(BuildContext context) {
    final visibleCount = count.clamp(1, 3);

    return SizedBox(
      width: 26.0 + (visibleCount * 18),
      height: 32,
      child: Stack(
        children: [
          for (var index = 0; index < visibleCount; index += 1)
            Positioned(
              left: index * 18,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: index.isEven
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.charcoal, width: 1.4),
                ),
                child: Icon(
                  index.isEven
                      ? Icons.person_outline_rounded
                      : Icons.favorite_border_rounded,
                  size: 15,
                  color: index.isEven ? AppColors.primary : Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SoftCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _SoftCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
    );
  }
}
