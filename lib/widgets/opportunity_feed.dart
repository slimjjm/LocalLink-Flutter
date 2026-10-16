import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../screens/business_detail_screen.dart';
import '../screens/customer_service_request_screen.dart';
import '../screens/organisation_detail_screen.dart';
import '../screens/opportunity_detail_screen.dart';
import '../screens/post_service_request_screen.dart';
import '../services/business_discovery_service.dart';
import '../services/community_help_lifecycle.dart';
import '../services/community_help_location.dart';
import '../services/home_feed_rules.dart';
import '../services/organisation_discovery_service.dart';
import '../services/home_business_discovery_policy.dart';
import '../services/local_discovery_filters.dart';
import '../services/location_service.dart';
import '../services/service_catalog_discovery_service.dart';
import '../services/service_request_marketplace.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../utils/helpers.dart';
import 'local_link_chip.dart';
import 'local_link_image.dart';
import 'local_link_section_header.dart';
import 'local_link_states.dart';
import 'local_link_surface_card.dart';
import 'marketplace_business_card.dart';
import 'opportunity_card.dart';
import 'opportunity_search.dart';

Color _communityAccent({required String mode, required String type}) {
  if (type == 'free_item') return AppColors.communityTeal;
  if (mode == 'found') return AppColors.serviceGreen;
  return AppColors.lost;
}

IconData _communityFallbackIcon({
  required String mode,
  required String type,
  required String itemCategory,
}) {
  if (type == 'free_item') return Icons.card_giftcard_outlined;
  if (itemCategory.trim().toLowerCase() == 'pet') return Icons.pets_outlined;
  return mode == 'lost' ? Icons.search_outlined : Icons.inventory_2_outlined;
}

String _distanceLabel(double? distanceMeters) {
  if (distanceMeters == null) return '';
  return '${(distanceMeters / 1609.344).toStringAsFixed(1)} miles';
}

class OpportunityFeed extends StatefulWidget {
  const OpportunityFeed({
    super.key,
    this.initialCategory = HomeDiscoveryCategory.nearby,
    this.onCategorySelected,
    this.onLocalityChanged,
    this.contextualActionsBuilder,
    this.showContent = true,
  });

  final HomeDiscoveryCategory initialCategory;
  final ValueChanged<HomeDiscoveryCategory>? onCategorySelected;
  final ValueChanged<String?>? onLocalityChanged;
  final Widget Function(BuildContext context, HomeDiscoveryCategory category)?
  contextualActionsBuilder;
  final bool showContent;

  @override
  State<OpportunityFeed> createState() => _OpportunityFeedState();
}

// Exercise the actual Home assembler without starting Firebase or location streams.
@visibleForTesting
List<HomeFeedCandidate<Map<String, dynamic>>>
buildHomeOrganisationDiscoveryForTest({
  required List<OrganisationDiscoveryRecord> organisations,
  required Position? position,
  List<QueryDocumentSnapshot> opportunities = const [],
  HomeDiscoveryCategory category = HomeDiscoveryCategory.nearby,
  String query = '',
}) {
  final state = _OpportunityFeedState()
    ..userPosition = position
    .._selectedHomeCategory = category
    ..searchText = query;
  final items = state._buildItems(
    organisations: organisations,
    opportunities: opportunities,
    availabilityPosts: const [],
    servicePosts: const [],
    businesses: const [],
    communityHelpPosts: const [],
    serviceRequests: const [],
  );
  return [
    for (final item in items)
      HomeFeedCandidate(
        item: {'id': item.id, 'data': item.data},
        type: state._homeFeedContentType(item),
        distanceMiles: state._distanceMilesFromMeters(item.distance),
      ),
  ];
}

enum _LocationLookupState { loading, ready, unavailable }

