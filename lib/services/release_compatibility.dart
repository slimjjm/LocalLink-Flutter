class ReleaseCompatibility {
  const ReleaseCompatibility._();
  // Kept in step with pubspec by a regression test; no platform plugin is needed.
  static const version = '18.0.7';
  static const build = 57;
  static const schemas = {
    'discoverySchema': 1,
    'reviewApi': 1,
    'membershipApi': 1,
    'locationSchema': 1,
  };

  static String? blockingReason(Map<String, dynamic>? config) {
    if (config == null || config['ready'] != true) return 'preparing';
    final minimum = config['minimumBuild'];
    if (minimum is! int || minimum < 1) return 'preparing';
    if (minimum > build) return 'update';
    if (schemas.entries.any(
      (entry) =>
          config[entry.key] is! int || (config[entry.key] as int) < entry.value,
    )) {
      return 'preparing';
    }
    return null;
  }
}
