import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../screens/business_detail_screen.dart';
import '../screens/post_service_request_screen.dart';
import '../services/local_discovery_filters.dart';
import '../services/service_catalog_discovery_service.dart';
import '../theme/app_colors.dart';
import '../utils/helpers.dart';
import 'category_filter.dart';
import 'local_link_surface_card.dart';
import 'marketplace_business_card.dart';
import 'opportunity_card.dart';
import 'opportunity_search.dart';

class OpportunityFeed extends StatefulWidget {
  const OpportunityFeed({super.key});

  @override
  State<OpportunityFeed> createState() => _OpportunityFeedState();
}

class _OpportunityFeedState extends State<OpportunityFeed> {
  Position? userPosition;

  String selectedExperience = 'All';
  String selectedCategory = 'All';
  String searchText = '';
  bool showRefineControls = false;

  final experienceFilters = const [
    'All',
    'Activities',
    'Services',
    'Community Help',
  ];

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

  final communityHelpCategories = const [
    'All',
    'Missing pets',
    'Lost items',
    'Found items',
    'Free items',
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

  void _logQueryError(String queryName, Object? error) {
    assert(() {
      debugPrint('OpportunityFeed $queryName failed: $error');
      if (error is FirebaseException) {
        debugPrint(
          'OpportunityFeed $queryName FirebaseException code=${error.code} plugin=${error.plugin} message=${error.message}',
        );
      }
      return true;
    }());
  }

  bool _matchesFilters(Map<String, dynamic> data) {
    final eventDate = data['eventDate'];

    if (eventDate != null && eventDate.toDate().isBefore(DateTime.now())) {
      return false;
    }

    final category = data['category']?.toString() ?? '';
    final title = data['title']?.toString().toLowerCase() ?? '';
    final name = data['name']?.toString().toLowerCase() ?? '';
    final businessName = data['businessName']?.toString().toLowerCase() ?? '';
    final serviceName = data['serviceName']?.toString().toLowerCase() ?? '';
    final description = data['description']?.toString().toLowerCase() ?? '';

    final matchesCategory =
        selectedCategory == 'All' || selectedCategory == category;

    final matchesSearch =
        searchText.isEmpty ||
        title.contains(searchText) ||
        name.contains(searchText) ||
        businessName.contains(searchText) ||
        serviceName.contains(searchText) ||
        description.contains(searchText) ||
        category.toLowerCase().contains(searchText);

    return matchesCategory && matchesSearch;
  }

  bool _matchesText(Map<String, dynamic> data) {
    return LocalDiscoveryFilters.matchesText(data, searchText);
  }

  bool _matchesCommunityHelpCategory(Map<String, dynamic> data) {
    if (selectedCategory == 'All') return true;

    final type = data['type']?.toString() ?? 'lost_found';
    final mode = data['mode']?.toString() ?? 'lost';
    final itemCategory = data['itemCategory']?.toString() ?? '';

    if (selectedCategory == 'Missing pets') {
      return type == 'lost_found' && mode == 'lost' && itemCategory == 'Pet';
    }

    if (selectedCategory == 'Lost items') {
      return type == 'lost_found' && mode == 'lost' && itemCategory != 'Pet';
    }

    if (selectedCategory == 'Found items') {
      return type == 'lost_found' && mode == 'found';
    }

    if (selectedCategory == 'Free items') {
      return type == 'free_item';
    }

    return true;
  }

  bool _matchesExperience(_FeedItem item) {
    if (selectedExperience == 'Activities') {
      return item.kind == _FeedItemKind.activity;
    }

    if (selectedExperience == 'Services') {
      return item.kind == _FeedItemKind.businessAvailability ||
          item.kind == _FeedItemKind.serviceBusiness;
    }

    if (selectedExperience == 'Community Help') {
      return item.kind == _FeedItemKind.communityHelp;
    }

    return true;
  }

  List<_FeedItem> _buildItems({
    required List<QueryDocumentSnapshot> opportunities,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>>
    availabilityPosts,
    required List<ServiceCatalogItem> servicePosts,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>>
    communityHelpPosts,
  }) {
    final items = <_FeedItem>[];

    for (final doc in opportunities) {
      final data = doc.data() as Map<String, dynamic>;

      if (!_matchesFilters(data)) continue;

      items.add(
        _FeedItem(
          id: doc.id,
          kind: _FeedItemKind.activity,
          data: data,
          distance: _distance(data),
        ),
      );
    }

    final groupedAvailability =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

    for (final doc in availabilityPosts) {
      final data = doc.data();

      if (data['isActive'] == false || !_matchesText(data)) continue;

      final availabilityAt = data['availabilityAt'];
      if (availabilityAt is Timestamp &&
          availabilityAt.toDate().isBefore(DateTime.now())) {
        continue;
      }

      final businessId = data['businessId']?.toString().trim() ?? '';
      if (businessId.isEmpty) continue;

      groupedAvailability.putIfAbsent(businessId, () => []).add(doc);
    }

    groupedAvailability.forEach((businessId, posts) {
      posts.sort((a, b) {
        final aTime = a.data()['availabilityAt'];
        final bTime = b.data()['availabilityAt'];
        if (aTime is Timestamp && bTime is Timestamp) {
          return aTime.compareTo(bTime);
        }
        return 0;
      });

      items.add(
        _FeedItem(
          id: businessId,
          businessId: businessId,
          kind: _FeedItemKind.businessAvailability,
          data: posts.first.data(),
          distance: _distance(posts.first.data()),
          availabilityPosts: posts,
        ),
      );
    });

    final groupedServices = <String, List<ServiceCatalogItem>>{};
    final serviceBusinessData = <String, Map<String, dynamic>>{};

    for (final item in servicePosts) {
      final data = item.serviceData;

      if (!LocalDiscoveryFilters.isServiceDiscoverable(data)) {
        continue;
      }

      groupedServices.putIfAbsent(item.businessId, () => []).add(item);
      serviceBusinessData[item.businessId] = item.businessData;
    }

    groupedServices.forEach((businessId, services) {
      if (services.isEmpty) return;

      final businessData = serviceBusinessData[businessId] ?? const {};
      final groupMatches =
          ServiceCatalogDiscoveryService.businessServiceGroupMatches(
            businessData: businessData,
            services: services,
            query: searchText,
          );

      if (!groupMatches) return;

      final sortedServices =
          ServiceCatalogDiscoveryService.sortServicesForSearch(
            services: services,
            query: searchText,
          );

      items.add(
        _FeedItem(
          id: businessId,
          businessId: businessId,
          kind: _FeedItemKind.serviceBusiness,
          data: businessData,
          distance: _distance(businessData),
          services: sortedServices,
        ),
      );
    });

    for (final doc in communityHelpPosts) {
      final data = doc.data();

      if (!LocalDiscoveryFilters.isCommunityHelpDiscoverable(
        data,
        now: DateTime.now(),
      )) {
        continue;
      }
      if (!_matchesText(data) || !_matchesCommunityHelpCategory(data)) continue;

      items.add(
        _FeedItem(
          id: doc.id,
          kind: _FeedItemKind.communityHelp,
          data: data,
          distance: _distance(data),
        ),
      );
    }

    return items.where(_matchesExperience).toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
  }

  double _distance(Map<String, dynamic> data) {
    if (userPosition == null) return 999999;

    final lat = double.tryParse(
      (data['latitude'] ?? data['approxLatitude'])?.toString() ?? '',
    );
    final lng = double.tryParse(
      (data['longitude'] ?? data['approxLongitude'])?.toString() ?? '',
    );

    if (lat == null || lng == null) return 999999;

    return Geolocator.distanceBetween(
      userPosition!.latitude,
      userPosition!.longitude,
      lat,
      lng,
    );
  }

  bool get _hasActiveRefinement =>
      searchText.isNotEmpty || selectedCategory != 'All';

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
                'Happening near you',
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
        CategoryFilter(
          categories: experienceFilters,
          selectedCategory: selectedExperience,
          onSelected: (filter) {
            setState(() {
              selectedExperience = filter;
              selectedCategory = 'All';
            });
          },
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            setState(() {
              showRefineControls = !showRefineControls;
            });
          },
          icon: Icon(
            showRefineControls ? Icons.tune_rounded : Icons.tune_outlined,
            size: 18,
          ),
          label: Text(
            _hasActiveRefinement ? 'Refine nearby results' : 'Refine nearby',
          ),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textMuted,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        if (showRefineControls || _hasActiveRefinement) ...[
          const SizedBox(height: 10),
          OpportunitySearch(
            onChanged: (value) {
              setState(() {
                searchText = value.trim().toLowerCase();
              });
            },
          ),
          const SizedBox(height: 12),
          if (selectedExperience != 'Services') ...[
            CategoryFilter(
              categories: selectedExperience == 'Community Help'
                  ? communityHelpCategories
                  : categories,
              selectedCategory: selectedCategory,
              onSelected: (category) {
                setState(() {
                  selectedCategory = category;
                });
              },
            ),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 4),
        ] else
          const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('opportunities')
              .where('isActive', isEqualTo: true)
              .snapshots(),
          builder: (context, opportunitySnapshot) {
            if (opportunitySnapshot.hasError) {
              _logQueryError('opportunities query', opportunitySnapshot.error);
              return const _FeedMessage(
                icon: Icons.error_outline_rounded,
                title: 'Unable to load activities',
                message: 'Please try again in a moment.',
              );
            }

            if (!opportunitySnapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.activityBlue,
                  ),
                ),
              );
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('availabilityPosts')
                  .where('isActive', isEqualTo: true)
                  .snapshots(),
              builder: (context, availabilitySnapshot) {
                if (availabilitySnapshot.hasError &&
                    selectedExperience == 'Services') {
                  _logQueryError(
                    'availabilityPosts query',
                    availabilitySnapshot.error,
                  );
                  return const _FeedMessage(
                    icon: Icons.error_outline_rounded,
                    title: 'Unable to load services',
                    message: 'Please try again in a moment.',
                  );
                }

                if (!availabilitySnapshot.hasData &&
                    !availabilitySnapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.serviceGreen,
                      ),
                    ),
                  );
                }

                return StreamBuilder<List<ServiceCatalogItem>>(
                  stream:
                      ServiceCatalogDiscoveryService.watchDiscoverableServices(),
                  builder: (context, serviceSnapshot) {
                    if (serviceSnapshot.hasError &&
                        selectedExperience == 'Services') {
                      _logQueryError(
                        'business service catalogue query',
                        serviceSnapshot.error,
                      );
                      return const _FeedMessage(
                        icon: Icons.error_outline_rounded,
                        title: 'Unable to load services',
                        message: 'Please try again in a moment.',
                      );
                    }

                    if (!serviceSnapshot.hasData &&
                        !serviceSnapshot.hasError &&
                        selectedExperience == 'Services') {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.serviceGreen,
                          ),
                        ),
                      );
                    }

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('communityHelpPosts')
                          .where('isActive', isEqualTo: true)
                          .snapshots(),
                      builder: (context, communityHelpSnapshot) {
                        if (communityHelpSnapshot.hasError &&
                            selectedExperience == 'Community Help') {
                          return const _FeedMessage(
                            icon: Icons.error_outline_rounded,
                            title: 'Unable to load Community Help',
                            message: 'Please try again in a moment.',
                          );
                        }

                        if (!communityHelpSnapshot.hasData &&
                            !communityHelpSnapshot.hasError &&
                            selectedExperience == 'Community Help') {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            ),
                          );
                        }

                        final items = _buildItems(
                          opportunities: opportunitySnapshot.data!.docs,
                          availabilityPosts: availabilitySnapshot.hasError
                              ? const []
                              : availabilitySnapshot.data?.docs ?? const [],
                          servicePosts: serviceSnapshot.hasError
                              ? const []
                              : serviceSnapshot.data ?? const [],
                          communityHelpPosts: communityHelpSnapshot.hasError
                              ? const []
                              : communityHelpSnapshot.data?.docs ?? const [],
                        );

                        if (items.isEmpty) {
                          final isServices = selectedExperience == 'Services';
                          final isCommunityHelp =
                              selectedExperience == 'Community Help';
                          return _FeedMessage(
                            icon: Icons.search_off_rounded,
                            title: isServices
                                ? 'No services are available nearby right now'
                                : isCommunityHelp
                                ? 'No Community Help posts nearby right now'
                                : 'No activities found',
                            message: isServices
                                ? 'Try again later or open a business profile to browse services.'
                                : isCommunityHelp
                                ? 'Try another help filter, search term or nearby area.'
                                : 'Try another filter, search term or nearby area.',
                          );
                        }

                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 28),
                          itemCount: items.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = items[index];

                            if (item.kind == _FeedItemKind.activity) {
                              return OpportunityCard(
                                opportunityId: item.id,
                                data: item.data,
                                userPosition: userPosition,
                              );
                            }

                            if (item.kind == _FeedItemKind.communityHelp) {
                              return _CommunityHelpFeedCard(
                                postId: item.id,
                                data: item.data,
                                distance: item.distance,
                              );
                            }

                            if (item.kind == _FeedItemKind.serviceBusiness) {
                              return _ServiceBusinessFeedCard(
                                businessId: item.businessId ?? item.id,
                                businessData: item.data,
                                services: item.services,
                                distance: item.distance,
                              );
                            }

                            return MarketplaceBusinessCard(
                              businessId: item.businessId ?? item.id,
                              availabilityPosts: item.availabilityPosts,
                              userPosition: userPosition,
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }
}

