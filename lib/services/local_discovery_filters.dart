import 'community_help_location.dart';
import 'community_help_lifecycle.dart';
import 'home_business_discovery_policy.dart';
import 'service_request_marketplace.dart';

class LocalDiscoveryFilters {
  const LocalDiscoveryFilters._();

  static bool matchesText(
    Map<String, dynamic> data,
    String query, {
    Iterable<Object?> extraValues = const [],
  }) {
    final value = query.toLowerCase().trim();
    if (value.isEmpty) return true;

    final fields = [
      data['title'],
      data['name'],
      data['businessName'],
      data['serviceName'],
      data['organisationName'],
      data['organisationCategory'],
      data['organisationSubcategories'],
      data['category'],
      data['activityType'],
      data['subcategory'],
      data['subcategories'],
      data['itemCategory'],
      data['organiserName'],
      data['audience'],
      data['audienceValues'],
      data['tags'],
      data['ageMinimum'],
      data['ageMaximum'],
      data['minimumAge'],
      data['maximumAge'],
      data['description'],
      data['details'],
      data['keywords'],
      data['location'],
      data['publicLocation'],
      data['address'],
      data['town'],
      data['city'],
      data['postcode'],
      ...extraValues,
    ];

    return fields.any((field) => _fieldContains(field, value)) ||
        _ageRangeContains(data, value);
  }

  static bool isServiceDiscoverable(Map<String, dynamic> data) {
    if (hasExplicitPublicVisibilityBlock(data)) return false;

    return data['isActive'] != false &&
        data['isPublished'] != false &&
        data['isEnabled'] != false &&
        data['moderationStatus'] != 'removed' &&
        data['approvalStatus'] != 'rejected';
  }

  static bool isPublicRecord(Map<String, dynamic> data) {
    return data['isActive'] != false && !hasExplicitPublicVisibilityBlock(data);
  }

  static bool hasExplicitPublicVisibilityBlock(Map<String, dynamic> data) {
    if (data['isDeleted'] == true || data['deleted'] == true) return true;
    if (data['isArchived'] == true || data['archived'] == true) return true;
    if (data['isHidden'] == true || data['hidden'] == true) return true;
    if (data['isPrivate'] == true || data['private'] == true) return true;
    if (data['isPubliclyDiscoverable'] == false) return true;

    final visibility = _normalisedText(data['visibility']);
    if (const {
      'private',
      'restricted',
      'members',
      'members_only',
    }.contains(visibility)) {
      return true;
    }

    final status = _normalisedText(data['status']);
    if (const {
      'inactive',
      'archived',
      'deleted',
      'removed',
      'rejected',
    }.contains(status)) {
      return true;
    }

    final moderationStatus = _normalisedText(data['moderationStatus']);
    return const {
      'removed',
      'rejected',
      'blocked',
      'hidden',
    }.contains(moderationStatus);
  }

  static bool isActivityDiscoverable(
    Map<String, dynamic> data, {
    required DateTime now,
  }) {
    if (hasExplicitPublicVisibilityBlock(data)) return false;
    if (data['isActive'] == false) return false;

    final expiresAt = activityExpiresAt(data);
    if (expiresAt != null && !expiresAt.isAfter(now)) return false;
    if (!isPublicActivityAudience(data)) return false;

    return true;
  }

  static DateTime? activityExpiresAt(Map<String, dynamic> data) {
    if (data['activityKind'] == 'community_challenge') {
      final closesAt = CommunityHelpLifecycle.asDateTime(
        data['challengeClosesAt'],
      );
      if (closesAt != null) return closesAt;
    }

    final eventDate = CommunityHelpLifecycle.asDateTime(data['eventDate']);
    if (eventDate == null) return null;

    final dateOnly =
        eventDate.hour == 0 &&
        eventDate.minute == 0 &&
        eventDate.second == 0 &&
        eventDate.millisecond == 0 &&
        eventDate.microsecond == 0;
    if (dateOnly) {
      return DateTime(
        eventDate.year,
        eventDate.month,
        eventDate.day,
      ).add(const Duration(days: 1));
    }

    return eventDate;
  }

