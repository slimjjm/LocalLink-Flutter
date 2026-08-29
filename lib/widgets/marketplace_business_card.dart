import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../screens/availability_detail_screen.dart';
import '../screens/business_detail_screen.dart';
import '../theme/app_colors.dart';
import '../utils/helpers.dart';
import 'local_link_surface_card.dart';

class MarketplaceBusinessCard extends StatelessWidget {
  final String businessId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> availabilityPosts;
  final Position? userPosition;

  const MarketplaceBusinessCard({
    super.key,
    required this.businessId,
    required this.availabilityPosts,
    required this.userPosition,
  });

  double? _milesAway(Map<String, dynamic> businessData) {
    if (userPosition == null) return null;

    final latitude = double.tryParse(
      businessData['latitude']?.toString() ?? '',
    );
    final longitude = double.tryParse(
      businessData['longitude']?.toString() ?? '',
    );

    if (latitude == null || longitude == null) return null;

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
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .get(),
      builder: (context, snapshot) {
        final businessData = snapshot.data?.data() ?? {};
        final firstPost = availabilityPosts.first.data();
        final businessName = safeText(
          businessData['businessName'] ?? firstPost['businessName'],
          'Business',
        );
        final category = safeText(
          businessData['category'] ?? firstPost['category'],
          'Service',
        );
        final rating = businessData['averageRating'];
        final reviewCount = businessData['reviewCount'];
        final milesAway = _milesAway(businessData);
        final visiblePosts = availabilityPosts.take(8).toList();
        final photoUrls = List<String>.from(
          businessData['photoURLs'] ?? businessData['galleryUrls'] ?? [],
        );
        final bannerUrl =
            (businessData['bannerImageUrl'] ?? businessData['bannerUrl'])
                ?.toString()
                .trim();
        final coverUrl = bannerUrl?.isNotEmpty == true
            ? bannerUrl
            : photoUrls.isNotEmpty
            ? photoUrls.first
            : null;
        final hasTodayAvailability = availabilityPosts.any((post) {
          final value = post.data()['availabilityAt'];
          if (value is! Timestamp) return false;

          final date = value.toDate();
          final now = DateTime.now();
          return date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;
        });

        return LocalLinkSurfaceCard(
          padding: EdgeInsets.zero,
          radius: 24,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BusinessDetailScreen(businessId: businessId),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: SizedBox(
                  height: 96,
                  width: double.infinity,
                  child: coverUrl == null
                      ? Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.serviceGreen.withValues(alpha: 0.9),
                                AppColors.charcoal.withValues(alpha: 0.84),
                              ],
                            ),
                          ),
                          child: const Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: EdgeInsets.only(right: 22),
                              child: Icon(
                                Icons.storefront_outlined,
                                color: Colors.white,
                                size: 42,
                              ),
                            ),
                          ),
                        )
                      : Image.network(
                          coverUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: AppColors.serviceGreen.withValues(
                                alpha: 0.08,
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.serviceGreen,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: AppColors.serviceGreen.withValues(
                                alpha: 0.10,
                              ),
                              child: const Icon(
                                Icons.storefront_outlined,
                                color: AppColors.serviceGreen,
                              ),
                            );
                          },
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: AppColors.serviceGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.storefront_outlined,
                        color: AppColors.serviceGreen,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            businessName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.charcoal,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            children: [
                              _Meta(
                                icon: Icons.category_outlined,
                                label: category,
                              ),
                              if (rating is num)
                                _Meta(
                                  icon: Icons.star_rounded,
                                  label:
                                      '${rating.toStringAsFixed(1)} (${reviewCount ?? 0})',
                                ),
                              if (milesAway != null)
                                _Meta(
                                  icon: Icons.near_me_outlined,
                                  label:
                                      '${milesAway.toStringAsFixed(1)} miles',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.serviceGreen.withValues(alpha: 0.11),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        hasTodayAvailability ? 'Free Today' : 'Time Available',
                        style: const TextStyle(
                          color: AppColors.serviceGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (availabilityPosts.length > visiblePosts.length)
                      const Text(
                        'View All',
                        style: TextStyle(
                          color: AppColors.serviceGreen,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 152,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: visiblePosts.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final post = visiblePosts[index];
                    return _AvailabilityTile(
                      postId: post.id,
                      data: post.data(),
                      businessData: businessData,
                      isLastAppointmentToday: _isLastAppointmentToday(
                        post,
                        availabilityPosts,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isLastAppointmentToday(
    QueryDocumentSnapshot<Map<String, dynamic>> post,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> posts,
  ) {
    final value = post.data()['availabilityAt'];
    if (value is! Timestamp) return false;

    final date = value.toDate();
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (!isToday) return false;

    return !posts.any((other) {
      if (other.id == post.id) return false;
      final otherValue = other.data()['availabilityAt'];
      if (otherValue is! Timestamp) return false;
      final otherDate = otherValue.toDate();
      return otherDate.year == date.year &&
          otherDate.month == date.month &&
          otherDate.day == date.day &&
          otherDate.isAfter(date);
    });
  }
}

class _AvailabilityTile extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> data;
  final Map<String, dynamic> businessData;
  final bool isLastAppointmentToday;

  const _AvailabilityTile({
    required this.postId,
    required this.data,
    required this.businessData,
    required this.isLastAppointmentToday,
  });

  String _timeLabel(BuildContext context) {
    final value = data['availabilityAt'];
    if (value is! Timestamp) return 'Time available';

    final date = value.toDate();
    final now = DateTime.now();
    final time = TimeOfDay.fromDateTime(date).format(context);

    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Today $time';
    }

    final tomorrow = now.add(const Duration(days: 1));
    if (date.year == tomorrow.year &&
        date.month == tomorrow.month &&
        date.day == tomorrow.day) {
      return 'Tomorrow $time';
    }

    return '${date.day}/${date.month} $time';
  }

  Duration? _startsIn() {
    final value = data['availabilityAt'];
    if (value is! Timestamp) return null;

    final difference = value.toDate().difference(DateTime.now());
    return difference.isNegative ? null : difference;
  }

  List<_AvailabilityBadgeData> _badges() {
    final startsIn = _startsIn();
    final createdAt = dateTimeFromValue(data['createdAt']);
    final recentlyAdded =
        createdAt != null &&
        DateTime.now().difference(createdAt).inMinutes < 60;

    if (startsIn != null && startsIn.inMinutes <= 15) {
      return const [
        _AvailabilityBadgeData(icon: Icons.flash_on_rounded, label: 'Free Now'),
      ];
    }

    if (startsIn != null && startsIn.inMinutes < 120) {
      return [
        _AvailabilityBadgeData(
          icon: Icons.schedule_rounded,
          label: 'Starts in ${startsIn.inMinutes} mins',
        ),
      ];
    }

    if (isLastAppointmentToday) {
      return const [
        _AvailabilityBadgeData(
          icon: Icons.local_fire_department_rounded,
          label: 'Last Appointment Today',
        ),
      ];
    }

    if (recentlyAdded) {
      return const [
        _AvailabilityBadgeData(
          icon: Icons.bolt_rounded,
          label: 'Recently Added',
        ),
      ];
    }

    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final serviceName = safeText(data['serviceName'], 'Service');
    final description = safeText(data['description'], '');
    final badges = _badges();

    return SizedBox(
      width: 196,
      child: Material(
        color: AppColors.serviceGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AvailabilityDetailScreen(
                  postId: postId,
                  availabilityData: data,
                  businessData: businessData,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                if (badges.isNotEmpty) ...[
                  _AvailabilityBadge(data: badges.first),
                  const SizedBox(height: 5),
                ],
                Text(
                  _timeLabel(context),
                  style: const TextStyle(
                    color: AppColors.serviceGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                StreamBuilder<int>(
                  stream: Stream<int>.periodic(
                    const Duration(minutes: 1),
                    (tick) => tick,
                  ),
                  builder: (context, _) {
                    return Text(
                      formatFreshnessLabel(
                        createdAt: data['createdAt'],
                        updatedAt: data['updatedAt'],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  formatPrice(data['price']),
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvailabilityBadgeData {
  final IconData icon;
  final String label;

  const _AvailabilityBadgeData({required this.icon, required this.label});
}

class _AvailabilityBadge extends StatelessWidget {
  final _AvailabilityBadgeData data;

  const _AvailabilityBadge({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: 12, color: AppColors.serviceGreen),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.serviceGreen,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Meta({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
