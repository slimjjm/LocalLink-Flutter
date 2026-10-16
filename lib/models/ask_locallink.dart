class AskLocalLinkIntent {
  const AskLocalLinkIntent({
    required this.intent,
    required this.searchText,
    required this.category,
    required this.serviceType,
    required this.requiresAvailability,
    required this.audience,
    required this.sort,
    required this.confidence,
    this.dateRange,
    this.timeRange,
    this.location,
    this.age,
  });

  final String intent;
  final String searchText;
  final String category;
  final String serviceType;
  final AskLocalLinkDateRange? dateRange;
  final AskLocalLinkTimeRange? timeRange;
  final AskLocalLinkLocation? location;
  final bool requiresAvailability;
  final String audience;
  final num? age;
  final String sort;
  final num confidence;

  factory AskLocalLinkIntent.fromMap(Map<String, dynamic> data) {
    return AskLocalLinkIntent(
      intent: _text(data['intent'], fallback: 'unknown'),
      searchText: _text(data['searchText']),
      category: _text(data['category']),
      serviceType: _text(data['serviceType']),
      dateRange: data['dateRange'] is Map
          ? AskLocalLinkDateRange.fromMap(
              Map<String, dynamic>.from(data['dateRange'] as Map),
            )
          : null,
      timeRange: data['timeRange'] is Map
          ? AskLocalLinkTimeRange.fromMap(
              Map<String, dynamic>.from(data['timeRange'] as Map),
            )
          : null,
      location: data['location'] is Map
          ? AskLocalLinkLocation.fromMap(
              Map<String, dynamic>.from(data['location'] as Map),
            )
          : null,
      requiresAvailability: data['requiresAvailability'] == true,
      audience: _text(data['audience']),
      age: data['age'] is num ? data['age'] as num : null,
      sort: _text(data['sort'], fallback: 'relevance'),
      confidence: data['confidence'] is num ? data['confidence'] as num : 0,
    );
  }
}

class AskLocalLinkDateRange {
  const AskLocalLinkDateRange({required this.start, required this.end});

  final String start;
  final String end;

  factory AskLocalLinkDateRange.fromMap(Map<String, dynamic> data) {
    return AskLocalLinkDateRange(
      start: _text(data['start']),
      end: _text(data['end']),
    );
  }
}

class AskLocalLinkTimeRange {
  const AskLocalLinkTimeRange({required this.start, required this.end});

  final String start;
  final String end;

  factory AskLocalLinkTimeRange.fromMap(Map<String, dynamic> data) {
    return AskLocalLinkTimeRange(
      start: _text(data['start']),
      end: _text(data['end']),
    );
  }
}

class AskLocalLinkLocation {
  const AskLocalLinkLocation({
    required this.text,
    this.latitude,
    this.longitude,
    this.radiusMiles,
  });

  final String text;
  final num? latitude;
  final num? longitude;
  final num? radiusMiles;

  factory AskLocalLinkLocation.fromMap(Map<String, dynamic> data) {
    return AskLocalLinkLocation(
      text: _text(data['text']),
      latitude: data['latitude'] is num ? data['latitude'] as num : null,
      longitude: data['longitude'] is num ? data['longitude'] as num : null,
      radiusMiles: data['radiusMiles'] is num
          ? data['radiusMiles'] as num
          : null,
    );
  }
}

class AskLocalLinkResult {
  const AskLocalLinkResult({
    required this.type,
    required this.id,
    required this.parentId,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.metadata,
    this.distanceMiles,
    this.dateTime,
  });

  final String type;
  final String id;
  final String parentId;
  final String title;
  final String subtitle;
  final num? distanceMiles;
  final String? dateTime;
  final String route;
  final Map<String, dynamic> metadata;

  bool get isAction => type == 'action';

  String get actionIntent {
    final raw = metadata['actionIntent']?.toString().trim() ?? '';
    return raw.isEmpty ? id : raw;
  }

  factory AskLocalLinkResult.fromMap(Map<String, dynamic> data) {
    return AskLocalLinkResult(
      type: _text(data['type']),
      id: _text(data['id']),
      parentId: _text(data['parentId']),
      title: _text(data['title']),
      subtitle: _text(data['subtitle']),
      distanceMiles: data['distanceMiles'] is num
          ? data['distanceMiles'] as num
          : null,
      dateTime: data['dateTime'] == null ? null : _text(data['dateTime']),
      route: _text(data['route']),
      metadata: data['metadata'] is Map
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : const {},
    );
  }
}

class AskLocalLinkResponse {
  const AskLocalLinkResponse({
    required this.intent,
    required this.results,
    required this.status,
  });

  final AskLocalLinkIntent intent;
  final List<AskLocalLinkResult> results;
  final String status;

  bool get isUnknown => status == 'unknown' || intent.intent == 'unknown';
  bool get hasResults => results.isNotEmpty;

  factory AskLocalLinkResponse.fromMap(Map<String, dynamic> data) {
    final rawResults = data['results'];
    return AskLocalLinkResponse(
      intent: AskLocalLinkIntent.fromMap(
        data['intent'] is Map
            ? Map<String, dynamic>.from(data['intent'] as Map)
            : const {'intent': 'unknown'},
      ),
      results: rawResults is List
          ? rawResults
                .whereType<Map>()
                .map(
                  (item) => AskLocalLinkResult.fromMap(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      status: _text(data['status'], fallback: 'unknown'),
    );
  }
}

String _text(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}