  static bool isOpportunityDiscoverable(
    Map<String, dynamic> data, {
    required DateTime now,
  }) {
    return isActivityDiscoverable(data, now: now);
  }

  static bool isPublicActivityAudience(Map<String, dynamic> data) {
    if (data['isPubliclyDiscoverable'] == false) return false;

    if (data.containsKey('isPubliclyDiscoverable') &&
        data['isPubliclyDiscoverable'] != true) {
      return false;
    }
    final scope = data['activityAudienceScope']?.toString().trim() ?? '';
    if (scope.isNotEmpty) return scope == 'everyone';
    final linked =
        (data['organisationId']?.toString().trim() ?? '').isNotEmpty ||
        (data['groupId']?.toString().trim() ?? '').isNotEmpty;
    return !linked || data['isPubliclyDiscoverable'] == true;
  }

  static bool matchesActivityCategory(
    Map<String, dynamic> data,
    String selectedCategory,
  ) {
    if (selectedCategory == 'All') return true;

    final categoryValues = [data['category'], data['organisationCategory']];

    return categoryValues.any(
      (value) => _matchesNormalisedCategory(value, selectedCategory),
    );
  }

  static bool matchesActivityType(
    Map<String, dynamic> data,
    String selectedActivityType,
  ) {
    final value = selectedActivityType.toLowerCase().trim();
    if (value.isEmpty || value == 'all') return true;

    final fields = [
      data['activityType'],
      data['subcategory'],
      data['subcategories'],
      data['organisationSubcategories'],
      data['tags'],
      data['audience'],
      data['audienceValues'],
      data['title'],
      data['description'],
    ];

    return fields.any((field) => _fieldContains(field, value));
  }

  static bool hasExplicitCategoryFilter(
    String selectedCategory,
    String selectedActivityType,
  ) {
    return selectedCategory.toLowerCase().trim() != 'all' ||
        selectedActivityType.toLowerCase().trim() != 'all';
  }

  static bool matchesDiscoveryCategoryFilters(
    Map<String, dynamic> data, {
    required String selectedCategory,
    required String selectedActivityType,
    Iterable<Object?> extraValues = const [],
  }) {
    if (!hasExplicitCategoryFilter(selectedCategory, selectedActivityType)) {
      return true;
    }

    final categoryMatches =
        selectedCategory.toLowerCase().trim() == 'all' ||
        [
          data['category'],
          data['organisationCategory'],
          data['businessCategory'],
          data['serviceCategory'],
        ].any((value) => _matchesNormalisedCategory(value, selectedCategory));

    if (!categoryMatches) return false;

    if (selectedActivityType.toLowerCase().trim() == 'all') {
      return true;
    }

    final fields = [
      data['activityType'],
      data['subcategory'],
      data['subcategories'],
      data['organisationSubcategories'],
      data['tags'],
      data['keywords'],
      data['serviceName'],
      data['name'],
      data['title'],
      data['description'],
      data['details'],
      ...extraValues,
    ];

    return fields.any(
      (field) =>
          _fieldContains(field, selectedActivityType.toLowerCase().trim()),
    );
  }

  static bool organisationActivityGroupMatches({
    required Iterable<Map<String, dynamic>> activities,
    required String selectedCategory,
    required String selectedActivityType,
    required String searchText,
  }) {
    return activities.any((activity) {
      return matchesActivityCategory(activity, selectedCategory) &&
          matchesActivityType(activity, selectedActivityType) &&
          matchesText(activity, searchText);
    });
  }

  static bool isCommunityHelpDiscoverable(
    Map<String, dynamic> data, {
    required DateTime now,
  }) {
    return !hasExplicitPublicVisibilityBlock(data) &&
        CommunityHelpLifecycle.isActiveForDiscovery(data, now);
  }

