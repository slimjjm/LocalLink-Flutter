import 'package:geolocator/geolocator.dart';

double calculateDistanceMiles({
  required double startLat,
  required double startLng,
  required double endLat,
  required double endLng,
}) {

  final meters = Geolocator.distanceBetween(
    startLat,
    startLng,
    endLat,
    endLng,
  );

  return meters / 1609.34;
}