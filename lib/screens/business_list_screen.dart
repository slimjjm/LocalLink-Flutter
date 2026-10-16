import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../constants/business_categories.dart';
import '../models/business.dart';
import '../services/business_discovery_service.dart';
import '../services/home_business_discovery_policy.dart';
import '../services/local_discovery_filters.dart';
import '../services/location_service.dart';
import '../services/service_catalog_discovery_service.dart';
import '../widgets/business_card.dart';

class BusinessListScreen extends StatefulWidget {
  final String? initialPostcode;
  final String? initialCategory;
  final bool useCurrentLocation;

  const BusinessListScreen({
    super.key,
    this.initialPostcode,
    this.initialCategory,
    this.useCurrentLocation = false,
  });

  @override
  State<BusinessListScreen> createState() => _BusinessListScreenState();
}

class _BusinessListScreenState extends State<BusinessListScreen> {
  final TextEditingController searchController = TextEditingController();
  final TextEditingController postcodeController = TextEditingController();

  Position? userPosition;
  bool locationLoadComplete = false;
  Map<String, List<Map<String, dynamic>>> serviceDataByBusinessId = const {};

  String searchText = '';
  String postcodeText = '';
  String? selectedCategory;

  final List<String> categories = BusinessCategories.values;

  @override
  void initState() {
    super.initState();

    final initialCategory = BusinessCategories.normalise(
      widget.initialCategory,
    );
    selectedCategory = BusinessCategories.isCanonical(initialCategory)
        ? initialCategory
        : widget.initialCategory;

    if (widget.initialPostcode != null &&
        widget.initialPostcode!.trim().isNotEmpty) {
      postcodeText = widget.initialPostcode!.trim();
      postcodeController.text = postcodeText;
    }

    if (widget.useCurrentLocation) {
      loadLocation();
    }

    _loadServiceDiscoveryData();
  }

  @override
  void dispose() {
    searchController.dispose();
    postcodeController.dispose();
    super.dispose();
  }

  Future<void> loadLocation() async {
    final position = await LocationService().getCurrentLocation();

    if (!mounted) return;

    setState(() {
      userPosition =
          position != null &&
              HomeBusinessDiscoveryPolicy.hasValidCoordinates(
                position.latitude,
                position.longitude,
              )
          ? position
          : null;
      locationLoadComplete = true;
    });
  }

  Future<void> _loadServiceDiscoveryData() async {
    try {
      final grouped = <String, List<Map<String, dynamic>>>{};
      final services =
          await ServiceCatalogDiscoveryService.loadDiscoverableServices();

      for (final service in services) {
        grouped
            .putIfAbsent(service.businessId, () => [])
            .add(service.serviceData);
      }

      if (!mounted) return;

      setState(() {
        serviceDataByBusinessId = grouped;
      });
    } catch (error) {
      assert(() {
        debugPrint('BusinessListScreen service discovery failed: $error');
        if (error is FirebaseException) {
          debugPrint(
            'BusinessListScreen service discovery FirebaseException code=${error.code} plugin=${error.plugin} message=${error.message}',
          );
        }
        return true;
      }());

      if (!mounted) return;

      setState(() {
        serviceDataByBusinessId = const {};
      });
    }
  }

  String _normalise(String value) {
    return value.toLowerCase().replaceAll(' ', '').trim();
  }

  bool _matchesPostcodeOrArea({
    required Map<String, dynamic> data,
    required String postcode,
  }) {
    final normalisedPostcode = _normalise(postcode);

    if (normalisedPostcode.isEmpty) return true;

    final fieldsToCheck = [
      data['postcode'],
      data['businessPostcode'],
      data['address'],
      data['town'],
      data['city'],
      data['county'],
    ];

    for (final field in fieldsToCheck) {
      if (field == null) continue;

      final value = _normalise(field.toString());

      if (value.contains(normalisedPostcode) ||
          normalisedPostcode.contains(value)) {
        return true;
      }
    }

    final listFieldsToCheck = [
      data['servicePostcodes'],
      data['coveredPostcodes'],
      data['serviceTowns'],
      data['areasCovered'],
      data['locationKeywords'],
    ];

    for (final field in listFieldsToCheck) {
      if (field is! List) continue;

      for (final item in field) {
        final value = _normalise(item.toString());

        if (value.contains(normalisedPostcode) ||
            normalisedPostcode.contains(value)) {
          return true;
        }
      }
    }

    return false;
  }

  bool _matchesSearch({
    required BusinessModel business,
    required Map<String, dynamic> data,
    required String query,
  }) {
    return LocalDiscoveryFilters.matchesText(
      data,
      query,
      extraValues: [
        business.name,
        for (final service
            in serviceDataByBusinessId[business.id] ?? const []) ...[
          service['name'],
          service['serviceName'],
          service['details'],
          service['description'],
          service['category'],
          service['searchKeywords'],
        ],
      ],
    );
  }

