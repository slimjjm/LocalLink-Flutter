import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_secrets.dart';
import '../models/address_result.dart';
import 'community_help_location.dart';

class AddressSearchService {
  Future<List<AddressResult>> search(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final url = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': query,
        'components': 'country:gb',
        'key': AppSecrets.googleApiKey,
      },
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      return [];
    }

    final data = jsonDecode(response.body);

    final predictions = data['predictions'] as List? ?? [];

    return predictions
        .map<AddressResult>(
          (e) => AddressResult(
            description: e['description'],
            placeId: e['place_id'],
          ),
        )
        .toList();
  }

  Future<String> getPublicAreaLabel(String placeId) async {
    final url =
        Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
          'place_id': placeId,
          'fields': 'address_components',
          'key': AppSecrets.googleApiKey,
        });
    final response = await http.get(url);
    if (response.statusCode != 200) return 'Selected area';
    final data = jsonDecode(response.body);
    final components = data['result']?['address_components'];
    return CommunityHelpLocation.areaFromComponents(
      components is List ? components : [],
    );
  }

  Future<Map<String, double>?> getCoordinates(String placeId) async {
    final url = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'fields': 'geometry',
        'key': AppSecrets.googleApiKey,
      },
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      return null;
    }

    final data = jsonDecode(response.body);

    final location = data['result']['geometry']['location'];

    return {
      'lat': location['lat'].toDouble(),
      'lng': location['lng'].toDouble(),
    };
  }
}
