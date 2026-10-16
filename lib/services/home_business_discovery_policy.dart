import 'dart:math' as math;

class HomeBusinessDiscoveryPolicy {
  const HomeBusinessDiscoveryPolicy._();

  static const double initialRadiusMiles = 15;
  static const double expandedRadiusMiles = 25;
  static const double maximumRadiusMiles = 40;
  static const int targetBusinessCount = 3;
  static const double _metersPerMile = 1609.344;

  static double selectedRadiusMiles(
    Iterable<double?> businessDistancesMiles, {
    int targetCount = targetBusinessCount,
  }) {
    final distances = businessDistancesMiles
        .whereType<double>()
        .where((distance) => distance.isFinite && distance >= 0)
        .toList();

    if (_countWithin(distances, initialRadiusMiles) >= targetCount) {
      return initialRadiusMiles;
    }

    if (_countWithin(distances, expandedRadiusMiles) >= targetCount) {
      return expandedRadiusMiles;
    }

    return maximumRadiusMiles;
  }

  static bool isWithinRadius({
    required double? distanceMiles,
    required double radiusMiles,
  }) {
    return distanceMiles != null &&
        distanceMiles.isFinite &&
        distanceMiles >= 0 &&
        distanceMiles <= radiusMiles;
  }

  static bool hasValidCoordinates(num? latitude, num? longitude) {
    if (latitude == null || longitude == null) return false;
    final lat = latitude.toDouble();
    final lng = longitude.toDouble();
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
    return !(lat.abs() < 0.000001 && lng.abs() < 0.000001);
  }

  static double? distanceMilesBetween({
    required num? startLatitude,
    required num? startLongitude,
    required num? endLatitude,
    required num? endLongitude,
  }) {
    if (!hasValidCoordinates(startLatitude, startLongitude) ||
        !hasValidCoordinates(endLatitude, endLongitude)) {
      return null;
    }

    final startLat = startLatitude!.toDouble();
    final startLng = startLongitude!.toDouble();
    final endLat = endLatitude!.toDouble();
    final endLng = endLongitude!.toDouble();
    const radiansPerDegree = math.pi / 180;
    final deltaLat = (endLat - startLat) * radiansPerDegree;
    final deltaLng = (endLng - startLng) * radiansPerDegree;
    final startLatRad = startLat * radiansPerDegree;
    final endLatRad = endLat * radiansPerDegree;
    final a =
        _sinSquared(deltaLat / 2) +
        math.cos(startLatRad) * math.cos(endLatRad) * _sinSquared(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return 6371000 * c / _metersPerMile;
  }

  static bool hasMeaningfulLocationChange({
    required num? previousLatitude,
    required num? previousLongitude,
    required num? nextLatitude,
    required num? nextLongitude,
    double thresholdMiles = 0.25,
  }) {
    final distanceMiles = distanceMilesBetween(
      startLatitude: previousLatitude,
      startLongitude: previousLongitude,
      endLatitude: nextLatitude,
      endLongitude: nextLongitude,
    );
    return distanceMiles == null || distanceMiles >= thresholdMiles;
  }

  static int _countWithin(Iterable<double> distances, double radiusMiles) {
    return distances.where((distance) => distance <= radiusMiles).length;
  }

  static double _sinSquared(double value) {
    final sin = math.sin(value);
    return sin * sin;
  }
}
