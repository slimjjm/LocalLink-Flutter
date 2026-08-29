import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'local_discovery_filters.dart';

class ServiceCatalogItem {
  final String serviceId;
  final String businessId;
  final Map<String, dynamic> serviceData;
  final Map<String, dynamic> businessData;

  const ServiceCatalogItem({
    required this.serviceId,
    required this.businessId,
    required this.serviceData,
    required this.businessData,
  });
}

class ServiceCatalogDiscoveryService {
  const ServiceCatalogDiscoveryService._();

  static Stream<List<ServiceCatalogItem>> watchDiscoverableServices({
    FirebaseFirestore? firestore,
  }) {
    final db = firestore ?? FirebaseFirestore.instance;

    return db
        .collection('businesses')
        .where('isActive', isEqualTo: true)
        .where('isClaimed', isEqualTo: true)
        .snapshots()
        .asyncMap(_loadServicesForBusinesses);
  }

  static Future<List<ServiceCatalogItem>> loadDiscoverableServices({
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final businesses = await db
        .collection('businesses')
        .where('isActive', isEqualTo: true)
        .where('isClaimed', isEqualTo: true)
        .get();

    return _loadServicesForBusinesses(businesses);
  }

  @visibleForTesting
  static bool isBusinessDiscoverable(Map<String, dynamic> data) {
    final businessIsActive = data['isActive'] != false;
    final businessIsClaimed = data['isClaimed'] == true;
    final paymentMethods = data['paymentMethods'];
    final canTakeBookings =
        data['chargesEnabled'] == true ||
        (paymentMethods is List && paymentMethods.isNotEmpty);

    return businessIsActive && businessIsClaimed && canTakeBookings;
  }

  @visibleForTesting
  static Map<String, dynamic> serviceDataWithBusinessContext({
    required String serviceId,
    required String businessId,
    required Map<String, dynamic> serviceData,
    required Map<String, dynamic> businessData,
  }) {
    return {
      ...serviceData,
      'businessId': serviceData['businessId'] ?? businessId,
      'businessName':
          serviceData['businessName'] ?? businessData['businessName'],
      'category': serviceData['category'] ?? businessData['category'],
    };
  }

  static bool businessServiceGroupMatches({
    required Map<String, dynamic> businessData,
    required Iterable<ServiceCatalogItem> services,
    required String query,
  }) {
    final value = query.trim();
    return value.isEmpty ||
        LocalDiscoveryFilters.matchesText(businessData, value) ||
        services.any(
          (service) =>
              LocalDiscoveryFilters.matchesText(service.serviceData, value),
        );
  }

  static List<ServiceCatalogItem> sortServicesForSearch({
    required Iterable<ServiceCatalogItem> services,
    required String query,
  }) {
    final value = query.trim();
    final sorted = [...services];

    sorted.sort((a, b) {
      final aMatches = LocalDiscoveryFilters.matchesText(a.serviceData, value);
      final bMatches = LocalDiscoveryFilters.matchesText(b.serviceData, value);
      if (aMatches != bMatches) return aMatches ? -1 : 1;

      final aName = a.serviceData['name']?.toString().toLowerCase() ?? '';
      final bName = b.serviceData['name']?.toString().toLowerCase() ?? '';
      return aName.compareTo(bName);
    });

    return sorted;
  }

  static Future<List<ServiceCatalogItem>> _loadServicesForBusinesses(
    QuerySnapshot<Map<String, dynamic>> businesses,
  ) async {
    final items = <ServiceCatalogItem>[];

    for (final business in businesses.docs) {
      final businessData = business.data();

      if (!isBusinessDiscoverable(businessData)) {
        continue;
      }

      try {
        final services = await business.reference
            .collection('services')
            .where('isActive', isEqualTo: true)
            .get();

        for (final service in services.docs) {
          final data = serviceDataWithBusinessContext(
            serviceId: service.id,
            businessId: business.id,
            serviceData: service.data(),
            businessData: businessData,
          );

          if (!LocalDiscoveryFilters.isServiceDiscoverable(data)) {
            continue;
          }

          items.add(
            ServiceCatalogItem(
              serviceId: service.id,
              businessId: business.id,
              serviceData: data,
              businessData: businessData,
            ),
          );
        }
      } on FirebaseException catch (error, stackTrace) {
        _debugLog(
          'Service subcollection query failed for business ${business.id}.',
          error,
          stackTrace,
        );
      } catch (error, stackTrace) {
        _debugLog(
          'Unexpected service subcollection query failure for business ${business.id}.',
          error,
          stackTrace,
        );
      }
    }

    return items;
  }

  static void _debugLog(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    assert(() {
      debugPrint('ServiceCatalogDiscoveryService: $message');
      if (error is FirebaseException) {
        debugPrint(
          'ServiceCatalogDiscoveryService FirebaseException code=${error.code} plugin=${error.plugin} message=${error.message}',
        );
      } else if (error != null) {
        debugPrint('ServiceCatalogDiscoveryService error=$error');
      }
      if (stackTrace != null) {
        debugPrint('ServiceCatalogDiscoveryService stack=$stackTrace');
      }
      return true;
    }());
  }
}
