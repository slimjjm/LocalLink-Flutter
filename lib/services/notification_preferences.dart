class NotificationPreferences {
  static const documentPath = 'preferences/notifications';

  static const communityResponses = 'communityResponses';
  static const communityMessages = 'communityMessages';
  static const communityFollowing = 'communityFollowing';
  static const nearbyCommunityAlerts = 'nearbyCommunityAlerts';
  static const activityUpdates = 'activityUpdates';
  static const serviceBookingUpdates = 'serviceBookingUpdates';
  static const reminders = 'reminders';
  static const localDiscovery = 'localDiscovery';
  // Legacy key kept so older preference documents continue to read safely.
  static const communityAlertsNearby = 'communityAlertsNearby';

  static const defaults = <String, bool>{
    communityResponses: true,
    communityMessages: true,
    communityFollowing: true,
    nearbyCommunityAlerts: true,
    activityUpdates: true,
    serviceBookingUpdates: true,
    reminders: true,
    localDiscovery: false,
    communityAlertsNearby: false,
  };

  static Map<String, bool> fromData(Map<String, dynamic>? data) {
    return {
      for (final entry in defaults.entries)
        entry.key: data?[entry.key] is bool
            ? data![entry.key] as bool
            : entry.value,
    };
  }
}