class _OpportunityFeedState extends State<OpportunityFeed>
    with WidgetsBindingObserver {
  Position? userPosition;
  _LocationLookupState _locationLookupState = _LocationLookupState.loading;
  bool _locationLookupInProgress = false;
  late HomeDiscoveryCategory _selectedHomeCategory = widget.initialCategory;

  String selectedCategory = 'All';
  String selectedActivityType = 'All';
  String searchText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.showContent) {
      _loadLocation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(OpportunityFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.showContent && widget.showContent) {
      _loadLocation();
    }
    if (oldWidget.initialCategory != widget.initialCategory &&
        widget.initialCategory != _selectedHomeCategory) {
      _selectedHomeCategory = widget.initialCategory;
      selectedCategory = 'All';
      selectedActivityType = 'All';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.showContent) {
      _loadLocation(force: true);
    }
  }

  Future<void> _loadLocation({bool force = false}) async {
    if (_locationLookupInProgress) return;

    setState(() {
      _locationLookupInProgress = true;
      if (force || _locationLookupState != _LocationLookupState.ready) {
        _locationLookupState = _LocationLookupState.loading;
      }
    });

    final previousPosition = userPosition;
    final position = await LocationService().getCurrentLocation();

    if (!mounted) return;

    final validPosition =
        position != null &&
        HomeBusinessDiscoveryPolicy.hasValidCoordinates(
          position.latitude,
          position.longitude,
        );

    if (validPosition &&
        previousPosition != null &&
        !HomeBusinessDiscoveryPolicy.hasMeaningfulLocationChange(
          previousLatitude: previousPosition.latitude,
          previousLongitude: previousPosition.longitude,
          nextLatitude: position.latitude,
          nextLongitude: position.longitude,
        )) {
      setState(() {
        _locationLookupState = _LocationLookupState.ready;
        _locationLookupInProgress = false;
      });
      unawaited(_publishLocality(position));
      return;
    }

    setState(() {
      userPosition = validPosition ? position : null;
      _locationLookupState = validPosition
          ? _LocationLookupState.ready
          : _LocationLookupState.unavailable;
      _locationLookupInProgress = false;
    });
    if (validPosition) {
      unawaited(_publishLocality(position));
    } else {
      widget.onLocalityChanged?.call(null);
    }
  }

  Future<void> _publishLocality(Position position) async {
    String? locality;
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 2), onTimeout: () => const []);
      for (final value in placemarks.expand(
        (place) => [
          place.locality,
          place.subLocality,
          place.subAdministrativeArea,
        ],
      )) {
        final text = value?.trim() ?? '';
        if (text.isNotEmpty) {
          locality = text;
          break;
        }
      }
    } catch (_) {
      locality = null;
    }
    if (mounted) widget.onLocalityChanged?.call(locality);
  }

  void _retryLocationLookup() {
    _loadLocation(force: true);
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

  bool _matchesActivityFilters(Map<String, dynamic> data) {
    if (!LocalDiscoveryFilters.isActivityDiscoverable(
      data,
      now: DateTime.now(),
    )) {
      return false;
    }

    return LocalDiscoveryFilters.matchesActivityCategory(
          data,
          selectedCategory,
        ) &&
        LocalDiscoveryFilters.matchesActivityType(data, selectedActivityType) &&
        LocalDiscoveryFilters.matchesText(data, searchText);
  }

  bool _matchesText(Map<String, dynamic> data) {
    return LocalDiscoveryFilters.matchesText(data, searchText);
  }

  bool _matchesCommunityHelpCategory(Map<String, dynamic> data) {
    if (selectedCategory == 'All') return true;

    final type = data['type']?.toString() ?? 'lost_found';
    final mode = data['mode']?.toString() ?? 'lost';
    final itemCategory = data['itemCategory']?.toString() ?? '';

    if (!CommunityHelpLifecycle.isVisibleInLostFoundUx(data)) return false;

    if (selectedCategory == 'Missing pets') {
      return type == 'lost_found' && mode == 'lost' && itemCategory == 'Pet';
    }

    if (selectedCategory == 'Lost items') {
      return type == 'lost_found' && mode == 'lost' && itemCategory != 'Pet';
    }

    if (selectedCategory == 'Found items') {
      return type == 'lost_found' && mode == 'found';
    }

    return true;
  }

  List<_FeedItem> _buildItems({
    required List<QueryDocumentSnapshot> opportunities,
    required List<OrganisationDiscoveryRecord> organisations,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>>
    availabilityPosts,
    required List<ServiceCatalogItem> servicePosts,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> businesses,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>>
    communityHelpPosts,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> serviceRequests,
  }) {
    final items = <_FeedItem>[];
    final groupedOrganisationActivities = <String, List<_LinkedActivity>>{};
    final now = DateTime.now();

    for (final doc in opportunities) {
      final data = doc.data() as Map<String, dynamic>;

      if (!LocalDiscoveryFilters.isActivityDiscoverable(data, now: now)) {
        continue;
      }

      final distance = _distance(data);
      if (distance == null) continue;

      final organisationId = safeText(data['organisationId'], '');
      if (organisationId.isNotEmpty) {
        groupedOrganisationActivities
            .putIfAbsent(organisationId, () => [])
            .add(_LinkedActivity(id: doc.id, data: data, distance: distance));
      }

      if (!_matchesActivityFilters(data)) continue;

      items.add(
        _FeedItem(
          id: doc.id,
          kind: _FeedItemKind.activity,
          data: data,
          distance: distance,
        ),
      );
    }

    for (final candidate in OrganisationDiscoveryService.nearbyCandidates(
      records: organisations,
      userLatitude: userPosition?.latitude,
      userLongitude: userPosition?.longitude,
      query: searchText,
      category: selectedCategory,
      activityType: selectedActivityType,
      radiusMiles: HomeBusinessDiscoveryPolicy.maximumRadiusMiles,
    )) {
      final record = candidate.record;
      final data = record.data;
      final activities =
          groupedOrganisationActivities[record.id] ?? const <_LinkedActivity>[];
      items.add(
        _FeedItem(
          id: record.id,
          organisationId: record.id,
          kind: _FeedItemKind.organisation,
          data: {
            ...data,
            'organisationName': data['name'],
            'organisationCategory': data['category'],
            'organisationSubcategories': data['subcategories'],
          },
          distance: candidate.distanceMiles * 1609.344,
          organisationActivities: _sortLinkedActivitiesForDisplay(activities),
        ),
      );
    }

    final discoverableBusinessData = <String, Map<String, dynamic>>{
      for (final business in businesses)
        if (BusinessDiscoveryService.isHomeAvailabilityParentDiscoverable(
          business.data(),
        ))
          business.id: business.data(),
    };

    final groupedAvailability =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    final availabilityBusinessData = <String, Map<String, dynamic>>{};

    for (final doc in availabilityPosts) {
      final data = doc.data();

      if (!LocalDiscoveryFilters.isAvailabilityDiscoverable(data, now: now)) {
        continue;
      }

      final businessId = data['businessId']?.toString().trim() ?? '';
      if (businessId.isEmpty) continue;

      final businessData = discoverableBusinessData[businessId];
      if (businessData == null) continue;

      final filterData = {...businessData, ...data};
      if (!_matchesText(filterData)) continue;
      if (!LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
        filterData,
        selectedCategory: selectedCategory,
        selectedActivityType: selectedActivityType,
      )) {
        continue;
      }

      groupedAvailability.putIfAbsent(businessId, () => []).add(doc);
      availabilityBusinessData[businessId] = businessData;
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
          distance: _distance(availabilityBusinessData[businessId] ?? const {}),
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
      final businessMatchesCategory =
          LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
            businessData,
            selectedCategory: selectedCategory,
            selectedActivityType: selectedActivityType,
          );
      final categoryFilteredServices = services.where((service) {
        return businessMatchesCategory ||
            LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
              service.serviceData,
              selectedCategory: selectedCategory,
              selectedActivityType: selectedActivityType,
              extraValues: [
                businessData['businessName'],
                businessData['category'],
              ],
            );
      }).toList();

      if (categoryFilteredServices.isEmpty) return;

      final groupMatches =
          ServiceCatalogDiscoveryService.businessServiceGroupMatches(
            businessData: businessData,
            services: categoryFilteredServices,
            query: searchText,
          );

      if (!groupMatches) return;

      final sortedServices =
          ServiceCatalogDiscoveryService.sortServicesForSearch(
            services: categoryFilteredServices,
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

    final businessesAlreadyRepresented = <String>{
      ...groupedAvailability.keys,
      ...groupedServices.keys,
    };

    for (final doc in businesses) {
      if (businessesAlreadyRepresented.contains(doc.id)) continue;

      final data = doc.data();
      final distance = _distance(data);
      final distanceMiles = _distanceMiles(data);
      if (!LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
        data,
        selectedCategory: selectedCategory,
        selectedActivityType: selectedActivityType,
      )) {
        continue;
      }
      if (!BusinessDiscoveryService.shouldShowStandaloneBusiness(
        businessId: doc.id,
        data: data,
        representedBusinessIds: businessesAlreadyRepresented,
        searchText: searchText,
        distanceMiles: distanceMiles,
      )) {
        continue;
      }

      items.add(
        _FeedItem(
          id: doc.id,
          businessId: doc.id,
          kind: _FeedItemKind.standaloneBusiness,
          data: data,
          distance: distance,
        ),
      );
    }

    for (final doc in serviceRequests) {
      final data = doc.data();
      if (!LocalDiscoveryFilters.isServiceRequestDiscoverable(data, now: now)) {
        continue;
      }
      final distance = _distance(data);
      if (distance == null) continue;
      if (!LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
        data,
        selectedCategory: selectedCategory,
        selectedActivityType: selectedActivityType,
      )) {
        continue;
      }
      if (!_matchesText(data)) continue;

      items.add(
        _FeedItem(
          id: doc.id,
          kind: _FeedItemKind.serviceRequest,
          data: data,
          distance: distance,
        ),
      );
    }

    for (final doc in communityHelpPosts) {
      final data = doc.data();

      if (!LocalDiscoveryFilters.isCommunityHelpDiscoverable(data, now: now)) {
        continue;
      }
      if (!LocalDiscoveryFilters.isCommunityHelpGeographicallyEligible(
        data,
        userLatitude: userPosition?.latitude,
        userLongitude: userPosition?.longitude,
      )) {
        continue;
      }
      if (!_matchesText(data) || !_matchesCommunityHelpCategory(data)) continue;
      if (!LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
        data,
        selectedCategory: selectedCategory,
        selectedActivityType: selectedActivityType,
      )) {
        continue;
      }

      items.add(
        _FeedItem(
          id: doc.id,
          kind: _FeedItemKind.communityHelp,
          data: data,
          distance: _distance(data),
        ),
      );
    }

    return _applyHomeRadius(items);
  }

  List<_FeedItem> _applyHomeRadius(List<_FeedItem> items) {
    final candidates = HomeFeedRules.applyProgressiveRadius(
      items.map(
        (item) => HomeFeedCandidate<_FeedItem>(
          item: item,
          type: _homeFeedContentType(item),
          distanceMiles: _distanceMilesFromMeters(item.distance),
        ),
      ),
    );

    final filtered = candidates.where(
      (candidate) => HomeFeedRules.categoryAllowsType(
        _selectedHomeCategory,
        candidate.type,
      ),
    );

    final ordered = HomeFeedRules.mix(filtered);

    return ordered.map((candidate) => candidate.item).toList();
  }

  void _selectHomeCategory(HomeDiscoveryCategory category) {
    setState(() {
      _selectedHomeCategory = category;
      selectedCategory = 'All';
      selectedActivityType = 'All';
    });
    widget.onCategorySelected?.call(category);
  }

  HomeFeedContentType _homeFeedContentType(_FeedItem item) {
    return switch (item.kind) {
      _FeedItemKind.communityHelp => HomeFeedContentType.communityHelp,
      _FeedItemKind.serviceRequest => HomeFeedContentType.serviceRequest,
      _FeedItemKind.activity => HomeFeedContentType.activity,
      _FeedItemKind.organisation => HomeFeedContentType.organisation,
      _FeedItemKind.businessAvailability => HomeFeedContentType.availability,
      _FeedItemKind.serviceBusiness => HomeFeedContentType.serviceBusiness,
      _FeedItemKind.standaloneBusiness =>
        HomeFeedContentType.standaloneBusiness,
    };
  }

  List<_LinkedActivity> _sortLinkedActivitiesForDisplay(
    List<_LinkedActivity> activities,
  ) {
    final matching = <_LinkedActivity>[];
    final other = <_LinkedActivity>[];

    for (final activity in activities) {
      final isMatch =
          LocalDiscoveryFilters.matchesActivityCategory(
            activity.data,
            selectedCategory,
          ) &&
          LocalDiscoveryFilters.matchesActivityType(
            activity.data,
            selectedActivityType,
          ) &&
          LocalDiscoveryFilters.matchesText(activity.data, searchText);
      (isMatch ? matching : other).add(activity);
    }

    int compare(_LinkedActivity a, _LinkedActivity b) {
      final aDate = a.data['eventDate'];
      final bDate = b.data['eventDate'];
      if (aDate is Timestamp && bDate is Timestamp) {
        return aDate.compareTo(bDate);
      }
      if (aDate is Timestamp) return -1;
      if (bDate is Timestamp) return 1;
      return safeText(
        a.data['title'],
        '',
      ).compareTo(safeText(b.data['title'], ''));
    }

    matching.sort(compare);
    other.sort(compare);
    return [...matching, ...other];
  }

  double? _distance(Map<String, dynamic> data) {
    final miles = _distanceMiles(data);
    return miles == null ? null : miles * 1609.344;
  }

  double? _distanceMiles(Map<String, dynamic> data) {
    final position = userPosition;
    if (position == null ||
        !HomeBusinessDiscoveryPolicy.hasValidCoordinates(
          position.latitude,
          position.longitude,
        )) {
      return null;
    }

    final lat =
        _validCoordinate(data['latitude'], isLatitude: true) ??
        _validCoordinate(data['approxLatitude'], isLatitude: true);
    final lng =
        _validCoordinate(data['longitude'], isLatitude: false) ??
        _validCoordinate(data['approxLongitude'], isLatitude: false);

    final distanceMiles = HomeBusinessDiscoveryPolicy.distanceMilesBetween(
      startLatitude: position.latitude,
      startLongitude: position.longitude,
      endLatitude: lat,
      endLongitude: lng,
    );
    return distanceMiles;
  }

  double? _distanceMilesFromMeters(double? distance) {
    if (distance == null) return null;
    return distance / 1609.344;
  }

  double? _validCoordinate(Object? value, {required bool isLatitude}) {
    final coordinate = double.tryParse(value?.toString() ?? '');
    if (coordinate == null || !coordinate.isFinite) return null;
    if (isLatitude && (coordinate < -90 || coordinate > 90)) return null;
    if (!isLatitude && (coordinate < -180 || coordinate > 180)) return null;
    return coordinate;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LocalLinkSectionHeader(
          title: 'Explore your community',
          trailing: _LiveNowPill(),
        ),
        const SizedBox(height: LocalLinkSpacing.md),
        HomeDiscoveryCategoryTabs(
          selectedCategory: _selectedHomeCategory,
          onSelected: _selectHomeCategory,
        ),
        if (widget.contextualActionsBuilder case final builder?) ...[
          const SizedBox(height: LocalLinkSpacing.sm),
          builder(context, _selectedHomeCategory),
        ],
        if (!widget.showContent)
          const SizedBox.shrink()
        else ...[
          const SizedBox(height: LocalLinkSpacing.sm),
          OpportunitySearch(
            onChanged: (value) {
              setState(() {
                searchText = value.trim().toLowerCase();
              });
            },
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('opportunities')
                .where('discoveryVisibility', isEqualTo: 'public')
                .where('isActive', isEqualTo: true)
                .snapshots(),
            builder: (context, opportunitySnapshot) {
              if (opportunitySnapshot.hasError) {
                _logQueryError(
                  'opportunities query',
                  opportunitySnapshot.error,
                );
                return const _FeedMessage(
                  icon: Icons.error_outline_rounded,
                  title: 'Unable to load activities',
                  message: 'Please try again in a moment.',
                );
              }

              if (!opportunitySnapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: LocalLinkSpacing.xxl),
                  child: LocalLinkLoadingState(label: 'Loading local activity'),
                );
              }

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('availabilityPosts')
                    .where('isActive', isEqualTo: true)
                    .snapshots(),
                builder: (context, availabilitySnapshot) {
                  if (availabilitySnapshot.hasError &&
                      _selectedHomeCategory ==
                          HomeDiscoveryCategory.businesses) {
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
                      padding: EdgeInsets.symmetric(
                        vertical: LocalLinkSpacing.xxl,
                      ),
                      child: LocalLinkLoadingState(label: 'Loading services'),
                    );
                  }

                  return StreamBuilder<List<ServiceCatalogItem>>(
                    stream:
                        ServiceCatalogDiscoveryService.watchDiscoverableServices(),
                    builder: (context, serviceSnapshot) {
                      if (serviceSnapshot.hasError &&
                          _selectedHomeCategory ==
                              HomeDiscoveryCategory.businesses) {
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
                          _selectedHomeCategory ==
                              HomeDiscoveryCategory.businesses) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: LocalLinkSpacing.xxl,
                          ),
                          child: LocalLinkLoadingState(
                            label: 'Loading services',
                          ),
                        );
                      }

                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('businesses')
                            .where('isActive', isEqualTo: true)
                            .snapshots(),
                        builder: (context, businessSnapshot) {
                          if (businessSnapshot.hasError &&
                              _selectedHomeCategory ==
                                  HomeDiscoveryCategory.businesses) {
                            _logQueryError(
                              'standalone businesses query',
                              businessSnapshot.error,
                            );
                          }

                          if (!businessSnapshot.hasData &&
                              !businessSnapshot.hasError &&
                              _selectedHomeCategory ==
                                  HomeDiscoveryCategory.businesses) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: LocalLinkSpacing.xxl,
                              ),
                              child: LocalLinkLoadingState(
                                label: 'Loading businesses',
                              ),
                            );
                          }

                          return StreamBuilder<
                            List<OrganisationDiscoveryRecord>
                          >(
                            stream:
                                OrganisationDiscoveryService.watchActiveOrganisations(),
                            builder: (context, organisationSnapshot) {
                              if (organisationSnapshot.hasError) {
                                _logQueryError(
                                  'organisations query',
                                  organisationSnapshot.error,
                                );
                                if (_selectedHomeCategory ==
                                    HomeDiscoveryCategory.organisations) {
                                  return const _FeedMessage(
                                    icon: Icons.error_outline_rounded,
                                    title: 'Unable to load organisations',
                                    message: 'Please try again in a moment.',
                                  );
                                }
                              }
                              if (!organisationSnapshot.hasData &&
                                  !organisationSnapshot.hasError &&
                                  _selectedHomeCategory ==
                                      HomeDiscoveryCategory.organisations) {
                                return const LocalLinkLoadingState(
                                  label: 'Loading organisations',
                                );
                              }
                              return StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>
                              >(
                                stream: FirebaseFirestore.instance
                                    .collection('communityHelpPosts')
                                    .where('isActive', isEqualTo: true)
                                    .snapshots(),
                                builder: (context, communityHelpSnapshot) {
                                  if (communityHelpSnapshot.hasError &&
                                      _selectedHomeCategory ==
                                          HomeDiscoveryCategory.communityHelp) {
                                    return const _FeedMessage(
                                      icon: Icons.error_outline_rounded,
                                      title: 'Unable to load Community Help',
                                      message: 'Please try again in a moment.',
                                    );
                                  }

                                  if (!communityHelpSnapshot.hasData &&
                                      !communityHelpSnapshot.hasError &&
                                      _selectedHomeCategory ==
                                          HomeDiscoveryCategory.communityHelp) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: LocalLinkSpacing.xxl,
                                      ),
                                      child: LocalLinkLoadingState(
                                        label: 'Loading Community Help',
                                      ),
                                    );
                                  }

                                  return StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>
                                  >(
                                    stream: FirebaseFirestore.instance
                                        .collection('serviceRequests')
                                        .where('isActive', isEqualTo: true)
                                        .snapshots(),
                                    builder: (context, serviceRequestSnapshot) {
                                      if (serviceRequestSnapshot.hasError &&
                                          _selectedHomeCategory ==
                                              HomeDiscoveryCategory.services) {
                                        _logQueryError(
                                          'serviceRequests query',
                                          serviceRequestSnapshot.error,
                                        );
                                      }

                                      final items = _buildItems(
                                        organisations:
                                            organisationSnapshot.hasError
                                            ? const []
                                            : organisationSnapshot.data ??
                                                  const [],
                                        opportunities:
                                            opportunitySnapshot.data!.docs,
                                        availabilityPosts:
                                            availabilitySnapshot.hasError
                                            ? const []
                                            : availabilitySnapshot.data?.docs ??
                                                  const [],
                                        servicePosts: serviceSnapshot.hasError
                                            ? const []
                                            : serviceSnapshot.data ?? const [],
                                        businesses: businessSnapshot.hasError
                                            ? const []
                                            : businessSnapshot.data?.docs ??
                                                  const [],
                                        communityHelpPosts:
                                            communityHelpSnapshot.hasError
                                            ? const []
                                            : communityHelpSnapshot
                                                      .data
                                                      ?.docs ??
                                                  const [],
                                        serviceRequests:
                                            serviceRequestSnapshot.hasError
                                            ? const []
                                            : serviceRequestSnapshot
                                                      .data
                                                      ?.docs ??
                                                  const [],
                                      );

                                      if (_locationLookupState ==
                                          _LocationLookupState.loading) {
                                        return const _FeedMessage(
                                          icon: Icons.my_location_outlined,
                                          title:
                                              'Finding nearby LocalLink posts',
                                          message:
                                              'LocalLink is checking your location so Home stays local.',
                                        );
                                      }

                                      if (_locationLookupState ==
                                          _LocationLookupState.unavailable) {
                                        return _FeedMessage(
                                          icon: Icons.location_off_outlined,
                                          title:
                                              'Location needed for nearby posts',
                                          message:
                                              'Turn on location access or try again to see local activities, services and help.',
                                          actionLabel: 'Try again',
                                          onAction: _retryLocationLookup,
                                        );
                                      }

                                      if (items.isEmpty) {
                                        return HomeDiscoveryCategorySwipeRegion(
                                          selectedCategory:
                                              _selectedHomeCategory,
                                          onSelected: _selectHomeCategory,
                                          child: _FeedMessage(
                                            icon: Icons.search_off_rounded,
                                            title: HomeFeedRules.emptyTitle(
                                              _selectedHomeCategory,
                                            ),
                                            message: HomeFeedRules.emptyMessage(
                                              _selectedHomeCategory,
                                            ),
                                          ),
                                        );
                                      }

                                      return HomeDiscoveryCategorySwipeRegion(
                                        selectedCategory: _selectedHomeCategory,
                                        onSelected: _selectHomeCategory,
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          switchInCurve: Curves.easeOutCubic,
                                          switchOutCurve: Curves.easeOutCubic,
                                          child: ListView.separated(
                                            key: ValueKey<String>(
                                              'home-feed-${_selectedHomeCategory.name}',
                                            ),
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            padding: const EdgeInsets.only(
                                              bottom: 28,
                                            ),
                                            itemCount: items.length,
                                            separatorBuilder:
                                                (context, index) =>
                                                    const SizedBox(
                                                      height:
                                                          LocalLinkSpacing.sm,
                                                    ),
                                            itemBuilder: (context, index) {
                                              final item = items[index];

                                              if (item.kind ==
                                                  _FeedItemKind.activity) {
                                                return OpportunityCard(
                                                  opportunityId: item.id,
                                                  data: item.data,
                                                  userPosition: userPosition,
                                                );
                                              }

                                              if (item.kind ==
                                                  _FeedItemKind.communityHelp) {
                                                return _CommunityHelpFeedCard(
                                                  postId: item.id,
                                                  data: item.data,
                                                  distance: item.distance,
                                                );
                                              }

                                              if (item.kind ==
                                                  _FeedItemKind
                                                      .serviceRequest) {
                                                return _ServiceRequestFeedCard(
                                                  requestId: item.id,
                                                  data: item.data,
                                                  distance: item.distance,
                                                );
                                              }

                                              if (item.kind ==
                                                  _FeedItemKind.organisation) {
                                                return _OrganisationFeedCard(
                                                  organisationId:
                                                      item.organisationId ??
                                                      item.id,
                                                  data: item.data,
                                                  activities: item
                                                      .organisationActivities,
                                                  distance: item.distance,
                                                );
                                              }

                                              if (item.kind ==
                                                  _FeedItemKind
                                                      .serviceBusiness) {
                                                return _ServiceBusinessFeedCard(
                                                  businessId:
                                                      item.businessId ??
                                                      item.id,
                                                  businessData: item.data,
                                                  services: item.services,
                                                  distance: item.distance,
                                                );
                                              }

                                              if (item.kind ==
                                                  _FeedItemKind
                                                      .standaloneBusiness) {
                                                return _StandaloneBusinessFeedCard(
                                                  businessId:
                                                      item.businessId ??
                                                      item.id,
                                                  businessData: item.data,
                                                  distance: item.distance,
                                                );
                                              }

                                              return MarketplaceBusinessCard(
                                                businessId:
                                                    item.businessId ?? item.id,
                                                availabilityPosts:
                                                    item.availabilityPosts,
                                                userPosition: userPosition,
                                              );
                                            },
                                          ),
                                        ),
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
                  );
                },
              );
            },
          ),
        ],
      ],
    );
  }
}

