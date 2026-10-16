import 'home_business_discovery_policy.dart';

class CommunityHelpLocation {
  const CommunityHelpLocation._();

  /// Returns the most useful safe, readable location stored on a Community
  /// Help report. Report-specific text must win over a moderator's broad area.
  static String publicLabel(Map<String, dynamic> report) {
    final isModeratorAdded =
        report['communityAdded'] == true ||
        report['createdByModerator'] == true;
    return _firstText([
      report['lastSeenLocation'],
      report['missingLocation'],
      if (isModeratorAdded) report['location'],
      report['locationLabel'],
      report['approximateLocationLabel'],
      if (isModeratorAdded) report['address'],
      report['publicLocation'],
      if (!isModeratorAdded) report['location'],
      if (!isModeratorAdded) report['address'],
      report['areaLabel'],
      report['area'],
    ]);
  }

  static ({double latitude, double longitude})? coordinates(
    Map<String, dynamic> data,
  ) {
    final approximate =
        data.containsKey('approxLatitude') ||
        data.containsKey('approxLongitude');
    double? number(Object? value) => value is num
        ? value.toDouble()
        : value is String
        ? double.tryParse(value.trim())
        : null;
    final latitude = number(data[approximate ? 'approxLatitude' : 'latitude']);
    final longitude = number(
      data[approximate ? 'approxLongitude' : 'longitude'],
    );
    if (!HomeBusinessDiscoveryPolicy.hasValidCoordinates(latitude, longitude)) {
      return null;
    }
    return (
      latitude: approximate
          ? latitude!
          : double.parse(latitude!.toStringAsFixed(2)),
      longitude: approximate
          ? longitude!
          : double.parse(longitude!.toStringAsFixed(2)),
    );
  }

  static String areaFromComponents(List<dynamic> components) {
    for (final kind in [
      'postal_town',
      'locality',
      'sublocality',
      'administrative_area_level_2',
    ]) {
      for (final component in components.whereType<Map>()) {
        if (component['types'] is List &&
            (component['types'] as List).contains(kind)) {
          final value = component['long_name']?.toString().trim() ?? '';
          if (value.isNotEmpty) return value;
        }
      }
    }
    for (final component in components.whereType<Map>()) {
      if (component['types'] is List &&
          (component['types'] as List).contains('postal_code')) {
        return component['long_name'].toString().trim().split(' ').first;
      }
    }
    return 'Selected area';
  }

  static String safeInputLabel(String input) {
    var value = input.trim();
    // Retain the supplied street/area, without automatically publishing a house number.
    value = value.replaceFirst(RegExp(r'^\d+[a-zA-Z]?\s+'), '');
    value = value.replaceAllMapped(
      RegExp(r'\b([A-Z]{1,2}\d[A-Z\d]?)\s*\d[A-Z]{2}\b', caseSensitive: false),
      (match) => match[1]!,
    );
    return value;
  }

  static String _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }
}
