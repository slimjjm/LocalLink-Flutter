import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../theme/app_colors.dart';
import 'category_filter.dart';
import 'local_link_surface_card.dart';
import 'opportunity_card.dart';
import 'opportunity_search.dart';

class OpportunityFeed extends StatefulWidget {
  const OpportunityFeed({super.key});

  @override
  State<OpportunityFeed> createState() => _OpportunityFeedState();
}

class _OpportunityFeedState extends State<OpportunityFeed> {
  Position? userPosition;

  String selectedCategory = 'All';
  String searchText = '';

  final categories = const [
    'All',
    'Fitness & Sport',
    'Family',
    'Pets',
    'Hobbies',
    'Social',
    'Volunteering',
    'Learning',
    'Local Deals',
  ];

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();

      if (!mounted) return;

      setState(() {
        userPosition = position;
      });
    } catch (_) {}
  }

  bool _matchesFilters(Map<String, dynamic> data) {
    final eventDate = data['eventDate'];

    if (eventDate != null && eventDate.toDate().isBefore(DateTime.now())) {
      return false;
    }

    final category = data['category']?.toString() ?? '';
    final title = data['title']?.toString().toLowerCase() ?? '';
    final description = data['description']?.toString().toLowerCase() ?? '';

    final matchesCategory =
        selectedCategory == 'All' || selectedCategory == category;

    final matchesSearch =
        searchText.isEmpty ||
        title.contains(searchText) ||
        description.contains(searchText) ||
        category.toLowerCase().contains(searchText);

    return matchesCategory && matchesSearch;
  }

  double _distance(Map<String, dynamic> data) {
    if (userPosition == null) return 999999;

    final lat = double.tryParse(data['latitude']?.toString() ?? '');
    final lng = double.tryParse(data['longitude']?.toString() ?? '');

    if (lat == null || lng == null) return 999999;

    return Geolocator.distanceBetween(
      userPosition!.latitude,
      userPosition!.longitude,
      lat,
      lng,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: const [
            Expanded(
              child: Text(
                'Nearby Opportunities',
                style: TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ),
            Text(
              'Live now',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        OpportunitySearch(
          onChanged: (value) {
            setState(() {
              searchText = value.trim().toLowerCase();
            });
          },
        ),
        const SizedBox(height: 14),
        CategoryFilter(
          categories: categories,
          selectedCategory: selectedCategory,
          onSelected: (category) {
            setState(() {
              selectedCategory = category;
            });
          },
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('opportunities')
              .where('isActive', isEqualTo: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _FeedMessage(
                icon: Icons.error_outline_rounded,
                title: 'Unable to load opportunities',
                message: 'Please try again in a moment.',
              );
            }

            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              );
            }

            final docs = snapshot.data!.docs.where((doc) {
              return _matchesFilters(doc.data() as Map<String, dynamic>);
            }).toList();

            docs.sort((a, b) {
              return _distance(
                a.data() as Map<String, dynamic>,
              ).compareTo(_distance(b.data() as Map<String, dynamic>));
            });

            if (docs.isEmpty) {
              return const _FeedMessage(
                icon: Icons.search_off_rounded,
                title: 'No opportunities found',
                message: 'Try another category, search term or nearby area.',
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 28),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = docs[index];

                return OpportunityCard(
                  opportunityId: doc.id,
                  data: doc.data() as Map<String, dynamic>,
                  userPosition: userPosition,
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _FeedMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _FeedMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalLinkIconBadge(icon: icon),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.charcoal,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 14,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
