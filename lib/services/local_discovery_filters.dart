import 'community_help_lifecycle.dart';

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
      data['category'],
      data['itemCategory'],
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

    return fields.any((field) => _fieldContains(field, value));
  }

  static bool isServiceDiscoverable(Map<String, dynamic> data) {
    return data['isActive'] != false &&
        data['isPublished'] != false &&
        data['isEnabled'] != false &&
        data['moderationStatus'] != 'removed' &&
        data['approvalStatus'] != 'rejected';
  }

  static bool isActivityDiscoverable(
    Map<String, dynamic> data, {
    required DateTime now,
  }) {
    if (data['isActive'] == false) return false;

    final eventDate = CommunityHelpLifecycle.asDateTime(data['eventDate']);
    if (eventDate != null && eventDate.isBefore(now)) return false;

    return true;
  }

  static bool isOpportunityDiscoverable(
    Map<String, dynamic> data, {
    required DateTime now,
  }) {
    return isActivityDiscoverable(data, now: now);
  }

  static bool isCommunityHelpDiscoverable(
    Map<String, dynamic> data, {
    required DateTime now,
  }) {
    return CommunityHelpLifecycle.isActiveForDiscovery(data, now);
  }

  static bool _fieldContains(Object? field, String query) {
    if (field == null) return false;

    if (field is Iterable) {
      return field.any((item) => _fieldContains(item, query));
    }

    return field.toString().toLowerCase().contains(query);
  }
}