enum _FeedItemKind {
  activity,
  businessAvailability,
  serviceBusiness,
  communityHelp,
}

class _FeedItem {
  final String id;
  final String? businessId;
  final _FeedItemKind kind;
  final Map<String, dynamic> data;
  final double distance;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> availabilityPosts;
  final List<ServiceCatalogItem> services;

  const _FeedItem({
    required this.id,
    this.businessId,
    required this.kind,
    required this.data,
    required this.distance,
    this.availabilityPosts = const [],
    this.services = const [],
  });
}

class _ServiceBusinessFeedCard extends StatelessWidget {
  const _ServiceBusinessFeedCard({
    required this.businessId,
    required this.businessData,
    required this.services,
    required this.distance,
  });

  final String businessId;
  final Map<String, dynamic> businessData;
  final List<ServiceCatalogItem> services;
  final double distance;

  @override
  Widget build(BuildContext context) {
    final businessName = safeText(
      businessData['businessName'] ?? businessData['name'],
      'Local business',
    );
    final category = safeText(businessData['category'], '');
    final location = safeText(
      businessData['serviceArea'] ??
          businessData['publicLocation'] ??
          businessData['location'] ??
          businessData['address'],
      '',
    );
    final distanceText = distance >= 999999
        ? ''
        : '${(distance / 1609.344).toStringAsFixed(1)} miles';

    return LocalLinkSurfaceCard(
      padding: const EdgeInsets.all(14),
      radius: 20,
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        if (location.isNotEmpty)
                          _ServiceBusinessMeta(
                            icon: Icons.place_outlined,
                            label: location,
                          ),
                        if (distanceText.isNotEmpty)
                          _ServiceBusinessMeta(
                            icon: Icons.near_me_outlined,
                            label: distanceText,
                          ),
                        if (category.isNotEmpty)
                          _ServiceBusinessMeta(
                            icon: Icons.handyman_outlined,
                            label: category,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _openBusiness(context),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.serviceGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
                child: const Text('View business'),
              ),
            ],
          ),
          const SizedBox(height: 13),
          SizedBox(
            height: 142,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: services.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final service = services[index];
                return _CompactServiceTile(
                  businessId: businessId,
                  serviceId: service.serviceId,
                  serviceData: service.serviceData,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openBusiness(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessDetailScreen(businessId: businessId),
      ),
    );
  }
}