  bool _matchesCategory({
    required String businessId,
    required Map<String, dynamic> data,
    required String? category,
  }) {
    if (category == null || category.isEmpty) return true;

    final businessCategory = data['category']?.toString() ?? '';

    if (BusinessCategories.normalise(businessCategory) == category) return true;

    return (serviceDataByBusinessId[businessId] ?? const []).any(
      (service) => service['category']?.toString() == category,
    );
  }

  double? _distanceFor(BusinessModel business) {
    final position = userPosition;
    if (position == null ||
        !HomeBusinessDiscoveryPolicy.hasValidCoordinates(
          position.latitude,
          position.longitude,
        )) {
      return null;
    }

    return HomeBusinessDiscoveryPolicy.distanceMilesBetween(
      startLatitude: position.latitude,
      startLongitude: position.longitude,
      endLatitude: business.latitude,
      endLongitude: business.longitude,
    );
  }

  void _clearPostcode() {
    setState(() {
      postcodeText = '';
      postcodeController.clear();
    });
  }

  void _applyPostcodeSearch() {
    setState(() {
      postcodeText = postcodeController.text.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasPostcode = postcodeText.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Businesses'),
        centerTitle: true,
        actions: [
          if (userPosition == null)
            IconButton(
              tooltip: 'Use current location',
              onPressed: loadLocation,
              icon: const Icon(Icons.near_me_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: postcodeController,
              textCapitalization: TextCapitalization.characters,
              keyboardType: TextInputType.streetAddress,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _applyPostcodeSearch(),
              decoration: InputDecoration(
                hintText: 'Search by postcode e.g. WS7 3AF',
                prefixIcon: const Icon(Icons.location_on_outlined),
                suffixIcon: hasPostcode
                    ? IconButton(
                        onPressed: _clearPostcode,
                        icon: const Icon(Icons.close),
                      )
                    : IconButton(
                        onPressed: _applyPostcodeSearch,
                        icon: const Icon(Icons.search),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Search business name or service',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  searchText = value.toLowerCase();
                });
              },
            ),
          ),

          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];

                final isSelected = selectedCategory == category;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        if (isSelected) {
                          selectedCategory = null;
                        } else {
                          selectedCategory = category;
                        }
                      });
                    },
                  ),
                );
              },
            ),
          ),

          if (hasPostcode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 18,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Showing businesses matching $postcodeText',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('businesses')
                  .where('isActive', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      "We couldn't load businesses. Please try again.",
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                final originalDataById = <String, Map<String, dynamic>>{};

                List<BusinessModel> businesses = docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;

                  originalDataById[doc.id] = data;

                  return BusinessModel.fromFirestore(doc.id, data);
                }).toList();

                businesses = businesses.where((business) {
                  final data = originalDataById[business.id];

                  if (data == null) return false;
                  if (!_isPubliclyDiscoverableBusiness(data)) return false;

                  return _matchesSearch(
                        business: business,
                        data: data,
                        query: searchText,
                      ) &&
                      _matchesCategory(
                        businessId: business.id,
                        data: data,
                        category: selectedCategory,
                      ) &&
                      _matchesPostcodeOrArea(
                        data: data,
                        postcode: postcodeText,
                      );
                }).toList();

                final requiresCurrentLocation =
                    widget.useCurrentLocation && !hasPostcode;
                final hasValidUserPosition =
                    userPosition != null &&
                    HomeBusinessDiscoveryPolicy.hasValidCoordinates(
                      userPosition!.latitude,
                      userPosition!.longitude,
                    );

                if (requiresCurrentLocation &&
                    !locationLoadComplete &&
                    !hasValidUserPosition) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (requiresCurrentLocation && !hasValidUserPosition) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'We need your location to show nearby businesses.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (hasValidUserPosition) {
                  final selectedRadius =
                      HomeBusinessDiscoveryPolicy.selectedRadiusMiles(
                        businesses.map(_distanceFor),
                      );

                  businesses = businesses.where((business) {
                    final distance = _distanceFor(business);

                    if (distance == null) return false;

                    return HomeBusinessDiscoveryPolicy.isWithinRadius(
                      distanceMiles: distance,
                      radiusMiles: selectedRadius,
                    );
                  }).toList();

                  businesses.sort((a, b) {
                    final aDistance = _distanceFor(a);
                    final bDistance = _distanceFor(b);

                    if (aDistance == null && bDistance == null) return 0;
                    if (aDistance == null) return 1;
                    if (bDistance == null) return -1;

                    return aDistance.compareTo(bDistance);
                  });
                }

                if (businesses.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        hasPostcode
                            ? 'No businesses found for $postcodeText yet.'
                            : 'No businesses found.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: businesses.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final business = businesses[index];

                    final data = originalDataById[business.id] ?? {};

                    final distance = _distanceFor(business);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (distance != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6, left: 4),
                            child: Text(
                              '${distance.toStringAsFixed(1)} miles away',
                            ),
                          ),
                        BusinessCard(
                          businessId: business.id,
                          businessData: data,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _isPubliclyDiscoverableBusiness(Map<String, dynamic> data) {
    return BusinessDiscoveryService.isPubliclyDiscoverable(data);
  }
}
