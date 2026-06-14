import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_secrets.dart';

class AddressSearchService {

  Future<List<String>> search(
    String query,
  ) async {

    if (query.trim().isEmpty) {
      return [];
    }

    final url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=$query'
        '&components=country:gb'
        '&key=${AppSecrets.googleApiKey}';

    final response =
        await http.get(
      Uri.parse(url),
    );

    if (response.statusCode != 200) {
      return [];
    }

    final data =
        jsonDecode(response.body);

    final predictions =
        data['predictions'] as List;

    return predictions
        .map<String>(
          (e) => e['description']
              .toString(),
        )
        .toList();
  }
}