class _CompactServiceTile extends StatelessWidget {
  const _CompactServiceTile({
    required this.businessId,
    required this.serviceId,
    required this.serviceData,
  });

  final String businessId;
  final String serviceId;
  final Map<String, dynamic> serviceData;

  @override
  Widget build(BuildContext context) {
    final name = safeText(
      serviceData['name'] ?? serviceData['title'],
      'Service',
    );
    final details = safeText(
      serviceData['details'] ?? serviceData['description'],
      '',
    );
    final price = formatPrice(serviceData['price']);

    return SizedBox(
      width: 214,
      child: LocalLinkSurfaceCard(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BusinessDetailScreen(
                businessId: businessId,
                initialServiceId: serviceId,
              ),
            ),
          );
        },
        padding: const EdgeInsets.all(12),
        radius: 14,
        elevated: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.serviceGreen.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.handyman_outlined,
                    color: AppColors.serviceGreen,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    price,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.serviceGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 15,
                height: 1.14,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                details,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const Spacer(),
            const Row(
              children: [
                Text(
                  'Open service',
                  style: TextStyle(
                    color: AppColors.serviceGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.serviceGreen,
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceBusinessMeta extends StatelessWidget {
  const _ServiceBusinessMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.charcoal.withValues(alpha: 0.54)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _CommunityHelpFeedCard extends StatelessWidget {
  const _CommunityHelpFeedCard({
    required this.postId,
    required this.data,
    required this.distance,
  });

  final String postId;
  final Map<String, dynamic> data;
  final double distance;

  @override
  Widget build(BuildContext context) {
    final type = data['type']?.toString() ?? 'lost_found';
    final mode = data['mode']?.toString() ?? 'lost';
    final title = data['title']?.toString() ?? 'Community Help post';
    final itemCategory = data['itemCategory']?.toString() ?? 'Item';
    final location =
        data['publicLocation']?.toString() ??
        data['location']?.toString() ??
        '';
    final photoUrl = data['photoUrl']?.toString() ?? '';
    final lookoutCount = (data['lookoutCount'] as num?)?.toInt() ?? 0;
    final status = type == 'free_item'
        ? 'FREE'
        : mode == 'found'
        ? 'FOUND'
        : 'MISSING';
    final distanceText = distance >= 999999
        ? ''
        : '${(distance / 1609.344).toStringAsFixed(distance < 1609.344 ? 1 : 1)} miles';

    return LocalLinkSurfaceCard(
      padding: const EdgeInsets.all(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostServiceRequestScreen(initialPostId: postId),
            ),
          );
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CommunityHelpThumb(photoUrl: photoUrl, mode: mode, type: type),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _HelpStatusPill(label: status),
                      Text(
                        itemCategory,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.charcoal,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (location.isNotEmpty)
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      if (distanceText.isNotEmpty)
                        _HelpMeta(
                          icon: Icons.near_me_outlined,
                          label: distanceText,
                        ),
                      if (lookoutCount > 0)
                        _HelpMeta(
                          icon: Icons.visibility_outlined,
                          label:
                              '$lookoutCount ${lookoutCount == 1 ? 'lookout' : 'lookouts'}',
                        ),
                      const _HelpMeta(
                        icon: Icons.volunteer_activism_outlined,
                        label: 'Community Help',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Icon(Icons.chevron_right, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityHelpThumb extends StatelessWidget {
  const _CommunityHelpThumb({
    required this.photoUrl,
    required this.mode,
    required this.type,
  });

  final String photoUrl;
  final String mode;
  final String type;

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          photoUrl,
          width: 78,
          height: 78,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _CommunityHelpPlaceholder(mode: mode, type: type);
          },
        ),
      );
    }

    return _CommunityHelpPlaceholder(mode: mode, type: type);
  }
}

class _CommunityHelpPlaceholder extends StatelessWidget {
  const _CommunityHelpPlaceholder({required this.mode, required this.type});

  final String mode;
  final String type;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        type == 'free_item'
            ? Icons.card_giftcard_outlined
            : mode == 'found'
            ? Icons.inventory_2_outlined
            : Icons.search_outlined,
        color: AppColors.primary,
      ),
    );
  }
}

class _HelpStatusPill extends StatelessWidget {
  const _HelpStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isUrgent = label == 'MISSING';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isUrgent ? AppColors.error : AppColors.serviceGreen).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isUrgent ? AppColors.error : AppColors.serviceGreen,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _HelpMeta extends StatelessWidget {
  const _HelpMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
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
