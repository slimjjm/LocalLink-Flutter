import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_business_discovery_policy.dart';
import 'local_discovery_filters.dart';

class OrganisationDiscoveryRecord {
  const OrganisationDiscoveryRecord({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;
}

class OrganisationDiscoveryCandidate {
  const OrganisationDiscoveryCandidate({
    required this.record,
    required this.distanceMiles,
  });
  final OrganisationDiscoveryRecord record;
  final double distanceMiles;
}

class OrganisationDiscoveryService {
  const OrganisationDiscoveryService._();

  static Stream<List<OrganisationDiscoveryRecord>> watchActiveOrganisations({
    FirebaseFirestore? firestore,
  }) => (firestore ?? FirebaseFirestore.instance)
      .collection('organisations')
      .where('isActive', isEqualTo: true)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            OrganisationDiscoveryRecord(id: doc.id, data: doc.data()),
        ],
      );

  static bool isDiscoverable(Map<String, dynamic> data) {
    if (data['isActive'] != true ||
        LocalDiscoveryFilters.hasExplicitPublicVisibilityBlock(data)) {
      return false;
    }
    // Fail closed for explicit or malformed privacy declarations.
    for (final key in ['visibility', 'discoveryVisibility']) {
      if (data.containsKey(key) && data[key] != '' && data[key] != 'public') {
        return false;
      }
    }
    for (final key in ['isPublic', 'isPubliclyDiscoverable']) {
      if (data.containsKey(key) && data[key] != true) return false;
    }
    for (final key in ['isPrivate', 'private']) {
      if (data.containsKey(key) && data[key] != false) return false;
    }
    return data['visibility'] == 'public' ||
        data['discoveryVisibility'] == 'public' ||
        data['isPublic'] == true ||
        data['isPubliclyDiscoverable'] == true ||
        // Both existing creation flows create public listings without a visibility field.
        data['createdByModerator'] == true ||
        data['selfServiceCreated'] == true ||
        data['claimStatus'] == 'approved' ||
        data['listingOwnershipStatus'] == 'claimed';
  }

  static List<OrganisationDiscoveryCandidate> nearbyCandidates({
    required Iterable<OrganisationDiscoveryRecord> records,
    required num? userLatitude,
    required num? userLongitude,
    String query = '',
    String category = 'All',
    String activityType = 'All',
    double? radiusMiles,
  }) {
    final candidates = <OrganisationDiscoveryCandidate>[];
    for (final record in records) {
      final data = record.data;
      if (!isDiscoverable(data) ||
          !LocalDiscoveryFilters.matchesText(data, query) ||
          !LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
            data,
            selectedCategory: category,
            selectedActivityType: activityType,
          )) {
        continue;
      }
      final distance = HomeBusinessDiscoveryPolicy.distanceMilesBetween(
        startLatitude: userLatitude,
        startLongitude: userLongitude,
        endLatitude: double.tryParse(data['latitude']?.toString() ?? ''),
        endLongitude: double.tryParse(data['longitude']?.toString() ?? ''),
      );
      if (distance != null) {
        candidates.add(
          OrganisationDiscoveryCandidate(
            record: record,
            distanceMiles: distance,
          ),
        );
      }
    }
    final radius =
        radiusMiles ??
        HomeBusinessDiscoveryPolicy.selectedRadiusMiles(
          candidates.map((item) => item.distanceMiles),
        );
    return candidates
        .where(
          (item) => HomeBusinessDiscoveryPolicy.isWithinRadius(
            distanceMiles: item.distanceMiles,
            radiusMiles: radius,
          ),
        )
        .toList();
  }
}
