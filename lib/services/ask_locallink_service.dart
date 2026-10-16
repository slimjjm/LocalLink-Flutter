import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/ask_locallink.dart';

class AskLocalLinkService {
  AskLocalLinkService({FirebaseFunctions? functions, String? region})
    : _region = region ?? 'us-central1',
      _functions =
          functions ??
          FirebaseFunctions.instanceFor(region: region ?? 'us-central1');

  final String _region;
  final FirebaseFunctions _functions;

  Future<AskLocalLinkResponse> search({
    required String query,
    AskLocalLinkQueryContext context = const AskLocalLinkQueryContext(),
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        query,
        'query',
        'Enter something to search for.',
      );
    }

    final payload = {
      'query': trimmed,
      if (context.hasValues) 'context': context.toMap(),
    };
    _debugLogRequest(query: trimmed, context: context, payload: payload);

    final result = await _functions.httpsCallable('askLocalLink').call(payload);

    final data = result.data;
    _debugLogRawResponse(data);
    if (data is! Map) {
      throw StateError('Ask LocalLink returned an unexpected response.');
    }

    final response = AskLocalLinkResponse.fromMap(
      Map<String, dynamic>.from(data),
    );
    _debugLogParsedResponse(response);
    return response;
  }

  void _debugLogRequest({
    required String query,
    required AskLocalLinkQueryContext context,
    required Map<String, Object?> payload,
  }) {
    if (!kDebugMode) return;

    final app = Firebase.app();
    debugPrint(
      'AskLocalLink callable request: '
      'projectId=${app.options.projectId}, '
      'appId=${app.options.appId}, '
      'region=$_region, '
      'query="$query", '
      'contextLocationText="${context.locationText}", '
      'latitude=${context.latitude}, '
      'longitude=${context.longitude}, '
      'radiusMiles=${context.radiusMiles}, '
      'payloadKeys=${payload.keys.join(',')}',
    );
  }

  void _debugLogRawResponse(Object? data) {
    if (!kDebugMode) return;

    if (data is Map) {
      final results = data['results'];
      debugPrint(
        'AskLocalLink raw response: '
        'status=${data['status']}, '
        'intent=${data['intent'] is Map ? (data['intent'] as Map)['intent'] : null}, '
        'category=${data['intent'] is Map ? (data['intent'] as Map)['category'] : null}, '
        'location=${data['intent'] is Map ? (data['intent'] as Map)['location'] : null}, '
        'resultCount=${results is List ? results.length : 'not-list'}',
      );
      if (results is List) {
        for (var index = 0; index < results.length; index += 1) {
          final item = results[index];
          if (item is! Map) continue;
          debugPrint(
            'AskLocalLink raw result[$index]: '
            'type=${item['type']}, '
            'id=${item['id']}, '
            'route=${item['route']}',
          );
        }
      }
    } else {
      debugPrint(
        'AskLocalLink raw response had unexpected type: ${data.runtimeType}',
      );
    }
  }

  void _debugLogParsedResponse(AskLocalLinkResponse response) {
    if (!kDebugMode) return;

    debugPrint(
      'AskLocalLink parsed response: '
      'status=${response.status}, '
      'intent=${response.intent.intent}, '
      'category=${response.intent.category}, '
      'locationText=${response.intent.location?.text ?? ''}, '
      'latitude=${response.intent.location?.latitude}, '
      'longitude=${response.intent.location?.longitude}, '
      'radiusMiles=${response.intent.location?.radiusMiles}, '
      'resultCount=${response.results.length}',
    );
    for (var index = 0; index < response.results.length; index += 1) {
      final result = response.results[index];
      debugPrint(
        'AskLocalLink parsed result[$index]: '
        'type=${result.type}, '
        'id=${result.id}, '
        'route=${result.route}',
      );
    }
  }
}

class AskLocalLinkQueryContext {
  const AskLocalLinkQueryContext({
    this.locationText = '',
    this.latitude,
    this.longitude,
    this.radiusMiles,
  });

  final String locationText;
  final num? latitude;
  final num? longitude;
  final num? radiusMiles;

  bool get hasValues =>
      locationText.trim().isNotEmpty ||
      latitude != null ||
      longitude != null ||
      radiusMiles != null;

  Map<String, Object?> toMap() => {
    if (locationText.trim().isNotEmpty) 'locationText': locationText.trim(),
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    if (radiusMiles != null) 'radiusMiles': radiusMiles,
  };
}
