import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/admin_access_service.dart';
import 'package:locallink_flutter/services/local_discovery_filters.dart';
import 'package:locallink_flutter/services/service_catalog_discovery_service.dart';

void main() {
  group('service discovery', () {
    test('newly created active service becomes discoverable', () {
      final service = {
        'name': 'Dog grooming',
        'details': 'Bath, trim and tidy for small dogs',
        'businessName': 'Burntwood Pets',
        'category': 'Dog Groomer',
        'isActive': true,
      };

      expect(LocalDiscoveryFilters.isServiceDiscoverable(service), isTrue);
      expect(LocalDiscoveryFilters.matchesText(service, 'dog groomer'), isTrue);
      expect(LocalDiscoveryFilters.matchesText(service, 'bath'), isTrue);
      expect(LocalDiscoveryFilters.matchesText(service, 'burntwood'), isTrue);
    });

    test('inactive or rejected services do not become discoverable', () {
      expect(
        LocalDiscoveryFilters.isServiceDiscoverable({
          'name': 'Dog grooming',
          'isActive': false,
        }),
        isFalse,
      );
      expect(
        LocalDiscoveryFilters.isServiceDiscoverable({
          'name': 'Dog grooming',
          'isActive': true,
          'approvalStatus': 'rejected',
        }),
        isFalse,
      );
      expect(
        LocalDiscoveryFilters.isServiceDiscoverable({
          'name': 'Dog grooming',
          'isActive': true,
          'moderationStatus': 'removed',
        }),
        isFalse,
      );
    });

    test('non-bookable parent business is not discoverable', () {
      expect(
        ServiceCatalogDiscoveryService.isBusinessDiscoverable({
          'isActive': true,
          'isClaimed': true,
          'paymentMethods': ['cash'],
        }),
        isTrue,
      );
      expect(
        ServiceCatalogDiscoveryService.isBusinessDiscoverable({
          'isActive': false,
          'isClaimed': true,
          'paymentMethods': ['cash'],
        }),
        isFalse,
      );
      expect(
        ServiceCatalogDiscoveryService.isBusinessDiscoverable({
          'isActive': true,
          'isClaimed': false,
          'paymentMethods': ['cash'],
        }),
        isFalse,
      );
      expect(
        ServiceCatalogDiscoveryService.isBusinessDiscoverable({
          'isActive': true,
          'isClaimed': true,
          'paymentMethods': [],
          'chargesEnabled': false,
        }),
        isFalse,
      );
    });

    test('older service documents inherit searchable business context', () {
      final service =
          ServiceCatalogDiscoveryService.serviceDataWithBusinessContext(
            serviceId: 'service-1',
            businessId: 'business-1',
            serviceData: {
              'name': 'Puppy trim',
              'details': 'Gentle grooming for young dogs',
              'isActive': true,
            },
            businessData: {
              'businessName': 'Burntwood Pets',
              'category': 'Dog Groomer',
            },
          );

      expect(service['businessId'], 'business-1');
      expect(service['businessName'], 'Burntwood Pets');
      expect(service['category'], 'Dog Groomer');
      expect(LocalDiscoveryFilters.matchesText(service, 'puppy'), isTrue);
      expect(LocalDiscoveryFilters.matchesText(service, 'burntwood'), isTrue);
      expect(LocalDiscoveryFilters.matchesText(service, 'dog groomer'), isTrue);
    });

    test('business service group matches by service or business text', () {
      final services = [
        ServiceCatalogItem(
          serviceId: 'panelling',
          businessId: 'business-1',
          serviceData: {
            'name': 'Panelling Quote',
            'details': 'Feature walls and trims',
            'isActive': true,
          },
          businessData: const {},
        ),
        ServiceCatalogItem(
          serviceId: 'exterior',
          businessId: 'business-1',
          serviceData: {
            'name': 'Exterior Painting Quote',
            'details': 'Outdoor paintwork',
            'isActive': true,
          },
          businessData: const {},
        ),
      ];

      expect(
        ServiceCatalogDiscoveryService.businessServiceGroupMatches(
          businessData: {'businessName': 'CS Painting Solutions'},
          services: services,
          query: 'exterior painting',
        ),
        isTrue,
      );
      expect(
        ServiceCatalogDiscoveryService.businessServiceGroupMatches(
          businessData: {'businessName': 'CS Painting Solutions'},
          services: services,
          query: 'CS Painting',
        ),
        isTrue,
      );
      expect(
        ServiceCatalogDiscoveryService.businessServiceGroupMatches(
          businessData: {'businessName': 'CS Painting Solutions'},
          services: services,
          query: 'dog walking',
        ),
        isFalse,
      );
    });

    test('business service carousel prioritises matching search results', () {
      final panelling = ServiceCatalogItem(
        serviceId: 'panelling',
        businessId: 'business-1',
        serviceData: {
          'name': 'Panelling Quote',
          'details': 'Feature walls and trims',
          'isActive': true,
        },
        businessData: const {},
      );
      final interior = ServiceCatalogItem(
        serviceId: 'interior',
        businessId: 'business-1',
        serviceData: {
          'name': 'Interior Painting Quote',
          'details': 'Rooms and ceilings',
          'isActive': true,
        },
        businessData: const {},
      );
      final exterior = ServiceCatalogItem(
        serviceId: 'exterior',
        businessId: 'business-1',
        serviceData: {
          'name': 'Exterior Painting Quote',
          'details': 'Outdoor walls and fences',
          'isActive': true,
        },
        businessData: const {},
      );

      final sorted = ServiceCatalogDiscoveryService.sortServicesForSearch(
        services: [panelling, interior, exterior],
        query: 'exterior painting',
      );

      expect(sorted.first.serviceId, 'exterior');
      expect(sorted.map((item) => item.businessId).toSet(), {'business-1'});
      expect(sorted, hasLength(3));
    });
  });

  test('activity search uses title, category, description and location', () {
    final activity = {
      'title': 'Football tonight',
      'category': 'Fitness & Sport',
      'description': 'Casual five-a-side',
      'location': 'Burntwood',
      'isActive': true,
      'eventDate': DateTime(2026, 9, 1),
    };

    expect(
      LocalDiscoveryFilters.isActivityDiscoverable(
        activity,
        now: DateTime(2026, 8, 27),
      ),
      isTrue,
    );
    expect(LocalDiscoveryFilters.matchesText(activity, 'football'), isTrue);
    expect(LocalDiscoveryFilters.matchesText(activity, 'sport'), isTrue);
    expect(LocalDiscoveryFilters.matchesText(activity, 'burntwood'), isTrue);
  });

  test('past opportunities are not discoverable', () {
    expect(
      LocalDiscoveryFilters.isOpportunityDiscoverable({
        'title': 'Old activity',
        'isActive': true,
        'eventDate': DateTime(2026, 8, 1),
      }, now: DateTime(2026, 8, 27)),
      isFalse,
    );
  });

  test(
    'Community Help search preserves active, expiry and resolved filtering',
    () {
      final activeMissingPet = {
        'type': 'lost_found',
        'mode': 'lost',
        'itemCategory': 'Pet',
        'title': 'Milo',
        'description': 'Black Labrador',
        'publicLocation': 'Chasewater',
        'status': 'active',
        'isActive': true,
        'expiresAt': DateTime(2026, 8, 28),
      };

      expect(
        LocalDiscoveryFilters.isCommunityHelpDiscoverable(
          activeMissingPet,
          now: DateTime(2026, 8, 27),
        ),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.matchesText(activeMissingPet, 'milo'),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.matchesText(activeMissingPet, 'labrador'),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.matchesText(activeMissingPet, 'chasewater'),
        isTrue,
      );

      expect(
        LocalDiscoveryFilters.isCommunityHelpDiscoverable({
          ...activeMissingPet,
          'status': 'resolved',
        }, now: DateTime(2026, 8, 27)),
        isFalse,
      );
      expect(
        LocalDiscoveryFilters.isCommunityHelpDiscoverable({
          ...activeMissingPet,
          'expiresAt': DateTime(2026, 8, 20),
        }, now: DateTime(2026, 8, 27)),
        isFalse,
      );
    },
  );

  group('admin access', () {
    test('admin profile flag grants app-side admin navigation', () {
      expect(AdminAccessService.hasAdminProfileFlag({'isAdmin': true}), isTrue);
    });

    test('ordinary profile does not receive app-side admin navigation', () {
      expect(
        AdminAccessService.hasAdminProfileFlag({'isAdmin': false}),
        isFalse,
      );
      expect(AdminAccessService.hasAdminProfileFlag({}), isFalse);
      expect(AdminAccessService.hasAdminProfileFlag(null), isFalse);
    });
  });
}
