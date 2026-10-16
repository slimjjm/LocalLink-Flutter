import 'package:flutter/foundation.dart';

import 'home_business_discovery_policy.dart';

enum HomeFeedContentType {
  communityHelp,
  serviceRequest,
  activity,
  organisation,
  availability,
  serviceBusiness,
  standaloneBusiness,
}

enum HomeDiscoveryCategory {
  nearby('Nearby'),
  services('Services'),
  activities('Activities'),
  communityHelp('Community Help'),
  businesses('Businesses'),
  organisations('Organisations');

  const HomeDiscoveryCategory(this.label);

  final String label;
}

@immutable
class HomeFeedCandidate<T> {
  const HomeFeedCandidate({
    required this.item,
    required this.type,
    required this.distanceMiles,
  });

  final T item;
  final HomeFeedContentType type;
  final double? distanceMiles;
}

class HomeFeedRules {
  const HomeFeedRules._();

  static const categories = HomeDiscoveryCategory.values;

  static List<HomeFeedCandidate<T>> applyProgressiveRadius<T>(
    Iterable<HomeFeedCandidate<T>> candidates,
  ) {
    final items = candidates.toList();
    final radiusMiles = HomeBusinessDiscoveryPolicy.selectedRadiusMiles(
      items.map((item) => item.distanceMiles),
    );

    return items
        .where(
          (item) => HomeBusinessDiscoveryPolicy.isWithinRadius(
            distanceMiles: item.distanceMiles,
            radiusMiles: radiusMiles,
          ),
        )
        .toList();
  }

  static List<HomeFeedCandidate<T>> mix<T>(
    Iterable<HomeFeedCandidate<T>> candidates,
  ) {
    final groups = <HomeFeedContentType, List<HomeFeedCandidate<T>>>{};
    for (final candidate in candidates) {
      groups.putIfAbsent(candidate.type, () => []).add(candidate);
    }

    for (final group in groups.values) {
      group.sort(_compareByDistance);
    }

    final mixed = <HomeFeedCandidate<T>>[];
    var addedInRound = true;
    while (addedInRound) {
      addedInRound = false;
      for (final type in _mixingOrder) {
        final group = groups[type];
        if (group == null || group.isEmpty) continue;
        mixed.add(group.removeAt(0));
        addedInRound = true;
      }
    }

    return mixed;
  }

  static bool categoryAllowsType(
    HomeDiscoveryCategory category,
    HomeFeedContentType type,
  ) {
    return switch (category) {
      HomeDiscoveryCategory.nearby => true,
      HomeDiscoveryCategory.services =>
        type == HomeFeedContentType.serviceRequest ||
            type == HomeFeedContentType.availability ||
            type == HomeFeedContentType.serviceBusiness,
      HomeDiscoveryCategory.businesses =>
        type == HomeFeedContentType.availability ||
            type == HomeFeedContentType.serviceBusiness ||
            type == HomeFeedContentType.standaloneBusiness,
      HomeDiscoveryCategory.activities => type == HomeFeedContentType.activity,
      HomeDiscoveryCategory.communityHelp =>
        type == HomeFeedContentType.communityHelp,
      HomeDiscoveryCategory.organisations =>
        type == HomeFeedContentType.organisation,
    };
  }

  static String emptyTitle(HomeDiscoveryCategory category) {
    return switch (category) {
      HomeDiscoveryCategory.nearby => 'No nearby posts yet',
      HomeDiscoveryCategory.services => 'No local services to show yet',
      HomeDiscoveryCategory.businesses => 'No local businesses to show yet',
      HomeDiscoveryCategory.activities => 'Nothing happening nearby yet',
      HomeDiscoveryCategory.communityHelp =>
        'No active Community Help posts nearby',
      HomeDiscoveryCategory.organisations =>
        'No local organisations to show yet',
    };
  }

  static String emptyMessage(HomeDiscoveryCategory category) {
    return switch (category) {
      HomeDiscoveryCategory.nearby =>
        'Try again later or check another local category.',
      HomeDiscoveryCategory.services =>
        'Services, availability and local requests will appear here when they are nearby.',
      HomeDiscoveryCategory.businesses =>
        'Local services and availability will appear here when they are nearby.',
      HomeDiscoveryCategory.activities =>
        'Activities and community challenges will appear here when they are nearby.',
      HomeDiscoveryCategory.communityHelp =>
        'Missing pets, lost and found posts and free-item posts will appear here.',
      HomeDiscoveryCategory.organisations =>
        'Community groups and organisations will appear here when they are nearby.',
    };
  }

  static const _mixingOrder = [
    HomeFeedContentType.communityHelp,
    HomeFeedContentType.serviceRequest,
    HomeFeedContentType.activity,
    HomeFeedContentType.organisation,
    HomeFeedContentType.availability,
    HomeFeedContentType.serviceBusiness,
    HomeFeedContentType.standaloneBusiness,
  ];

  static int _compareByDistance<T>(
    HomeFeedCandidate<T> a,
    HomeFeedCandidate<T> b,
  ) {
    final aDistance = a.distanceMiles ?? double.infinity;
    final bDistance = b.distanceMiles ?? double.infinity;
    return aDistance.compareTo(bDistance);
  }
}
