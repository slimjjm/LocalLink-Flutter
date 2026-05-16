import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../models/business.dart';
import '../services/location_service.dart';
import '../utils/distance_helper.dart';

import 'package:locallink_flutter/widgets/business_card.dart';

class BusinessListScreen extends StatefulWidget {

  const BusinessListScreen({super.key});

  @override
  State<BusinessListScreen> createState() =>
      _BusinessListScreenState();
}

class _BusinessListScreenState
    extends State<BusinessListScreen> {

  Position? userPosition;

  String searchText = '';

  String? selectedCategory;
final categories = [
  'Cleaner',
  'Barber',
  'Nails',
  'Dog Walker',
  'Gardener',
  'Personal Trainer',
];

  @override
  void initState() {
    super.initState();

    loadLocation();
  }

  Future<void> loadLocation() async {

    final position =
        await LocationService()
            .getCurrentLocation();

    if (!mounted) return;

    setState(() {
      userPosition = position;
    });
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text('Businesses'),
        centerTitle: true,
      ),

      body: Column(
        children: [

          // SEARCH BAR

         // SEARCH BAR

Padding(
  padding: const EdgeInsets.all(16),

  child: TextField(

    decoration: InputDecoration(
      hintText: 'Search businesses',

      prefixIcon:
          const Icon(Icons.search),

      border: OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(12),
      ),
    ),

    onChanged: (value) {

      setState(() {
        searchText =
            value.toLowerCase();
      });
    },
  ),
),

// CATEGORY CHIPS

SizedBox(
  height: 50,

  child: ListView.builder(

    scrollDirection:
        Axis.horizontal,

    padding:
        const EdgeInsets.symmetric(
      horizontal: 16,
    ),

    itemCount:
        categories.length,

    itemBuilder:
        (context, index) {

      final category =
          categories[index];

      final isSelected =
          selectedCategory ==
              category;

      return Padding(

        padding:
            const EdgeInsets.only(
          right: 8,
        ),

        child: FilterChip(

          label: Text(category),

          selected: isSelected,

          onSelected: (_) {

            setState(() {

              if (isSelected) {

                selectedCategory =
                    null;

              } else {

                selectedCategory =
                    category;
              }
            });
          },
        ),
      );
    },
  ),
),


          Expanded(
            child:
                StreamBuilder<QuerySnapshot>(

              stream:
                  FirebaseFirestore.instance
                      .collection('businesses')
                      .where(
                        'isActive',
                        isEqualTo: true,
                      )
                      .snapshots(),

              builder: (context, snapshot) {

                // LOADING

                if (snapshot.connectionState ==
                    ConnectionState.waiting) {

                  return const Center(
                    child:
                        CircularProgressIndicator(),
                  );
                }

                // ERROR

                if (snapshot.hasError) {

                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                    ),
                  );
                }

                final docs =
                    snapshot.data?.docs ?? [];

                // CONVERT

                List<BusinessModel>
                    businesses = docs
                        .map((doc) {

                  return BusinessModel
                      .fromFirestore(
                    doc.id,
                    doc.data()
                        as Map<String, dynamic>,
                  );
                }).toList();

                // REMOVE BUSINESSES
                // THAT CANNOT TAKE BOOKINGS

                businesses = businesses
                    .where(
                      (b) =>
                          b.canTakeBookings,
                    )
                    .toList();

                // SEARCH FILTER

                if (searchText.isNotEmpty) {

                  businesses = businesses
                      .where(
                        (b) => b.name
                            .toLowerCase()
                            .contains(
                              searchText,
                            ),
                      )
                      .toList();
                }

                // CATEGORY FILTER

if (selectedCategory != null) {

  businesses = businesses.where(
    (b) {

      final originalDoc =
          docs.firstWhere(
        (doc) => doc.id == b.id,
      );

      final data =
          originalDoc.data()
              as Map<String, dynamic>;

      final category =
          data['category'] ?? '';

      return category ==
          selectedCategory;
    },
  ).toList();
}

                // SORT BY DISTANCE

                if (userPosition != null) {

                  businesses.sort((a, b) {

                    final aDistance =
                        calculateDistanceMiles(
                      startLat:
                          userPosition!
                              .latitude,

                      startLng:
                          userPosition!
                              .longitude,

                      endLat:
                          a.latitude ?? 0,

                      endLng:
                          a.longitude ?? 0,
                    );

                    final bDistance =
                        calculateDistanceMiles(
                      startLat:
                          userPosition!
                              .latitude,

                      startLng:
                          userPosition!
                              .longitude,

                      endLat:
                          b.latitude ?? 0,

                      endLng:
                          b.longitude ?? 0,
                    );

                    return aDistance.compareTo(
                      bDistance,
                    );
                  });
                }

                // EMPTY

                if (businesses.isEmpty) {

                  return const Center(
                    child: Text(
                      'No businesses found',
                    ),
                  );
                }

                return ListView.separated(

                  padding:
                      const EdgeInsets.all(16),

                  itemCount:
                      businesses.length,

                  separatorBuilder:
                      (_, __) =>
                          const SizedBox(
                    height: 12,
                  ),

itemBuilder: (context, index) {

  final business =
      businesses[index];

  // FIND ORIGINAL FIRESTORE DOC

  final originalDoc =
      docs.firstWhere(
    (doc) => doc.id == business.id,
  );

  final data =
      originalDoc.data()
          as Map<String, dynamic>;

  double? distance;

  if (userPosition != null &&
      business.latitude != null &&
      business.longitude != null) {

    distance =
        calculateDistanceMiles(
      startLat:
          userPosition!.latitude,

      startLng:
          userPosition!.longitude,

      endLat:
          business.latitude!,

      endLng:
          business.longitude!,
    );
  }

  return Column(
    crossAxisAlignment:
        CrossAxisAlignment.start,

    children: [

      if (distance != null)

        Padding(
          padding:
              const EdgeInsets.only(
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