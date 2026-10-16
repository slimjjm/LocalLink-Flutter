import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../constants/business_categories.dart';
import '../models/business.dart';
import 'home_business_discovery_policy.dart';
import 'local_discovery_filters.dart';

class BusinessDiscoveryService {
  static Future<List<BusinessModel>> loadBusinesses({
    Position? userPosition,

    String searchText = '',

    String? selectedCategory,

    bool featuredOnly = false,

    int limit = 50,
  }) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('businesses')
        .where('isActive', isEqualTo: true)
        .get();

    List<BusinessModel> businesses = [];

    for (final doc in snapshot.docs) {
      final data = doc.data();

      if (!isPubliclyDiscoverable(data)) {
        continue;
      }

      // =====================================
      // BASIC VALIDATION
      // =====================================

      final latitude = (data['latitude'] as num?)?.toDouble();

      final longitude = (data['longitude'] as num?)?.toDouble();

      final businessName = data['businessName'] ?? '';

      final category = data['category'] ?? '';

      final serviceMode = data['serviceMode'] ?? 'premises';

      final serviceRadius =
          (data['serviceRadiusMiles'] as num?)?.toDouble() ?? 10;

      // =====================================
      // FEATURED FILTER
      // =====================================

      if (featuredOnly) {
        final isFeatured =
            data['isFeatured'] == true ||
            data['featured'] == true ||
            data['foundingBusiness'] == true;

        if (!isFeatured) {
          continue;
        }
      }

      // =====================================
      // SEARCH FILTER
      // =====================================

      if (searchText.isNotEmpty) {
        final lower = searchText.toLowerCase();

        final matches =
            businessName.toLowerCase().contains(lower) ||
            category.toLowerCase().contains(lower);

        if (!matches) {
          continue;
        }
      }

      // =====================================
      // CATEGORY FILTER
      // =====================================

      if (selectedCategory != null &&
          BusinessCategories.normalise(category.toString()) !=
              BusinessCategories.normalise(selectedCategory)) {
        continue;
      }

      // =====================================
      // DISTANCE CALCULATION
      // =====================================

      double? distanceMiles;

      if (userPosition != null) {
        distanceMiles = HomeBusinessDiscoveryPolicy.distanceMilesBetween(
          startLatitude: userPosition.latitude,
          startLongitude: userPosition.longitude,
          endLatitude: latitude,
          endLongitude: longitude,
        );
      }

      // =====================================
      // SERVICE AREA FILTERING
      // =====================================

      bool shouldShow = true;

      if (userPosition != null) {
        shouldShow = isWithinDiscoveryRadius(
          data,
          distanceMiles: distanceMiles,
          serviceMode: serviceMode.toString(),
          serviceRadiusMiles: serviceRadius,
          requireDistance: HomeBusinessDiscoveryPolicy.hasValidCoordinates(
            userPosition.latitude,
            userPosition.longitude,
          ),
        );
      }

      if (!shouldShow) {
        continue;
      }

      // =====================================
      // BUILD MODEL
      // =====================================

      businesses.add(
        BusinessModel.fromFirestore(doc.id, data, distanceMiles: distanceMiles),
      );
    }

    // =====================================
    // SORT NEAREST FIRST
    // =====================================

    businesses.sort((a, b) {
      final aDistance = a.distanceMiles ?? 9999;

      final bDistance = b.distanceMiles ?? 9999;

      return aDistance.compareTo(bDistance);
    });

    return businesses.take(limit).toList();
  }

  static bool isPubliclyDiscoverable(Map<String, dynamic> data) {
    if (!LocalDiscoveryFilters.isPublicRecord(data)) return false;
    if (_normalisedText(data['moderationStatus']) == 'removed') return false;
    if (_normalisedText(data['approvalStatus']) == 'rejected') return false;

    final claimed = data['isClaimed'] == true;
    final moderatorSeededUnclaimed = isStandaloneSeededUnclaimedBusiness(data);

    return claimed || moderatorSeededUnclaimed;
  }

  static bool isHomeAvailabilityParentDiscoverable(Map<String, dynamic> data) {
    return isPubliclyDiscoverable(data);
  }

  static bool isStandaloneSeededUnclaimedBusiness(Map<String, dynamic> data) {
    return LocalDiscoveryFilters.isPublicRecord(data) &&
        _normalisedText(data['moderationStatus']) != 'removed' &&
        _normalisedText(data['approvalStatus']) != 'rejected' &&
        data['createdByModerator'] == true &&
        data['listingOwnershipStatus'] != 'claimed' &&
        data['claimStatus'] != 'approved';
  }

  static String _normalisedText(Object? value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  @visibleForTesting
  static bool isWithinDiscoveryRadius(
    Map<String, dynamic> data, {
    required double? distanceMiles,
    String? serviceMode,
    double? serviceRadiusMiles,
    bool requireDistance = false,
  }) {
    if (distanceMiles == null) return !requireDistance;

    final mode = serviceMode ?? data['serviceMode']?.toString() ?? 'premises';
    final radius =
        serviceRadiusMiles ??
        (data['serviceRadiusMiles'] as num?)?.toDouble() ??
        10;

    if (mode == 'mobile' || mode == 'hybrid') {
      return distanceMiles <= radius;
    }

    return distanceMiles <= 15;
  }

  static bool shouldShowStandaloneBusiness({
    required String businessId,
    required Map<String, dynamic> data,
    required Set<String> representedBusinessIds,
    required String searchText,
    required double? distanceMiles,
    bool requireDistance = false,
  }) {
    if (representedBusinessIds.contains(businessId)) return false;
    if (!isPubliclyDiscoverable(data)) return false;
    if (!LocalDiscoveryFilters.matchesText(data, searchText)) return false;
    if (!isWithinDiscoveryRadius(
      data,
      distanceMiles: distanceMiles,
      requireDistance: requireDistance,
    )) {
      return false;
    }

    return true;
  }

  @visibleForTesting
  static bool shouldShowStandaloneSeededBusiness({
    required String businessId,
    required Map<String, dynamic> data,
    required Set<String> representedBusinessIds,
    required String searchText,
    required double? distanceMiles,
    bool requireDistance = false,
  }) {
    return shouldShowStandaloneBusiness(
      businessId: businessId,
      data: data,
      representedBusinessIds: representedBusinessIds,
      searchText: searchText,
      distanceMiles: distanceMiles,
      requireDistance: requireDistance,
    );
  }
}
