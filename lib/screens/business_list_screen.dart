import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../models/business.dart';
import '../services/location_service.dart';
import '../utils/distance_helper.dart';
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

  String searchText = '';
  String postcodeText = '';
  String? selectedCategory;

  final List<String> categories = const [
    'Aesthetics',
    'Beauty',
    'Brows & Lashes',
    'Hair Salon',
    'Barber',
    'Nails',
    'Massage',
    'Skin Clinic',
    'Cleaner',
    'Dog Groomer',
    'Dog Walker',
    'Gardener',
    'Handyman',
    'Mobile Valeting',
    'Pressure Washing',
    'Specialist Services',
  ];

  @override
  void initState() {
    super.initState();

    selectedCategory = widget.initialCategory;

    if (widget.initialPostcode != null &&
        widget.initialPostcode!.trim().isNotEmpty) {
      postcodeText = widget.initialPostcode!.trim();
      postcodeController.text = postcodeText;
    }

    if (widget.useCurrentLocation) {
      loadLocation();
    }
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
      userPosition = position;
    });
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
    final value = query.toLowerCase().trim();

    if (value.isEmpty) return true;

    final searchableText = [
      business.name,
      data['businessName'],
      data['category'],
      data['address'],
      data['town'],
      data['city'],
      data['description'],
    ]
        .whereType<Object>()
        .map((item) => item.toString().toLowerCase())
        .join(' ');

    return searchableText.contains(value);
  }

  bool _matchesCategory({
    required Map<String, dynamic> data,
    required String? category,
  }) {
    if (category == null || category.isEmpty) return true;

    final businessCategory = data['category']?.toString() ?? '';

    return businessCategory == category;
  }

  double? _distanceFor(BusinessModel business) {
    if (userPosition == null ||
        business.latitude == null ||
        business.longitude == null) {
      return null;
    }

    return calculateDistanceMiles(
      startLat: userPosition!.latitude,
      startLng: userPosition!.longitude,
      endLat: business.latitude!,
      endLng: business.longitude!,
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
                  .where(
                    'isActive',
                    isEqualTo: true,
                  )
                  .where(
                    'isClaimed',
                    isEqualTo: true,
                  )
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                final originalDataById = <String, Map<String, dynamic>>{};

                List<BusinessModel> businesses = docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;

                  originalDataById[doc.id] = data;

                  return BusinessModel.fromFirestore(
                    doc.id,
                    data,
                  );
                }).toList();

                businesses = businesses
                    .where(
                      (business) => business.canTakeBookings,
                    )
                    .toList();

                businesses = businesses.where((business) {
                  final data = originalDataById[business.id];

                  if (data == null) return false;

                  return _matchesSearch(
                        business: business,
                        data: data,
                        query: searchText,
                      ) &&
                      _matchesCategory(
                        data: data,
                        category: selectedCategory,
                      ) &&
                      _matchesPostcodeOrArea(
                        data: data,
                        postcode: postcodeText,
                      );
                }).toList();

              if (userPosition != null) {

  businesses = businesses.where((business) {

    final distance = _distanceFor(business);

    if (distance == null) return false;

    return distance <= 10;

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
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final business = businesses[index];

                    final data = originalDataById[business.id] ?? {};

                    final distance = _distanceFor(business);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (distance != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: 6,
                              left: 4,
                            ),
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
}