  static bool isCommunityHelpGeographicallyEligible(
    Map<String, dynamic> data, {
    required num? userLatitude,
    required num? userLongitude,
  }) {
    final coordinates = CommunityHelpLocation.coordinates(data);
    final distanceMiles = HomeBusinessDiscoveryPolicy.distanceMilesBetween(
      startLatitude: userLatitude,
      startLongitude: userLongitude,
      endLatitude: coordinates?.latitude,
      endLongitude: coordinates?.longitude,
    );
    final radiusMiles = _communityHelpDiscoveryRadiusMiles(data);
    return HomeBusinessDiscoveryPolicy.isWithinRadius(
      distanceMiles: distanceMiles,
      radiusMiles: radiusMiles,
    );
  }

  static bool isAvailabilityDiscoverable(
    Map<String, dynamic> data, {
    required DateTime now,
  }) {
    if (hasExplicitPublicVisibilityBlock(data)) return false;
    if (data['isActive'] == false) return false;

    final availabilityAt = CommunityHelpLifecycle.asDateTime(
      data['availabilityAt'],
    );
    if (availabilityAt == null) return false;
    return !availabilityAt.isBefore(now);
  }

  static bool isServiceRequestDiscoverable(
    Map<String, dynamic> data, {
    required DateTime now,
  }) {
    if (data['moderationStatus'] == 'removed') return false;
    if (data['approvalStatus'] == 'rejected') return false;
    return !hasExplicitPublicVisibilityBlock(data) &&
        ServiceRequestMarketplace.isOpenForDiscovery(data, now: now);
  }

  static String _normalisedText(Object? value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  static double _communityHelpDiscoveryRadiusMiles(Map<String, dynamic> data) {
    final stored = _number(data['discoveryRadiusMiles']);
    if (stored != null && stored.isFinite && stored > 0) return stored;

    return CommunityHelpLifecycle.defaultDiscoveryRadiusMiles(
      type: data['type']?.toString() ?? 'lost_found',
      mode: data['mode']?.toString() ?? CommunityHelpLifecycle.lostMode,
      itemCategory: data['itemCategory']?.toString() ?? '',
    );
  }

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  static bool _fieldContains(Object? field, String query) {
    if (field == null) return false;

    if (field is Iterable) {
      return field.any((item) => _fieldContains(item, query));
    }

    return field.toString().toLowerCase().contains(query);
  }

  static bool _matchesNormalisedCategory(
    Object? storedCategory,
    String selectedCategory,
  ) {
    if (storedCategory == null) return false;
    final stored = storedCategory.toString().trim().toLowerCase();
    if (stored.isEmpty) return false;

    final selected = selectedCategory.toLowerCase().trim();
    if (stored == selected) return true;

    const aliases = {
      'children & family': 'family',
      'community & volunteering': 'volunteering',
      'support & wellbeing': 'wellbeing & support',
      'hobbies & interests': 'hobbies',
      'education & skills': 'learning',
      'pets & animals': 'pets',
      'sport & fitness': 'fitness & sport',
      'sport': 'fitness & sport',
      'fitness': 'fitness & sport',
      'youth': 'family',
      'community': 'volunteering',
      'wellbeing': 'wellbeing & support',
    };

    return (aliases[stored] ?? stored) == selected;
  }

  static bool _ageRangeContains(Map<String, dynamic> data, String query) {
    final age = int.tryParse(query.replaceAll(RegExp(r'[^0-9]'), ''));
    if (age == null) return false;

    final minAge = _readInt(data['minimumAge'] ?? data['ageMinimum']);
    final maxAge = _readInt(data['maximumAge'] ?? data['ageMaximum']);
    if (minAge == null && maxAge == null) return false;
    if (minAge != null && age < minAge) return false;
    if (maxAge != null && age > maxAge) return false;
    return true;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }
}