enum _FeedItemKind {
  activity,
  organisation,
  businessAvailability,
  serviceBusiness,
  standaloneBusiness,
  serviceRequest,
  communityHelp,
}

class _LiveNowPill extends StatelessWidget {
  const _LiveNowPill();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Live now',
      child: Row(
        key: const ValueKey('home-live-now-status'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 15, color: AppColors.primary),
          const SizedBox(width: LocalLinkSpacing.xxs),
          Text('Live now', style: LocalLinkTextStyles.metadata),
        ],
      ),
    );
  }
}

class HomeDiscoveryCategoryTabs extends StatefulWidget {
  const HomeDiscoveryCategoryTabs({
    super.key,
    required this.selectedCategory,
    required this.onSelected,
  });

  final HomeDiscoveryCategory selectedCategory;
  final ValueChanged<HomeDiscoveryCategory> onSelected;

  @override
  State<HomeDiscoveryCategoryTabs> createState() =>
      _HomeDiscoveryCategoryTabsState();
}

class _HomeDiscoveryCategoryTabsState extends State<HomeDiscoveryCategoryTabs> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _viewportKey = GlobalKey();
  final Map<HomeDiscoveryCategory, GlobalKey> _categoryKeys = {
    for (final category in HomeFeedRules.categories) category: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _scheduleSelectedCategoryVisibility();
  }

  @override
  void didUpdateWidget(HomeDiscoveryCategoryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCategory != widget.selectedCategory) {
      _scheduleSelectedCategoryVisibility();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleSelectedCategoryVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final itemContext =
          _categoryKeys[widget.selectedCategory]?.currentContext;
      final viewportContext = _viewportKey.currentContext;
      final itemBox = itemContext?.findRenderObject() as RenderBox?;
      final viewportBox = viewportContext?.findRenderObject() as RenderBox?;
      if (itemBox == null || viewportBox == null) return;

      final itemLeft = itemBox.localToGlobal(Offset.zero).dx;
      final viewportLeft = viewportBox.localToGlobal(Offset.zero).dx;
      final relativeLeft = itemLeft - viewportLeft;
      final target =
          (_scrollController.offset +
                  relativeLeft -
                  (viewportBox.size.width - itemBox.size.width) / 2)
              .clamp(
                _scrollController.position.minScrollExtent,
                _scrollController.position.maxScrollExtent,
              )
              .toDouble();

      if ((target - _scrollController.offset).abs() < 1) return;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('home-category-scroll'),
      child: SingleChildScrollView(
        key: _viewportKey,
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final category in HomeFeedRules.categories) ...[
              Column(
                key: _categoryKeys[category],
                mainAxisSize: MainAxisSize.min,
                children: [
                  LocalLinkChip(
                    key: ValueKey('home-category-${category.name}'),
                    label: category.label,
                    selected: category == widget.selectedCategory,
                    accentColor: homeDiscoveryCategoryAccent(category),
                    onSelected: (_) => widget.onSelected(category),
                  ),
                  const SizedBox(height: LocalLinkSpacing.xxs),
                  AnimatedContainer(
                    key: ValueKey('home-category-indicator-${category.name}'),
                    duration: LocalLinkMotion.quick,
                    curve: LocalLinkMotion.curve,
                    width: category == widget.selectedCategory ? 24 : 0,
                    height: 2,
                    decoration: BoxDecoration(
                      color: homeDiscoveryCategoryAccent(category),
                      borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
                    ),
                  ),
                ],
              ),
              if (category != HomeFeedRules.categories.last)
                const SizedBox(width: LocalLinkSpacing.xs),
            ],
          ],
        ),
      ),
    );
  }
}

