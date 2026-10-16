import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/constants/activity_categories.dart';
import 'package:locallink_flutter/constants/business_categories.dart';
import 'package:locallink_flutter/models/business_opening_hours.dart';
import 'package:locallink_flutter/services/admin_access_service.dart';
import 'package:locallink_flutter/services/business_discovery_service.dart';
import 'package:locallink_flutter/services/home_business_discovery_policy.dart';
import 'package:locallink_flutter/services/home_feed_rules.dart';
import 'package:locallink_flutter/services/local_discovery_filters.dart';
import 'package:locallink_flutter/services/service_catalog_discovery_service.dart';
import 'package:locallink_flutter/utils/helpers.dart';
import 'package:locallink_flutter/widgets/opportunity_map_view.dart';

void main() {
  group('activity categories', () {
    test('shared taxonomy preserves Home filter compatibility', () {
      expect(ActivityCategories.filters.first, ActivityCategories.all);
      expect(ActivityCategories.values, contains('Fitness & Sport'));
      expect(ActivityCategories.values, contains('Family'));
      expect(ActivityCategories.values, contains('Pets'));
      expect(
        ActivityCategories.matchesFilter('Fitness & Sport', 'Fitness & Sport'),
        isTrue,
      );
      expect(
        ActivityCategories.matchesFilter('Children & Family', 'Family'),
        isTrue,
      );
      expect(
        ActivityCategories.matchesFilter(
          'Support & Wellbeing',
          'Wellbeing & Support',
        ),
        isTrue,
      );
    });
  });

  group('organisation activity audience', () {
    final now = DateTime(2026, 9, 15, 12);

    test(
      'legacy standalone discovery is retained while ambiguous linked activities stay restricted',
      () {
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Open run',
            'isActive': true,
          }, now: now),
          isTrue,
        );
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Legacy club activity',
            'isActive': true,
            'organisationId': 'org-1',
          }, now: now),
          isFalse,
        );
      },
    );

    test('public organisation activity is discoverable', () {
      expect(
        LocalDiscoveryFilters.isActivityDiscoverable({
          'title': 'Community open day',
          'isActive': true,
          'organisationId': 'org-1',
          'activityAudienceScope': 'everyone',
          'isPubliclyDiscoverable': true,
        }, now: now),
        isTrue,
      );
    });

    test(
      'whole organisation and group activities are not public discovery items',
      () {
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Members briefing',
            'isActive': true,
            'organisationId': 'org-1',
            'activityAudienceScope': 'organisation',
            'isPubliclyDiscoverable': false,
          }, now: now),
          isFalse,
        );
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Team training',
            'isActive': true,
            'organisationId': 'org-1',
            'groupId': 'group-1',
            'activityAudienceScope': 'group',
            'isPubliclyDiscoverable': false,
          }, now: now),
          isFalse,
        );
      },
    );

    test(
      'explicit public discovery false always wins over legacy fallback',
      () {
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Hidden standalone activity',
            'isActive': true,
            'isPubliclyDiscoverable': false,
          }, now: now),
          isFalse,
        );
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Hidden open day',
            'isActive': true,
            'organisationId': 'org-1',
            'activityAudienceScope': 'everyone',
            'isPubliclyDiscoverable': false,
          }, now: now),
          isFalse,
        );
      },
    );

    test('date-only activity remains discoverable throughout its day', () {
      expect(
        LocalDiscoveryFilters.isActivityDiscoverable({
          'title': 'Today activity',
          'isActive': true,
          'eventDate': DateTime(2026, 9, 15),
        }, now: DateTime(2026, 9, 15, 12)),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.isActivityDiscoverable({
          'title': 'Yesterday activity',
          'isActive': true,
          'eventDate': DateTime(2026, 9, 14),
        }, now: DateTime(2026, 9, 15, 12)),
        isFalse,
      );
      expect(
        LocalDiscoveryFilters.isActivityDiscoverable({
          'title': 'Tomorrow activity',
          'isActive': true,
          'eventDate': DateTime(2026, 9, 16),
        }, now: DateTime(2026, 9, 15, 12)),
        isTrue,
      );
    });

    test('community challenge expiry prefers challengeClosesAt', () {
      expect(
        LocalDiscoveryFilters.isActivityDiscoverable({
          'title': 'Today photo challenge',
          'isActive': true,
          'activityKind': 'community_challenge',
          'eventDate': DateTime(2026, 9, 15),
          'challengeClosesAt': DateTime(2026, 9, 15, 18),
        }, now: DateTime(2026, 9, 15, 12)),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.isActivityDiscoverable({
          'title': 'Expired photo challenge',
          'isActive': true,
          'activityKind': 'community_challenge',
          'eventDate': DateTime(2026, 9, 20),
          'challengeClosesAt': DateTime(2026, 9, 15, 9),
        }, now: DateTime(2026, 9, 15, 12)),
        isFalse,
      );
      expect(
        LocalDiscoveryFilters.isActivityDiscoverable({
          'title': 'Challenge without close time',
          'isActive': true,
          'activityKind': 'community_challenge',
          'eventDate': DateTime(2026, 9, 15),
        }, now: DateTime(2026, 9, 15, 12)),
        isTrue,
      );
    });

    test('public map activity visibility respects explicit blockers', () {
      final publicActivity = {
        'title': 'Open bootcamp',
        'isActive': true,
        'eventDate': DateTime(2026, 9, 16),
      };

      expect(isPublicMapActivity(publicActivity, now: now), isTrue);
      expect(
        isPublicMapActivity({...publicActivity, 'private': true}, now: now),
        isFalse,
      );
      expect(
        isPublicMapActivity({...publicActivity, 'hidden': true}, now: now),
        isFalse,
      );
      expect(
        isPublicMapActivity({...publicActivity, 'archived': true}, now: now),
        isFalse,
      );
      expect(
        isPublicMapActivity({
          ...publicActivity,
          'organisationId': 'org-1',
          'groupId': 'group-1',
          'activityAudienceScope': 'group',
        }, now: now),
        isFalse,
      );
      expect(
        isPublicMapActivity({
          ...publicActivity,
          'organisationId': 'org-1',
          'activityAudienceScope': 'everyone',
          'isPubliclyDiscoverable': true,
        }, now: now),
        isTrue,
      );
      for (final moderationStatus in [
        'removed',
        'rejected',
        'blocked',
        'hidden',
      ]) {
        expect(
          isPublicMapActivity({
            ...publicActivity,
            'moderationStatus': moderationStatus,
          }, now: now),
          isFalse,
        );
      }
    });
  });

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

    test(
      'claimed and moderator seeded parent businesses remain discoverable before payments setup',
      () {
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
            'isClaimed': false,
            'createdByModerator': true,
            'listingOwnershipStatus': 'unclaimed',
            'claimStatus': 'unclaimed',
            'paymentMethods': ['cash'],
          }),
          isTrue,
        );
        expect(
          ServiceCatalogDiscoveryService.isBusinessDiscoverable({
            'isActive': true,
            'isClaimed': true,
            'paymentMethods': [],
            'chargesEnabled': false,
          }),
          isTrue,
        );
        expect(
          ServiceCatalogDiscoveryService.isBusinessDiscoverable({
            'isActive': true,
            'isClaimed': true,
            'paymentMethods': ['cash'],
            'acceptingLeads': false,
          }),
          isTrue,
        );
      },
    );

    test('missing payment configuration does not imply cash accepted', () {
      expect(resolvePaymentMethods({}), isEmpty);
      expect(resolvePaymentMethods({'paymentMethods': []}), isEmpty);
      expect(
        resolvePaymentMethods({
          'paymentMethods': ['cash', 'stripe'],
          'stripeConnected': false,
          'stripeChargesEnabled': false,
        }),
        ['cash'],
      );
      expect(
        resolvePaymentMethods({
          'paymentMethods': ['cash', 'bank_transfer', 'stripe'],
          'stripeConnected': true,
          'stripeChargesEnabled': true,
        }),
        ['cash', 'bank_transfer', 'stripe'],
      );
      expect(paymentMethodLabel('bank_transfer'), 'Bank transfer');
      expect(paymentMethodLabel('stripe'), 'Card & Apple Pay');
    });

    test('service prices without a supplied fixed price do not show zero', () {
      expect(formatPrice(null), 'Price on request');
      expect(formatPrice(0), 'Price on request');
      expect(formatPrice(''), 'Price on request');
      expect(formatPrice(13), '£0.13');
      expect(formatPrice(1250), '£12.50');
    });

    test(
      'business cover image resolves from existing business image fields',
      () {
        expect(
          businessCoverImageUrl({
            'photoURLs': ['https://example.com/gallery-cover.jpg'],
          }),
          'https://example.com/gallery-cover.jpg',
        );
        expect(
          businessCoverImageUrl({
            'bannerImageUrl': 'https://example.com/banner.jpg',
            'photoURLs': ['https://example.com/gallery-cover.jpg'],
          }),
          'https://example.com/banner.jpg',
        );
        expect(
          businessCoverImageUrl({
            'galleryUrls': ['https://example.com/legacy-gallery.jpg'],
          }),
          'https://example.com/legacy-gallery.jpg',
        );
        expect(
          businessPhotoUrls({
            'photoURLs': ['https://example.com/photo.jpg'],
            'galleryUrls': ['gs://locallink.appspot.com/businessPhotos/1.jpg'],
          }),
          [
            'https://example.com/photo.jpg',
            'gs://locallink.appspot.com/businessPhotos/1.jpg',
          ],
        );
        expect(businessCoverImageUrl({'photoURLs': []}), isEmpty);
      },
    );

    test('Home business discovery progressively widens but caps distance', () {
      final localDistance = HomeBusinessDiscoveryPolicy.distanceMilesBetween(
        startLatitude: 52.681,
        startLongitude: -1.927,
        endLatitude: 52.690,
        endLongitude: -1.920,
      );
      final farDistance = HomeBusinessDiscoveryPolicy.distanceMilesBetween(
        startLatitude: 52.681,
        startLongitude: -1.927,
        endLatitude: 51.5072,
        endLongitude: -0.1276,
      );

      expect(
        HomeBusinessDiscoveryPolicy.hasValidCoordinates(52.681, -1.927),
        isTrue,
      );
      expect(HomeBusinessDiscoveryPolicy.hasValidCoordinates(0, 0), isFalse);
      expect(
        HomeBusinessDiscoveryPolicy.hasValidCoordinates(181, -1.927),
        isFalse,
      );
      expect(localDistance, isNotNull);
      expect(localDistance!, lessThan(15));
      expect(farDistance, isNotNull);
      expect(farDistance!, greaterThan(40));
      expect(
        HomeBusinessDiscoveryPolicy.distanceMilesBetween(
          startLatitude: 0,
          startLongitude: 0,
          endLatitude: 52.690,
          endLongitude: -1.920,
        ),
        isNull,
      );
      expect(
        HomeBusinessDiscoveryPolicy.distanceMilesBetween(
          startLatitude: 52.681,
          startLongitude: -1.927,
          endLatitude: 0,
          endLongitude: 0,
        ),
        isNull,
      );
      expect(
        HomeBusinessDiscoveryPolicy.selectedRadiusMiles([2, 6, 14, 120]),
        HomeBusinessDiscoveryPolicy.initialRadiusMiles,
      );
      expect(
        HomeBusinessDiscoveryPolicy.selectedRadiusMiles([2, 18, 24, 120]),
        HomeBusinessDiscoveryPolicy.expandedRadiusMiles,
      );
      expect(
        HomeBusinessDiscoveryPolicy.selectedRadiusMiles([2, 30, 39, 120]),
        HomeBusinessDiscoveryPolicy.maximumRadiusMiles,
      );
      expect(
        HomeBusinessDiscoveryPolicy.isWithinRadius(
          distanceMiles: 120,
          radiusMiles: HomeBusinessDiscoveryPolicy.maximumRadiusMiles,
        ),
        isFalse,
      );
      expect(
        HomeBusinessDiscoveryPolicy.isWithinRadius(
          distanceMiles: localDistance,
          radiusMiles: HomeBusinessDiscoveryPolicy.initialRadiusMiles,
        ),
        isTrue,
      );
      expect(
        HomeBusinessDiscoveryPolicy.isWithinRadius(
          distanceMiles: 18,
          radiusMiles: HomeBusinessDiscoveryPolicy.expandedRadiusMiles,
        ),
        isTrue,
      );
      expect(
        HomeBusinessDiscoveryPolicy.isWithinRadius(
          distanceMiles: null,
          radiusMiles: HomeBusinessDiscoveryPolicy.maximumRadiusMiles,
        ),
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

  test('activity search uses structured audience tags and age fields', () {
    final activity = {
      'title': 'Burntwood 1st Scouts',
      'category': 'Children & Family',
      'audience': 'Children, Teenagers',
      'audienceValues': ['Children', 'Teenagers'],
      'tags': ['Scouts', 'Youth', 'Outdoor', 'Skills'],
      'minimumAge': 10,
      'maximumAge': 14,
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
    expect(LocalDiscoveryFilters.matchesText(activity, 'scouts'), isTrue);
    expect(LocalDiscoveryFilters.matchesText(activity, 'youth'), isTrue);
    expect(LocalDiscoveryFilters.matchesText(activity, 'children'), isTrue);
    expect(LocalDiscoveryFilters.matchesText(activity, '12'), isTrue);
    expect(LocalDiscoveryFilters.matchesText(activity, '10'), isTrue);
    expect(LocalDiscoveryFilters.matchesText(activity, '14'), isTrue);
  });

  test(
    'organisation activity groups match by linked child activity metadata',
    () {
      final rugbyActivities = [
        {
          'title': 'U8 Rugby Training',
          'category': 'Fitness & Sport',
          'activityType': 'Rugby',
          'organisationName': 'Burntwood Rugby Club',
          'organisationCategory': 'Fitness & Sport',
          'organisationSubcategories': ['Rugby'],
          'isActive': true,
        },
        {
          'title': 'Adult Rugby',
          'category': 'Fitness & Sport',
          'activityType': 'Rugby',
          'organisationName': 'Burntwood Rugby Club',
          'organisationCategory': 'Fitness & Sport',
          'organisationSubcategories': ['Rugby'],
          'isActive': true,
        },
      ];

      expect(
        LocalDiscoveryFilters.organisationActivityGroupMatches(
          activities: rugbyActivities,
          selectedCategory: 'Fitness & Sport',
          selectedActivityType: 'Rugby',
          searchText: '',
        ),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.organisationActivityGroupMatches(
          activities: rugbyActivities,
          selectedCategory: 'Fitness & Sport',
          selectedActivityType: 'Hockey',
          searchText: '',
        ),
        isFalse,
      );
      expect(
        LocalDiscoveryFilters.organisationActivityGroupMatches(
          activities: rugbyActivities,
          selectedCategory: 'Fitness & Sport',
          selectedActivityType: 'All',
          searchText: 'u8',
        ),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.organisationActivityGroupMatches(
          activities: rugbyActivities,
          selectedCategory: 'Fitness & Sport',
          selectedActivityType: 'All',
          searchText: 'burntwood rugby',
        ),
        isTrue,
      );
    },
  );

  group('mixed discovery category filters', () {
    final cleaner = {
      'businessName': 'CG Elite Cleaning',
      'category': 'Cleaner',
      'description': 'Domestic cleaning and tidying',
    };

    final painter = {
      'businessName': 'CS Painting Solutions',
      'category': 'Painter',
      'serviceName': 'Interior Painting Quote',
    };

    final rugby = {
      'title': 'U8 Rugby Training',
      'category': 'Fitness & Sport',
      'activityType': 'Rugby',
      'organisationName': 'Burntwood Rugby Club',
      'organisationCategory': 'Fitness & Sport',
      'organisationSubcategories': ['Rugby'],
    };

    final hockey = {
      'title': 'Junior Hockey',
      'category': 'Fitness & Sport',
      'activityType': 'Hockey',
      'organisationName': 'Burntwood Hockey Club',
      'organisationCategory': 'Fitness & Sport',
      'organisationSubcategories': ['Hockey'],
    };

    test('All plus no category keeps mixed content eligible', () {
      expect(
        LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
          cleaner,
          selectedCategory: 'All',
          selectedActivityType: 'All',
        ),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
          rugby,
          selectedCategory: 'All',
          selectedActivityType: 'All',
        ),
        isTrue,
      );
    });

    test('All plus Fitness & Sport excludes unrelated service businesses', () {
      expect(
        LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
          cleaner,
          selectedCategory: 'Fitness & Sport',
          selectedActivityType: 'All',
        ),
        isFalse,
      );
      expect(
        LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
          painter,
          selectedCategory: 'Fitness & Sport',
          selectedActivityType: 'All',
        ),
        isFalse,
      );
    });

    test('All plus Fitness & Sport includes relevant sport content', () {
      expect(
        LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
          rugby,
          selectedCategory: 'Fitness & Sport',
          selectedActivityType: 'All',
        ),
        isTrue,
      );
    });

    test('All plus Fitness & Sport plus Rugby narrows subcategory results', () {
      expect(
        LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
          rugby,
          selectedCategory: 'Fitness & Sport',
          selectedActivityType: 'Rugby',
        ),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.matchesDiscoveryCategoryFilters(
          hockey,
          selectedCategory: 'Fitness & Sport',
          selectedActivityType: 'Rugby',
        ),
        isFalse,
      );
    });

    test('Activities plus Fitness & Sport uses the same category rule', () {
      expect(
        LocalDiscoveryFilters.matchesActivityCategory(rugby, 'Fitness & Sport'),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.matchesActivityCategory(
          cleaner,
          'Fitness & Sport',
        ),
        isFalse,
      );
    });
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

  test('Community Help geographic eligibility uses post discovery radius', () {
    const userLat = 52.681;
    const userLng = -1.927;

    Map<String, dynamic> petPostAtMiles(double miles) => {
      'type': 'lost_found',
      'mode': 'lost',
      'itemCategory': 'Pet',
      'approxLatitude': userLat,
      'approxLongitude': _longitudeAtMiles(
        latitude: userLat,
        longitude: userLng,
        miles: miles,
      ),
      'discoveryRadiusMiles': 10,
    };

    for (final miles in [0.5, 5.0, 9.9, 10.0]) {
      expect(
        LocalDiscoveryFilters.isCommunityHelpGeographicallyEligible(
          petPostAtMiles(miles),
          userLatitude: userLat,
          userLongitude: userLng,
        ),
        isTrue,
        reason: '$miles miles should be discoverable',
      );
    }

    for (final miles in [10.1, 15.0, 30.0, 100.0]) {
      expect(
        LocalDiscoveryFilters.isCommunityHelpGeographicallyEligible(
          petPostAtMiles(miles),
          userLatitude: userLat,
          userLongitude: userLng,
        ),
        isFalse,
        reason: '$miles miles should not be discoverable',
      );
    }

    expect(
      LocalDiscoveryFilters.isCommunityHelpGeographicallyEligible(
        {...petPostAtMiles(15), 'discoveryRadiusMiles': 20},
        userLatitude: userLat,
        userLongitude: userLng,
      ),
      isTrue,
    );
    expect(
      LocalDiscoveryFilters.isCommunityHelpGeographicallyEligible(
        {...petPostAtMiles(21), 'discoveryRadiusMiles': 20},
        userLatitude: userLat,
        userLongitude: userLng,
      ),
      isFalse,
    );
  });

  test(
    'Community Help geographic eligibility handles legacy and invalid data',
    () {
      const userLat = 52.681;
      const userLng = -1.927;
      final legacyPet = {
        'type': 'lost_found',
        'mode': 'lost',
        'itemCategory': 'Pet',
        'approxLatitude': userLat,
        'approxLongitude': _longitudeAtMiles(
          latitude: userLat,
          longitude: userLng,
          miles: 9,
        ),
      };

      expect(
        LocalDiscoveryFilters.isCommunityHelpGeographicallyEligible(
          legacyPet,
          userLatitude: userLat,
          userLongitude: userLng,
        ),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.isCommunityHelpGeographicallyEligible(
          {...legacyPet, 'approxLatitude': null},
          userLatitude: userLat,
          userLongitude: userLng,
        ),
        isFalse,
      );
      expect(
        LocalDiscoveryFilters.isCommunityHelpGeographicallyEligible(
          {...legacyPet, 'approxLatitude': 0, 'approxLongitude': 0},
          userLatitude: userLat,
          userLongitude: userLng,
        ),
        isFalse,
      );
      expect(
        LocalDiscoveryFilters.isCommunityHelpGeographicallyEligible(
          legacyPet,
          userLatitude: 0,
          userLongitude: 0,
        ),
        isFalse,
      );
    },
  );

  test('public map Community Help visibility respects explicit blockers', () {
    final now = DateTime(2026, 8, 27);
    final publicPost = {
      'type': 'lost_found',
      'mode': 'lost',
      'itemCategory': 'Pet',
      'title': 'Milo',
      'status': 'active',
      'isActive': true,
      'expiresAt': DateTime(2026, 8, 28),
    };

    final localPost = {
      ...publicPost,
      'approxLatitude': 52.681,
      'approxLongitude': -1.927,
      'discoveryRadiusMiles': 10,
    };

    expect(
      isPublicMapCommunityHelp(
        localPost,
        now: now,
        userLatitude: 52.681,
        userLongitude: -1.927,
      ),
      isTrue,
    );
    expect(
      isPublicMapCommunityHelp(
        {...localPost, 'private': true},
        now: now,
        userLatitude: 52.681,
        userLongitude: -1.927,
      ),
      isFalse,
    );
    expect(
      isPublicMapCommunityHelp(
        {...localPost, 'hidden': true},
        now: now,
        userLatitude: 52.681,
        userLongitude: -1.927,
      ),
      isFalse,
    );
    expect(
      isPublicMapCommunityHelp(
        {...localPost, 'archived': true},
        now: now,
        userLatitude: 52.681,
        userLongitude: -1.927,
      ),
      isFalse,
    );
    expect(
      isPublicMapCommunityHelp(
        {...localPost, 'deleted': true},
        now: now,
        userLatitude: 52.681,
        userLongitude: -1.927,
      ),
      isFalse,
    );
    expect(
      isPublicMapCommunityHelp(
        {...localPost, 'isPubliclyDiscoverable': false},
        now: now,
        userLatitude: 52.681,
        userLongitude: -1.927,
      ),
      isFalse,
    );
  });

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

  group('business discovery', () {
    test(
      'business categories normalise canonical values without hiding legacy labels',
      () {
        expect(BusinessCategories.normalise(' cleaner '), 'Cleaner');
        expect(BusinessCategories.isCanonical('Cleaner'), isTrue);
        expect(
          BusinessCategories.normalise('Custom legacy category'),
          'Custom legacy category',
        );
        expect(
          BusinessCategories.isCanonical('Custom legacy category'),
          isFalse,
        );
      },
    );

    test(
      'structured business opening hours summarise and legacy text falls back',
      () {
        final hours = BusinessOpeningHours.defaultStructured();

        expect(
          BusinessOpeningHours.summary(hours),
          contains('Monday - Friday: 09:00 - 17:00'),
        );
        expect(
          BusinessOpeningHours.displayText({'openingHours': 'By appointment'}),
          'By appointment',
        );
      },
    );

    test('moderator seeded unclaimed businesses are publicly discoverable', () {
      expect(
        BusinessDiscoveryService.isPubliclyDiscoverable({'isClaimed': true}),
        isTrue,
      );

      expect(
        BusinessDiscoveryService.isPubliclyDiscoverable({'isClaimed': false}),
        isFalse,
      );

      expect(
        BusinessDiscoveryService.isPubliclyDiscoverable({
          'isClaimed': false,
          'createdByModerator': true,
          'listingOwnershipStatus': 'unclaimed',
        }),
        isTrue,
      );
      expect(
        ServiceCatalogDiscoveryService.isBusinessDiscoverable({
          'isClaimed': false,
          'createdByModerator': true,
          'listingOwnershipStatus': 'unclaimed',
          'claimStatus': 'unclaimed',
          'isActive': true,
        }),
        isTrue,
      );

      expect(
        BusinessDiscoveryService.isPubliclyDiscoverable({
          'isClaimed': true,
          'createdByModerator': true,
          'listingOwnershipStatus': 'claimed',
        }),
        isTrue,
      );
    });

    test('moderator seeded business can be found by business name', () {
      final business = {
        'businessName': 'Tedsbakeryvan',
        'name': 'Tedsbakeryvan',
        'category': 'Specialist Services',
        'createdByModerator': true,
        'listingOwnershipStatus': 'unclaimed',
        'claimStatus': 'unclaimed',
        'isActive': true,
      };

      expect(BusinessDiscoveryService.isPubliclyDiscoverable(business), isTrue);
      expect(
        ServiceCatalogDiscoveryService.isBusinessDiscoverable(business),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.matchesText(business, 'Tedsbakeryvan'),
        isTrue,
      );
      expect(LocalDiscoveryFilters.matchesText(business, 'specialist'), isTrue);
    });

    test('explicit non-public business signals exclude Flutter discovery', () {
      final publicClaimedBusiness = {'isActive': true, 'isClaimed': true};

      expect(
        BusinessDiscoveryService.isPubliclyDiscoverable(publicClaimedBusiness),
        isTrue,
      );
      expect(
        ServiceCatalogDiscoveryService.isBusinessDiscoverable(
          publicClaimedBusiness,
        ),
        isTrue,
      );

      for (final blocker in [
        {'hidden': true},
        {'archived': true},
        {'deleted': true},
        {'private': true},
        {'isPubliclyDiscoverable': false},
        {'visibility': 'restricted'},
        {'status': 'removed'},
      ]) {
        final business = {...publicClaimedBusiness, ...blocker};

        expect(
          BusinessDiscoveryService.isPubliclyDiscoverable(business),
          isFalse,
        );
        expect(
          ServiceCatalogDiscoveryService.isBusinessDiscoverable(business),
          isFalse,
        );
      }
    });

    test(
      'legacy business records without newer visibility fields remain public',
      () {
        expect(
          BusinessDiscoveryService.isPubliclyDiscoverable({'isClaimed': true}),
          isTrue,
        );
        expect(
          ServiceCatalogDiscoveryService.isBusinessDiscoverable({
            'isClaimed': true,
          }),
          isTrue,
        );
        expect(
          BusinessDiscoveryService.isPubliclyDiscoverable({
            'createdByModerator': true,
            'listingOwnershipStatus': 'unclaimed',
          }),
          isTrue,
        );
      },
    );

    test(
      'availability-backed Home cards require an active public parent business',
      () {
        expect(
          BusinessDiscoveryService.isHomeAvailabilityParentDiscoverable({
            'isActive': true,
            'isClaimed': true,
          }),
          isTrue,
        );

        expect(
          BusinessDiscoveryService.isHomeAvailabilityParentDiscoverable({
            'isActive': false,
            'isClaimed': true,
          }),
          isFalse,
        );

        expect(
          BusinessDiscoveryService.isHomeAvailabilityParentDiscoverable({
            'isActive': true,
            'isClaimed': false,
          }),
          isFalse,
        );
      },
    );

    test(
      'seeded unclaimed business with no services can appear as standalone discovery',
      () {
        final business = {
          'businessName': 'New Eggs',
          'category': 'Gardener',
          'claimStatus': 'unclaimed',
          'createdByModerator': true,
          'listingOwnershipStatus': 'unclaimed',
          'businessOwnerId': '',
          'area': 'Burntwood',
          'isActive': true,
        };

        expect(
          BusinessDiscoveryService.shouldShowStandaloneSeededBusiness(
            businessId: 'new-eggs',
            data: business,
            representedBusinessIds: const {},
            searchText: '',
            distanceMiles: null,
          ),
          isTrue,
        );
        expect(
          BusinessDiscoveryService.shouldShowStandaloneSeededBusiness(
            businessId: 'new-eggs',
            data: business,
            representedBusinessIds: const {},
            searchText: '',
            distanceMiles: null,
            requireDistance: true,
          ),
          isFalse,
        );
      },
    );

    test(
      'public claimed business with no services can appear as standalone discovery',
      () {
        final business = {
          'businessName': 'Lichfield Cycle Repairs',
          'category': 'Repairs',
          'claimStatus': 'approved',
          'listingOwnershipStatus': 'claimed',
          'isClaimed': true,
          'isActive': true,
          'isPubliclyDiscoverable': true,
          'serviceMode': 'premises',
        };

        expect(
          BusinessDiscoveryService.shouldShowStandaloneBusiness(
            businessId: 'cycle-repairs',
            data: business,
            representedBusinessIds: const {},
            searchText: '',
            distanceMiles: 4,
          ),
          isTrue,
        );
        expect(
          BusinessDiscoveryService.shouldShowStandaloneBusiness(
            businessId: 'cycle-repairs',
            data: business,
            representedBusinessIds: const {},
            searchText: 'cycle',
            distanceMiles: 4,
          ),
          isTrue,
        );
      },
    );

    test(
      'standalone business discovery still excludes unsafe or distant records',
      () {
        final business = {
          'businessName': 'Lichfield Cycle Repairs',
          'category': 'Repairs',
          'isClaimed': true,
          'isActive': true,
          'serviceMode': 'premises',
        };

        for (final blocked in [
          {'isActive': false},
          {'isPubliclyDiscoverable': false},
          {'hidden': true},
          {'moderationStatus': 'removed'},
          {'visibility': 'private'},
        ]) {
          expect(
            BusinessDiscoveryService.shouldShowStandaloneBusiness(
              businessId: 'cycle-repairs',
              data: {...business, ...blocked},
              representedBusinessIds: const {},
              searchText: '',
              distanceMiles: 4,
            ),
            isFalse,
          );
        }

        expect(
          BusinessDiscoveryService.shouldShowStandaloneBusiness(
            businessId: 'cycle-repairs',
            data: business,
            representedBusinessIds: const {},
            searchText: '',
            distanceMiles: 16,
          ),
          isFalse,
        );
      },
    );

    test(
      'standalone seeded businesses are not duplicated if services already represent them',
      () {
        expect(
          BusinessDiscoveryService.shouldShowStandaloneSeededBusiness(
            businessId: 'new-eggs',
            data: {
              'businessName': 'New Eggs',
              'createdByModerator': true,
              'listingOwnershipStatus': 'unclaimed',
              'claimStatus': 'unclaimed',
              'isActive': true,
            },
            representedBusinessIds: const {'new-eggs'},
            searchText: '',
            distanceMiles: null,
          ),
          isFalse,
        );
      },
    );

    test(
      'standalone seeded business search and radius restrictions still apply',
      () {
        final business = {
          'businessName': 'New Eggs',
          'category': 'Gardener',
          'createdByModerator': true,
          'listingOwnershipStatus': 'unclaimed',
          'claimStatus': 'unclaimed',
          'isActive': true,
          'serviceMode': 'premises',
        };

        expect(
          BusinessDiscoveryService.shouldShowStandaloneSeededBusiness(
            businessId: 'new-eggs',
            data: business,
            representedBusinessIds: const {},
            searchText: 'gardener',
            distanceMiles: 3,
          ),
          isTrue,
        );
        expect(
          BusinessDiscoveryService.shouldShowStandaloneSeededBusiness(
            businessId: 'new-eggs',
            data: business,
            representedBusinessIds: const {},
            searchText: 'cleaner',
            distanceMiles: 3,
          ),
          isFalse,
        );
        expect(
          BusinessDiscoveryService.shouldShowStandaloneSeededBusiness(
            businessId: 'new-eggs',
            data: business,
            representedBusinessIds: const {},
            searchText: '',
            distanceMiles: 16,
          ),
          isFalse,
        );
        expect(
          BusinessDiscoveryService.shouldShowStandaloneSeededBusiness(
            businessId: 'new-eggs',
            data: business,
            representedBusinessIds: const {},
            searchText: '',
            distanceMiles: 30,
          ),
          isFalse,
        );
      },
    );
  });

  group('Home mixed feed locality and completeness rules', () {
    final now = DateTime(2026, 9, 27, 12);

    test('Home discovery categories keep the requested order and labels', () {
      expect(HomeFeedRules.categories.map((category) => category.label), [
        'Nearby',
        'Services',
        'Activities',
        'Community Help',
        'Businesses',
        'Organisations',
      ]);
    });

    test('Home discovery categories include the expected content types', () {
      for (final type in HomeFeedContentType.values) {
        expect(
          HomeFeedRules.categoryAllowsType(HomeDiscoveryCategory.nearby, type),
          isTrue,
        );
      }

      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.businesses,
          HomeFeedContentType.availability,
        ),
        isTrue,
      );
      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.businesses,
          HomeFeedContentType.serviceBusiness,
        ),
        isTrue,
      );
      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.businesses,
          HomeFeedContentType.standaloneBusiness,
        ),
        isTrue,
      );
      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.businesses,
          HomeFeedContentType.serviceRequest,
        ),
        isFalse,
      );

      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.activities,
          HomeFeedContentType.activity,
        ),
        isTrue,
      );
      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.activities,
          HomeFeedContentType.organisation,
        ),
        isFalse,
      );
      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.activities,
          HomeFeedContentType.communityHelp,
        ),
        isFalse,
      );

      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.communityHelp,
          HomeFeedContentType.communityHelp,
        ),
        isTrue,
      );
      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.communityHelp,
          HomeFeedContentType.activity,
        ),
        isFalse,
      );

      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.services,
          HomeFeedContentType.serviceRequest,
        ),
        isTrue,
      );
      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.services,
          HomeFeedContentType.serviceBusiness,
        ),
        isTrue,
      );
      expect(
        HomeFeedRules.categoryAllowsType(
          HomeDiscoveryCategory.organisations,
          HomeFeedContentType.organisation,
        ),
        isTrue,
      );
    });

    test(
      'local activity and challenge are eligible before Home radius mixing',
      () {
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Local yoga',
            'isActive': true,
            'eventDate': now.add(const Duration(days: 1)),
            'latitude': 52.681,
            'longitude': -1.927,
          }, now: now),
          isTrue,
        );
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Photo challenge',
            'isActive': true,
            'activityKind': 'community_challenge',
            'eventDate': now.add(const Duration(days: 2)),
            'challengeClosesAt': now.add(const Duration(hours: 6)),
            'latitude': 52.681,
            'longitude': -1.927,
          }, now: now),
          isTrue,
        );
      },
    );

    test(
      'active public nearby activity appears in All and Activities tabs',
      () {
        final activity = {
          'title': 'Local yoga',
          'isActive': true,
          'eventDate': now.add(const Duration(days: 1)),
          'latitude': 52.681,
          'longitude': -1.927,
        };

        expect(
          LocalDiscoveryFilters.isActivityDiscoverable(activity, now: now),
          isTrue,
        );

        final candidate = const HomeFeedCandidate(
          item: 'local-yoga',
          type: HomeFeedContentType.activity,
          distanceMiles: 1,
        );
        final local = HomeFeedRules.applyProgressiveRadius([candidate]);

        expect(local.single.item, 'local-yoga');
        expect(
          HomeFeedRules.categoryAllowsType(
            HomeDiscoveryCategory.nearby,
            candidate.type,
          ),
          isTrue,
        );
        expect(
          HomeFeedRules.categoryAllowsType(
            HomeDiscoveryCategory.activities,
            candidate.type,
          ),
          isTrue,
        );
      },
    );

    test('Home excludes out-of-radius activities before mixing', () {
      final filtered = HomeFeedRules.applyProgressiveRadius([
        const HomeFeedCandidate(
          item: 'nearby-activity',
          type: HomeFeedContentType.activity,
          distanceMiles: 2,
        ),
        const HomeFeedCandidate(
          item: 'out-of-radius-activity',
          type: HomeFeedContentType.activity,
          distanceMiles: 60,
        ),
      ]);

      expect(filtered.map((item) => item.item), ['nearby-activity']);
    });

    test(
      'activity visibility blockers are shared by Home and map discovery',
      () {
        final publicActivity = {
          'title': 'Community run',
          'isActive': true,
          'eventDate': now.add(const Duration(days: 1)),
        };

        for (final blocker in [
          {'private': true},
          {'visibility': 'private'},
          {'status': 'removed'},
          {'status': 'rejected'},
          {'moderationStatus': 'removed'},
          {'moderationStatus': 'rejected'},
        ]) {
          final blocked = {...publicActivity, ...blocker};

          expect(
            LocalDiscoveryFilters.isActivityDiscoverable(blocked, now: now),
            isFalse,
          );
          expect(isPublicMapActivity(blocked, now: now), isFalse);
        }
      },
    );

    test(
      'future expired date-only challenge and recurring activities share lifecycle rules',
      () {
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Future activity',
            'isActive': true,
            'eventDate': now.add(const Duration(days: 3)),
          }, now: now),
          isTrue,
        );
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Expired activity',
            'isActive': true,
            'eventDate': now.subtract(const Duration(minutes: 1)),
          }, now: now),
          isFalse,
        );
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Date-only today',
            'isActive': true,
            'eventDate': DateTime(now.year, now.month, now.day),
          }, now: now),
          isTrue,
        );
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Photo challenge',
            'isActive': true,
            'activityKind': 'community_challenge',
            'eventDate': now.subtract(const Duration(days: 2)),
            'challengeClosesAt': now.add(const Duration(hours: 2)),
          }, now: now),
          isTrue,
        );
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Weekly club night',
            'isActive': true,
            'repeatType': 'weekly',
            'eventDate': now.add(const Duration(days: 2)),
          }, now: now),
          isTrue,
        );
        expect(
          LocalDiscoveryFilters.isActivityDiscoverable({
            'title': 'Past recurring instance',
            'isActive': true,
            'repeatType': 'weekly',
            'eventDate': now.subtract(const Duration(days: 2)),
          }, now: now),
          isFalse,
        );
      },
    );

    test('progressive Home radius excludes distant and invalid candidates', () {
      final filtered = HomeFeedRules.applyProgressiveRadius([
        const HomeFeedCandidate(
          item: 'local-activity',
          type: HomeFeedContentType.activity,
          distanceMiles: 1,
        ),
        const HomeFeedCandidate(
          item: 'local-challenge',
          type: HomeFeedContentType.activity,
          distanceMiles: 3,
        ),
        const HomeFeedCandidate(
          item: 'local-service-request',
          type: HomeFeedContentType.serviceRequest,
          distanceMiles: 8,
        ),
        const HomeFeedCandidate(
          item: 'distant-activity',
          type: HomeFeedContentType.activity,
          distanceMiles: 60,
        ),
        const HomeFeedCandidate(
          item: 'invalid-activity',
          type: HomeFeedContentType.activity,
          distanceMiles: null,
        ),
      ]);

      expect(filtered.map((item) => item.item), [
        'local-activity',
        'local-challenge',
        'local-service-request',
      ]);
    });

    test('distant organisation summary is excluded by activity distance', () {
      final filtered = HomeFeedRules.applyProgressiveRadius([
        const HomeFeedCandidate(
          item: 'local-business',
          type: HomeFeedContentType.serviceBusiness,
          distanceMiles: 1,
        ),
        const HomeFeedCandidate(
          item: 'local-help',
          type: HomeFeedContentType.communityHelp,
          distanceMiles: 2,
        ),
        const HomeFeedCandidate(
          item: 'local-request',
          type: HomeFeedContentType.serviceRequest,
          distanceMiles: 3,
        ),
        const HomeFeedCandidate(
          item: 'distant-organisation',
          type: HomeFeedContentType.organisation,
          distanceMiles: 50,
        ),
      ]);

      expect(
        filtered.map((item) => item.item),
        isNot(contains('distant-organisation')),
      );
    });

    test(
      'service request lifecycle excludes closed filled expired and removed',
      () {
        final openRequest = {
          'status': 'open',
          'isActive': true,
          'expiresAt': now.add(const Duration(hours: 2)),
        };

        expect(
          LocalDiscoveryFilters.isServiceRequestDiscoverable(
            openRequest,
            now: now,
          ),
          isTrue,
        );
        for (final status in ['closed', 'filled']) {
          expect(
            LocalDiscoveryFilters.isServiceRequestDiscoverable({
              ...openRequest,
              'status': status,
            }, now: now),
            isFalse,
          );
        }
        expect(
          LocalDiscoveryFilters.isServiceRequestDiscoverable({
            ...openRequest,
            'expiresAt': now.subtract(const Duration(minutes: 1)),
          }, now: now),
          isFalse,
        );
        expect(
          LocalDiscoveryFilters.isServiceRequestDiscoverable({
            ...openRequest,
            'moderationStatus': 'removed',
          }, now: now),
          isFalse,
        );
      },
    );

    test('availability requires a valid current or future time', () {
      expect(
        LocalDiscoveryFilters.isAvailabilityDiscoverable({
          'isActive': true,
          'availabilityAt': now.add(const Duration(minutes: 1)),
        }, now: now),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.isAvailabilityDiscoverable({
          'isActive': true,
          'availabilityAt': now.subtract(const Duration(minutes: 1)),
        }, now: now),
        isFalse,
      );
      expect(
        LocalDiscoveryFilters.isAvailabilityDiscoverable({
          'isActive': true,
          'availabilityAt': 'tomorrow',
        }, now: now),
        isFalse,
      );
      expect(
        LocalDiscoveryFilters.isAvailabilityDiscoverable({
          'isActive': false,
          'availabilityAt': now.add(const Duration(minutes: 1)),
        }, now: now),
        isFalse,
      );
    });

    test('Community Help active/resolved filtering remains intact', () {
      final active = {
        'type': 'lost_found',
        'mode': 'lost',
        'itemCategory': 'Pet',
        'status': 'active',
        'isActive': true,
        'expiresAt': now.add(const Duration(hours: 2)),
      };

      expect(
        LocalDiscoveryFilters.isCommunityHelpDiscoverable(active, now: now),
        isTrue,
      );
      expect(
        LocalDiscoveryFilters.isCommunityHelpDiscoverable({
          ...active,
          'status': 'resolved',
        }, now: now),
        isFalse,
      );
    });

    test('mixed feed keeps non-business categories discoverable', () {
      final candidates = [
        for (var index = 0; index < 20; index++)
          HomeFeedCandidate(
            item: 'business-$index',
            type: HomeFeedContentType.serviceBusiness,
            distanceMiles: 0.1 + index / 100,
          ),
        const HomeFeedCandidate(
          item: 'help',
          type: HomeFeedContentType.communityHelp,
          distanceMiles: 2,
        ),
        const HomeFeedCandidate(
          item: 'request',
          type: HomeFeedContentType.serviceRequest,
          distanceMiles: 2.2,
        ),
        const HomeFeedCandidate(
          item: 'activity',
          type: HomeFeedContentType.activity,
          distanceMiles: 2.4,
        ),
      ];

      final mixed = HomeFeedRules.mix(candidates).map((item) => item.item);
      expect(mixed.take(4), containsAll(['help', 'request', 'activity']));
    });

    test(
      'nearby activities and businesses both appear in mixed All results',
      () {
        final candidates = [
          for (var index = 0; index < 12; index++)
            HomeFeedCandidate(
              item: 'activity-$index',
              type: HomeFeedContentType.activity,
              distanceMiles: 0.2 + index / 10,
            ),
          const HomeFeedCandidate(
            item: 'tedsbakeryvan',
            type: HomeFeedContentType.standaloneBusiness,
            distanceMiles: 3,
          ),
        ];

        final local = HomeFeedRules.applyProgressiveRadius(candidates);
        final all = HomeFeedRules.mix(
          local.where(
            (candidate) => HomeFeedRules.categoryAllowsType(
              HomeDiscoveryCategory.nearby,
              candidate.type,
            ),
          ),
        ).map((candidate) => candidate.item);

        expect(all, contains('activity-0'));
        expect(all.take(4), contains('tedsbakeryvan'));
      },
    );

    test(
      'one content type cannot crowd all others out of early mixed results',
      () {
        final candidates = [
          for (var index = 0; index < 20; index++)
            HomeFeedCandidate(
              item: 'activity-$index',
              type: HomeFeedContentType.activity,
              distanceMiles: 0.1 + index / 100,
            ),
          const HomeFeedCandidate(
            item: 'business',
            type: HomeFeedContentType.standaloneBusiness,
            distanceMiles: 2,
          ),
          const HomeFeedCandidate(
            item: 'service-request',
            type: HomeFeedContentType.serviceRequest,
            distanceMiles: 2.2,
          ),
        ];

        final mixed = HomeFeedRules.mix(candidates).map((item) => item.item);

        expect(mixed.take(4), containsAll(['business', 'service-request']));
      },
    );

    test(
      'Services category includes standalone businesses with no service records',
      () {
        expect(
          HomeFeedRules.categoryAllowsType(
            HomeDiscoveryCategory.businesses,
            HomeFeedContentType.standaloneBusiness,
          ),
          isTrue,
        );
        expect(
          HomeFeedRules.categoryAllowsType(
            HomeDiscoveryCategory.businesses,
            HomeFeedContentType.activity,
          ),
          isFalse,
        );
      },
    );

    test('guest and registered users share the same radius rule', () {
      final guest = HomeFeedRules.applyProgressiveRadius([
        const HomeFeedCandidate(
          item: 'local',
          type: HomeFeedContentType.serviceRequest,
          distanceMiles: 4,
        ),
        const HomeFeedCandidate(
          item: 'distant',
          type: HomeFeedContentType.serviceRequest,
          distanceMiles: 80,
        ),
      ]);
      final registered = HomeFeedRules.applyProgressiveRadius([
        const HomeFeedCandidate(
          item: 'local',
          type: HomeFeedContentType.serviceRequest,
          distanceMiles: 4,
        ),
        const HomeFeedCandidate(
          item: 'distant',
          type: HomeFeedContentType.serviceRequest,
          distanceMiles: 80,
        ),
      ]);

      expect(
        guest.map((item) => item.item),
        registered.map((item) => item.item),
      );
    });

    test(
      'location refresh threshold only treats material moves as changed',
      () {
        expect(
          HomeBusinessDiscoveryPolicy.hasMeaningfulLocationChange(
            previousLatitude: 52.681,
            previousLongitude: -1.927,
            nextLatitude: 52.6811,
            nextLongitude: -1.9271,
          ),
          isFalse,
        );
        expect(
          HomeBusinessDiscoveryPolicy.hasMeaningfulLocationChange(
            previousLatitude: 52.681,
            previousLongitude: -1.927,
            nextLatitude: 52.681,
            nextLongitude: _longitudeAtMiles(
              latitude: 52.681,
              longitude: -1.927,
              miles: 0.5,
            ),
          ),
          isTrue,
        );
      },
    );
  });
}

double _longitudeAtMiles({
  required double latitude,
  required double longitude,
  required double miles,
}) {
  final milesPerLongitudeDegree = 69.172 * math.cos(latitude * math.pi / 180);
  return longitude + miles / milesPerLongitudeDegree;
}
