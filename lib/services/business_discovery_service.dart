import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../models/business.dart';

class BusinessDiscoveryService {

  static Future<List<BusinessModel>>
      loadBusinesses({

    Position? userPosition,

    String searchText = '',

    String? selectedCategory,

    bool featuredOnly = false,

    int limit = 50,
  }) async {

    final snapshot =
        await FirebaseFirestore.instance
            .collection('businesses')
            .where(
              'isActive',
              isEqualTo: true,
            )
            .where(
              'isClaimed',
              isEqualTo: true,
            )
            .limit(limit)
            .get();

    List<BusinessModel> businesses = [];

    for (final doc in snapshot.docs) {

      final data = doc.data();

      // =====================================
      // BASIC VALIDATION
      // =====================================

      final latitude =
          (data['latitude'] as num?)
              ?.toDouble();

      final longitude =
          (data['longitude'] as num?)
              ?.toDouble();

      final businessName =
          data['businessName'] ?? '';

      final category =
          data['category'] ?? '';

      final serviceMode =
          data['serviceMode'] ??
              'premises';

      final serviceRadius =
          (data['serviceRadiusMiles']
                  as num?)
              ?.toDouble() ??
              10;

      final paymentMethods =
          List<String>.from(
        data['paymentMethods'] ?? [],
      );

      final chargesEnabled =
          data['chargesEnabled'] == true;

      // =====================================
      // MUST BE BOOKABLE
      // =====================================

      final canTakeBookings =
          chargesEnabled ||
              paymentMethods.isNotEmpty;

      if (!canTakeBookings) {
        continue;
      }

      // =====================================
      // FEATURED FILTER
      // =====================================

      if (featuredOnly) {

        final isFeatured =
            data['isFeatured'] == true ||
            data['featured'] == true ||
            data['foundingBusiness']
                == true;

        if (!isFeatured) {
          continue;
        }
      }

      // =====================================
      // SEARCH FILTER
      // =====================================

      if (searchText.isNotEmpty) {

        final lower =
            searchText.toLowerCase();

        final matches =
            businessName
                    .toLowerCase()
                    .contains(lower) ||
                category
                    .toLowerCase()
                    .contains(lower);

        if (!matches) {
          continue;
        }
      }

      // =====================================
      // CATEGORY FILTER
      // =====================================

      if (selectedCategory != null &&
          category != selectedCategory) {

        continue;
      }

      // =====================================
      // DISTANCE CALCULATION
      // =====================================

      double? distanceMiles;

      if (userPosition != null &&
          latitude != null &&
          longitude != null) {

        final meters =
            Geolocator.distanceBetween(
          userPosition.latitude,
          userPosition.longitude,
          latitude,
          longitude,
        );

        distanceMiles =
            meters / 1609.34;
      }

      // =====================================
      // SERVICE AREA FILTERING
      // =====================================

      bool shouldShow = true;

      if (distanceMiles != null) {

        // MOBILE

        if (serviceMode == 'mobile') {

          shouldShow =
              distanceMiles <=
                  serviceRadius;
        }

        // HYBRID

        else if (serviceMode ==
            'hybrid') {

          shouldShow =
              distanceMiles <=
                  serviceRadius;
        }

        // PREMISES

        else {

          shouldShow =
              distanceMiles <= 25;
        }
      }

      if (!shouldShow) {
        continue;
      }

      // =====================================
      // BUILD MODEL
      // =====================================

      businesses.add(

        BusinessModel.fromFirestore(
          doc.id,
          data,
          distanceMiles:
              distanceMiles,
        ),
      );
    }

    // =====================================
    // SORT NEAREST FIRST
    // =====================================

    businesses.sort((a, b) {

      final aDistance =
          a.distanceMiles ?? 9999;

      final bDistance =
          b.distanceMiles ?? 9999;

      return aDistance.compareTo(
        bDistance,
      );
    });

    return businesses;
  }
}