Color homeDiscoveryCategoryAccent(HomeDiscoveryCategory category) {
  return switch (category) {
    HomeDiscoveryCategory.nearby => AppColors.primary,
    HomeDiscoveryCategory.services => AppColors.serviceGreen,
    HomeDiscoveryCategory.activities => AppColors.activityBlue,
    HomeDiscoveryCategory.communityHelp => AppColors.communityTeal,
    HomeDiscoveryCategory.businesses => AppColors.serviceGreen,
    HomeDiscoveryCategory.organisations => AppColors.activityBlue,
  };
}

class HomeDiscoveryCategorySwipeRegion extends StatelessWidget {
  const HomeDiscoveryCategorySwipeRegion({
    super.key,
    required this.selectedCategory,
    required this.onSelected,
    required this.child,
  });

  final HomeDiscoveryCategory selectedCategory;
  final ValueChanged<HomeDiscoveryCategory> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: _handleHorizontalSwipe,
      child: child,
    );
  }

  void _handleHorizontalSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 180) return;

    final categories = HomeFeedRules.categories;
    final index = categories.indexOf(selectedCategory);
    final nextIndex = velocity < 0 ? index + 1 : index - 1;
    if (nextIndex < 0 || nextIndex >= categories.length) return;
    onSelected(categories[nextIndex]);
  }
}

