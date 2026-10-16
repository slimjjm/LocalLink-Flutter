import 'home_business_discovery_policy.dart';

class BusinessLocationUpdate {
  const BusinessLocationUpdate._();

  static Map<String, dynamic> build({
    required String originalAddress,
    required String address,
    String? selectedAddress,
    double? latitude,
    double? longitude,
  }) {
    final next = address.trim();
    if (next == originalAddress.trim()) return {'address': next};
    if (next.isEmpty ||
        selectedAddress?.trim() != next ||
        !HomeBusinessDiscoveryPolicy.hasValidCoordinates(latitude, longitude)) {
      throw StateError(
        'Choose your updated address from the suggestions so its map location is correct.',
      );
    }
    return {
      'address': next,
      'latitude': latitude,
      'longitude': longitude,
      'locationAddress': next,
    };
  }
}
