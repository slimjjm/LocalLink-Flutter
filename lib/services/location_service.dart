import 'package:geolocator/geolocator.dart';

import 'home_business_discovery_policy.dart';

class LocationService {
  Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        return null;
      }

      permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition();
      return HomeBusinessDiscoveryPolicy.hasValidCoordinates(
            position.latitude,
            position.longitude,
          )
          ? position
          : null;
    } catch (_) {
      return null;
    }
  }
}