class _LinkedActivity {
  const _LinkedActivity({
    required this.id,
    required this.data,
    required this.distance,
  });

  final String id;
  final Map<String, dynamic> data;
  final double distance;
}

class _FeedItem {
  final String id;
  final String? businessId;
  final String? organisationId;
  final _FeedItemKind kind;
  final Map<String, dynamic> data;
  final double? distance;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> availabilityPosts;
  final List<ServiceCatalogItem> services;
  final List<_LinkedActivity> organisationActivities;

  const _FeedItem({
    required this.id,
    this.businessId,
    this.organisationId,
    required this.kind,
    required this.data,
    required this.distance,
    this.availabilityPosts = const [],
    this.services = const [],
    this.organisationActivities = const [],
  });
}

class _OrganisationFeedCard extends StatelessWidget {
  const _OrganisationFeedCard({
    required this.organisationId,
    required this.data,
    required this.activities,
    required this.distance,
  });

  final String organisationId;
  final Map<String, dynamic> data;
  final List<_LinkedActivity> activities;
  final double? distance;

  @override
  Widget build(BuildContext context) {
    final name = safeText(data['organisationName'] ?? data['name'], 'Group');
    final category = safeText(data['organisationCategory'], 'Activity');
    final location = safeText(data['publicLocation'], '');
    final imageUrl = safeText(data['imageUrl'], '');
    final tags = _stringList(data['organisationSubcategories']).take(2);
    final visibleActivities = activities.take(2).toList();
    final next = activities.isEmpty ? null : activities.first.data;
    final nextTitle = safeText(next?['title'], '');
    final nextWhen = _activityWhen(next ?? const {});
    final distanceText = _distanceLabel(distance);

    return LocalLinkSurfaceCard(
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      radius: LocalLinkRadius.lg,
      elevated: false,
      onTap: () => _openOrganisation(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OrganisationLogo(imageUrl: imageUrl),
              const SizedBox(width: LocalLinkSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.charcoal,
                              fontSize: 18,
                              height: 1.14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: LocalLinkSpacing.xs),
                        _OrganisationBadge(count: activities.length),
                      ],
                    ),
                    const SizedBox(height: LocalLinkSpacing.xs),
                    Wrap(
                      spacing: LocalLinkSpacing.xs,
                      runSpacing: LocalLinkSpacing.xs,
                      children: [
                        _ServiceBusinessMeta(
                          icon: Icons.groups_2_outlined,
                          label: category,
                        ),
                        for (final tag in tags)
                          _ServiceBusinessMeta(
                            icon: Icons.sell_outlined,
                            label: tag,
                          ),
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
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (nextTitle.isNotEmpty) ...[
            const SizedBox(height: LocalLinkSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(LocalLinkSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.activityBlue.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(LocalLinkRadius.md),
                border: Border.all(
                  color: AppColors.activityBlue.withValues(alpha: 0.10),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.schedule_outlined,
                    color: AppColors.activityBlue,
                    size: 18,
                  ),
                  const SizedBox(width: LocalLinkSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next',
                          style: LocalLinkTextStyles.status.copyWith(
                            color: AppColors.activityBlue,
                          ),
                        ),
                        const SizedBox(height: LocalLinkSpacing.xxs),
                        Text(
                          [
                            nextTitle,
                            if (nextWhen.isNotEmpty) nextWhen,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: LocalLinkTextStyles.bodyStrong,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (visibleActivities.length > 1) ...[
            const SizedBox(height: LocalLinkSpacing.sm),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: visibleActivities.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: LocalLinkSpacing.xs),
                itemBuilder: (context, index) {
                  final activity = visibleActivities[index];
                  return _CompactActivityTile(
                    activityId: activity.id,
                    data: activity.data,
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: LocalLinkSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _openOrganisation(context),
              icon: const Icon(Icons.arrow_forward_rounded, size: 17),
              label: Text(
                activities.isEmpty ? 'View organisation' : 'View activities',
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.activityBlue,
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: LocalLinkTextStyles.button,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openOrganisation(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OrganisationDetailScreen(organisationId: organisationId),
      ),
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! Iterable) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static String _activityWhen(Map<String, dynamic> data) {
    final schedule = safeText(data['scheduleText'], '');
    if (schedule.isNotEmpty) return schedule;

    final repeatType = safeText(data['repeatType'], '');
    final eventTime = safeText(data['eventTime'], '');
    final repeatLabel = switch (repeatType) {
      'daily' => 'Daily',
      'weekly' => 'Weekly',
      'fortnightly' => 'Fortnightly',
      'monthly' => 'Monthly',
      _ => '',
    };

    return [
      if (repeatLabel.isNotEmpty) repeatLabel,
      if (eventTime.isNotEmpty) eventTime,
    ].join(' · ');
  }
}

class _OrganisationLogo extends StatelessWidget {
  const _OrganisationLogo({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 68,
      child: LocalLinkImage(
        imageUrl: imageUrl,
        fallbackIcon: Icons.groups_2_outlined,
        accentColor: AppColors.activityBlue,
        semanticLabel: 'Organisation image',
      ),
    );
  }
}

class _OrganisationBadge extends StatelessWidget {
  const _OrganisationBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 activity' : '$count activities';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.sm,
        vertical: LocalLinkSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.activityBlue.withValues(alpha: 0.11),
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

class _CompactActivityTile extends StatelessWidget {
  const _CompactActivityTile({required this.activityId, required this.data});

  final String activityId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final title = safeText(data['title'], 'Activity');
    final when = _OrganisationFeedCard._activityWhen(data);

    return InkWell(
      borderRadius: BorderRadius.circular(LocalLinkRadius.md),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OpportunityDetailScreen(
              opportunityId: activityId,
              opportunity: data,
            ),
          ),
        );
      },
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(LocalLinkSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.activityBlue.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(LocalLinkRadius.md),
          border: Border.all(
            color: AppColors.activityBlue.withValues(alpha: 0.10),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Activity',
              style: LocalLinkTextStyles.status.copyWith(
                color: AppColors.activityBlue,
              ),
            ),
            const SizedBox(height: LocalLinkSpacing.xxs),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: LocalLinkTextStyles.label,
            ),
            const Spacer(),
            if (when.isNotEmpty)
              Text(
                when,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LocalLinkTextStyles.status.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
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
  final double? distance;

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
    final distanceText = _distanceLabel(distance);
    final coverImageUrl = businessCoverImageUrl(businessData);
    final hasCoverImage = coverImageUrl.isNotEmpty;

    return LocalLinkSurfaceCard(
      padding: EdgeInsets.zero,
      radius: LocalLinkRadius.lg,
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasCoverImage)
            _BusinessCoverImage(
              imageUrl: coverImageUrl,
              semanticLabel: businessName,
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              LocalLinkSpacing.md,
              hasCoverImage ? LocalLinkSpacing.sm : LocalLinkSpacing.md,
              LocalLinkSpacing.md,
              LocalLinkSpacing.sm,
            ),
            child: Row(
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
                        style: LocalLinkTextStyles.cardTitle.copyWith(
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: LocalLinkSpacing.xs),
                      Wrap(
                        spacing: LocalLinkSpacing.sm,
                        runSpacing: LocalLinkSpacing.xs,
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
                    textStyle: LocalLinkTextStyles.button,
                  ),
                  child: const Text('View business'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LocalLinkSpacing.md,
              0,
              LocalLinkSpacing.md,
              LocalLinkSpacing.md,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = services.length == 1
                    ? constraints.maxWidth
                    : constraints.maxWidth.clamp(210.0, 224.0);

                return SizedBox(
                  height: 164,
                  child: ListView.separated(
                    key: PageStorageKey<String>('service-row-$businessId'),
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: services.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: LocalLinkSpacing.sm),
                    itemBuilder: (context, index) {
                      final service = services[index];
                      return _CompactServiceTile(
                        businessId: businessId,
                        serviceId: service.serviceId,
                        serviceData: service.serviceData,
                        width: tileWidth,
                      );
                    },
                  ),
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

class _BusinessCoverImage extends StatelessWidget {
  const _BusinessCoverImage({
    required this.imageUrl,
    required this.semanticLabel,
  });

  final String imageUrl;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      width: double.infinity,
      child: LocalLinkImage(
        imageUrl: imageUrl,
        aspectRatio: 16 / 9,
        fallbackIcon: Icons.storefront_outlined,
        accentColor: AppColors.serviceGreen,
        semanticLabel: semanticLabel,
      ),
    );
  }
}

class _StandaloneBusinessFeedCard extends StatelessWidget {
  const _StandaloneBusinessFeedCard({
    required this.businessId,
    required this.businessData,
    required this.distance,
  });

  final String businessId;
  final Map<String, dynamic> businessData;
  final double? distance;

  @override
  Widget build(BuildContext context) {
    final businessName = safeText(
      businessData['businessName'] ?? businessData['name'],
      'Local business',
    );
    final category = safeText(businessData['category'], 'Business');
    final isUnclaimed =
        BusinessDiscoveryService.isStandaloneSeededUnclaimedBusiness(
          businessData,
        );
    final location = safeText(
      businessData['publicLocation'] ??
          businessData['area'] ??
          businessData['serviceArea'] ??
          businessData['location'] ??
          businessData['address'],
      '',
    );
    final distanceText = _distanceLabel(distance);
    final coverImageUrl = businessCoverImageUrl(businessData);
    final hasCoverImage = coverImageUrl.isNotEmpty;

    return LocalLinkSurfaceCard(
      padding: EdgeInsets.zero,
      radius: LocalLinkRadius.lg,
      elevated: false,
      onTap: () => _openBusiness(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasCoverImage)
            _BusinessCoverImage(
              imageUrl: coverImageUrl,
              semanticLabel: businessName,
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              LocalLinkSpacing.md,
              hasCoverImage ? LocalLinkSpacing.sm : LocalLinkSpacing.md,
              LocalLinkSpacing.md,
              LocalLinkSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.serviceGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(LocalLinkRadius.md),
                    border: Border.all(
                      color: AppColors.serviceGreen.withValues(alpha: 0.12),
                    ),
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    color: AppColors.serviceGreen,
                  ),
                ),
                const SizedBox(width: LocalLinkSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          LocalLinkChip(
                            label: isUnclaimed ? 'Unclaimed' : 'Local business',
                            selected: true,
                            accentColor: AppColors.primary,
                          ),
                          Text(category, style: LocalLinkTextStyles.metadata),
                        ],
                      ),
                      const SizedBox(height: LocalLinkSpacing.xs),
                      Text(
                        businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LocalLinkTextStyles.cardTitle.copyWith(
                          fontSize: 18,
                        ),
                      ),
                      if (location.isNotEmpty || distanceText.isNotEmpty) ...[
                        const SizedBox(height: LocalLinkSpacing.xs),
                        Wrap(
                          spacing: LocalLinkSpacing.sm,
                          runSpacing: LocalLinkSpacing.xs,
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
                          ],
                        ),
                      ],
                      const SizedBox(height: LocalLinkSpacing.xs),
                      TextButton.icon(
                        onPressed: () => _openBusiness(context),
                        icon: const Icon(Icons.open_in_new_rounded, size: 17),
                        label: const Text('View business'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.serviceGreen,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: LocalLinkTextStyles.button,
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
    required this.width,
  });

  final String businessId;
  final String serviceId;
  final Map<String, dynamic> serviceData;
  final double width;

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
      width: width,
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
        radius: LocalLinkRadius.md,
        elevated: false,
        color: AppColors.elevatedSurface,
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
                    borderRadius: BorderRadius.circular(LocalLinkRadius.sm),
                  ),
                  child: const Icon(
                    Icons.handyman_outlined,
                    color: AppColors.serviceGreen,
                    size: 19,
                  ),
                ),
                const SizedBox(width: LocalLinkSpacing.xs),
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
            const SizedBox(height: LocalLinkSpacing.xs),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: LocalLinkTextStyles.bodyStrong,
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: LocalLinkSpacing.xxs),
              Text(
                details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LocalLinkTextStyles.metadata,
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

class _ServiceRequestFeedCard extends StatelessWidget {
  const _ServiceRequestFeedCard({
    required this.requestId,
    required this.data,
    required this.distance,
  });

  final String requestId;
  final Map<String, dynamic> data;
  final double? distance;

  @override
  Widget build(BuildContext context) {
    final category = safeText(data['category'], 'help');
    final title = safeText(
      data['title'],
      'Someone nearby is looking for ${category.toLowerCase()}',
    );
    final schedule = safeText(data['scheduleText'], '');
    final location = ServiceRequestMarketplace.publicLocation(data);
    final distanceText = _distanceLabel(distance);
    final imageUrls = ServiceRequestMarketplace.imageUrls(data);
    final hasImage = imageUrls.isNotEmpty;

    return LocalLinkSurfaceCard(
      padding: EdgeInsets.zero,
      radius: LocalLinkRadius.lg,
      elevated: false,
      onTap: () => _openRequest(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasImage)
            SizedBox(
              height: 112,
              width: double.infinity,
              child: LocalLinkImage(
                imageUrl: imageUrls.first,
                aspectRatio: 16 / 9,
                fallbackIcon: Icons.handyman_outlined,
                accentColor: AppColors.serviceGreen,
                semanticLabel: title,
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              LocalLinkSpacing.md,
              hasImage ? LocalLinkSpacing.sm : LocalLinkSpacing.md,
              LocalLinkSpacing.md,
              LocalLinkSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.serviceGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(LocalLinkRadius.md),
                  ),
                  child: const Icon(
                    Icons.campaign_outlined,
                    color: AppColors.serviceGreen,
                  ),
                ),
                const SizedBox(width: LocalLinkSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalLinkChip(
                        label: 'Looking for help',
                        selected: true,
                        accentColor: AppColors.serviceGreen,
                      ),
                      const SizedBox(height: LocalLinkSpacing.xs),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: LocalLinkTextStyles.cardTitle.copyWith(
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: LocalLinkSpacing.xs),
                      Wrap(
                        spacing: LocalLinkSpacing.sm,
                        runSpacing: LocalLinkSpacing.xs,
                        children: [
                          _ServiceBusinessMeta(
                            icon: Icons.handyman_outlined,
                            label: category,
                          ),
                          if (distanceText.isNotEmpty)
                            _ServiceBusinessMeta(
                              icon: Icons.near_me_outlined,
                              label: distanceText,
                            ),
                          if (schedule.isNotEmpty)
                            _ServiceBusinessMeta(
                              icon: Icons.schedule_outlined,
                              label: schedule,
                            ),
                          if (location.isNotEmpty)
                            _ServiceBusinessMeta(
                              icon: Icons.place_outlined,
                              label: location,
                            ),
                        ],
                      ),
                      const SizedBox(height: LocalLinkSpacing.xs),
                      TextButton.icon(
                        onPressed: () => _openRequest(context),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                        label: const Text('View request'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.serviceGreen,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: LocalLinkTextStyles.button,
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
  }

  void _openRequest(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CustomerServiceRequestDetailScreen(requestId: requestId),
      ),
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
  final double? distance;

  @override
  Widget build(BuildContext context) {
    final type = data['type']?.toString() ?? 'lost_found';
    final mode = data['mode']?.toString() ?? 'lost';
    final title = data['title']?.toString() ?? 'Community Help post';
    final itemCategory = data['itemCategory']?.toString() ?? 'Item';
    final location = CommunityHelpLocation.publicLabel(data);
    final photoUrl = data['photoUrl']?.toString() ?? '';
    final lookoutCount = (data['lookoutCount'] as num?)?.toInt() ?? 0;
    final eventDateText = CommunityHelpLifecycle.observedAtText(
      data,
      DateTime.now(),
    );
    final isPet = itemCategory.trim().toLowerCase() == 'pet';
    final itemLabel = data['petType']?.toString() ?? itemCategory;
    final isMissingPet = type != 'free_item' && mode == 'lost' && isPet;
    final accent = _communityAccent(mode: mode, type: type);
    final status = type == 'free_item'
        ? 'FREE'
        : mode == 'found'
        ? 'FOUND'
        : 'MISSING';
    final distanceText = _distanceLabel(distance);

    void openPost() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostServiceRequestScreen(initialPostId: postId),
        ),
      );
    }

    if (isMissingPet) {
      return LocalLinkSurfaceCard(
        padding: EdgeInsets.zero,
        radius: LocalLinkRadius.lg,
        elevated: false,
        onTap: openPost,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalLinkImage(
              imageUrl: photoUrl,
              aspectRatio: 16 / 10,
              fallbackIcon: Icons.pets_outlined,
              accentColor: accent,
              semanticLabel: 'Missing pet photo',
            ),
            Padding(
              padding: const EdgeInsets.all(LocalLinkSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: LocalLinkSpacing.xs,
                    runSpacing: LocalLinkSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _HelpStatusPill(label: status),
                      Text(itemLabel, style: LocalLinkTextStyles.metadata),
                    ],
                  ),
                  const SizedBox(height: LocalLinkSpacing.xs),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LocalLinkTextStyles.sectionTitle,
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: LocalLinkSpacing.xs),
                    Text(
                      'Last seen near $location',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LocalLinkTextStyles.bodyStrong,
                    ),
                  ],
                  if (eventDateText.isNotEmpty) ...[
                    const SizedBox(height: LocalLinkSpacing.xxs),
                    Text(
                      eventDateText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LocalLinkTextStyles.metadata,
                    ),
                  ],
                  const SizedBox(height: LocalLinkSpacing.sm),
                  Wrap(
                    spacing: LocalLinkSpacing.sm,
                    runSpacing: LocalLinkSpacing.xs,
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
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return LocalLinkSurfaceCard(
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      radius: LocalLinkRadius.lg,
      elevated: false,
      onTap: openPost,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommunityHelpThumb(
            photoUrl: photoUrl,
            mode: mode,
            type: type,
            itemCategory: itemCategory,
          ),
          const SizedBox(width: LocalLinkSpacing.sm),
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
                    Text(itemLabel, style: LocalLinkTextStyles.metadata),
                  ],
                ),
                const SizedBox(height: LocalLinkSpacing.xs),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LocalLinkTextStyles.cardTitle,
                ),
                const SizedBox(height: LocalLinkSpacing.xxs),
                if (location.isNotEmpty)
                  Text(
                    mode == 'found' ? 'Found near $location' : location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LocalLinkTextStyles.metadata,
                  ),
                const SizedBox(height: LocalLinkSpacing.xs),
                Wrap(
                  spacing: LocalLinkSpacing.sm,
                  runSpacing: LocalLinkSpacing.xs,
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
    );
  }
}

class _CommunityHelpThumb extends StatelessWidget {
  const _CommunityHelpThumb({
    required this.photoUrl,
    required this.mode,
    required this.type,
    required this.itemCategory,
  });

  final String photoUrl;
  final String mode;
  final String type;
  final String itemCategory;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 78,
      child: LocalLinkImage(
        imageUrl: photoUrl,
        fallbackIcon: _communityFallbackIcon(
          mode: mode,
          type: type,
          itemCategory: itemCategory,
        ),
        accentColor: _communityAccent(mode: mode, type: type),
        semanticLabel: 'Community Help image',
      ),
    );
  }
}

class _HelpStatusPill extends StatelessWidget {
  const _HelpStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'MISSING' => AppColors.lost,
      'FOUND' => AppColors.success,
      _ => AppColors.communityTeal,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.xs,
        vertical: LocalLinkSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LocalLinkRadius.xs),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: LocalLinkTextStyles.status.copyWith(color: color),
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
  final String? actionLabel;
  final VoidCallback? onAction;

  const _FeedMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalLinkEmptyState(icon: icon, title: title, message: message),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: LocalLinkSpacing.sm),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
