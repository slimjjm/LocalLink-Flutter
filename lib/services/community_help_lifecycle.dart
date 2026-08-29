import 'dart:math' as math;

class CommunityHelpLifecycle {
  static const lostExpiry = Duration(days: 7);
  static const foundExpiry = Duration(days: 14);
  static const freeItemExpiry = Duration(days: 3);
  static const expiryWarningLeadTime = Duration(hours: 24);

  static const activeStatus = 'active';
  static const resolvedStatus = 'resolved';
  static const expiredStatus = 'expired';

  static const lostMode = 'lost';
  static const foundMode = 'found';
  static const wantedMode = 'wanted';
  static const offeringMode = 'offering';

  static const petCategory = 'Pet';

  static Duration expiryDuration({
    required String type,
    required String mode,
    required String itemCategory,
  }) {
    if (type == 'free_item') return freeItemExpiry;
    if (mode == foundMode) return foundExpiry;
    return lostExpiry;
  }

  static double defaultDiscoveryRadiusMiles({
    required String type,
    required String mode,
    required String itemCategory,
  }) {
    if (type == 'free_item' || mode == offeringMode || mode == wantedMode) {
      return 5;
    }
    if (itemCategory == petCategory) return 10;
    if (itemCategory == 'Keys' ||
        itemCategory == 'Wallet' ||
        itemCategory == 'Phone') {
      return 3;
    }
    return 5;
  }

  static DateTime expiresAt({
    required DateTime now,
    required String type,
    required String mode,
    required String itemCategory,
  }) {
    return now.add(
      expiryDuration(type: type, mode: mode, itemCategory: itemCategory),
    );
  }

  static DateTime expiryReminderAt(DateTime expiresAt) {
    return expiresAt.subtract(expiryWarningLeadTime);
  }

  static bool isLegacyActiveStatus(String status) {
    return status == activeStatus ||
        status == 'open' ||
        status == 'missing' ||
        status == 'looking_for_owner';
  }

  static bool isExpired(Map<String, dynamic> data, DateTime now) {
    final status = (data['status'] as String?) ?? activeStatus;
    if (status == expiredStatus) return true;
    if (status == resolvedStatus ||
        status == 'reunited' ||
        status == 'returned') {
      return false;
    }

    final expiresAt = asDateTime(data['expiresAt']);
    if (expiresAt == null) return false;
    return !expiresAt.isAfter(now);
  }

  static bool isResolved(Map<String, dynamic> data) {
    final status = (data['status'] as String?) ?? activeStatus;
    return status == resolvedStatus ||
        status == 'reunited' ||
        status == 'returned' ||
        data['resolvedAt'] != null;
  }

  static bool isActiveForDiscovery(Map<String, dynamic> data, DateTime now) {
    final isActive = data['isActive'] != false;
    final status = (data['status'] as String?) ?? activeStatus;
    return isActive &&
        isLegacyActiveStatus(status) &&
        !isResolved(data) &&
        !isExpired(data, now);
  }

  static String lifecycleKind({
    required String type,
    required String mode,
    required String itemCategory,
  }) {
    if (type == 'free_item') return 'free_item';
    if (mode == foundMode) return 'found_object';
    if (itemCategory == petCategory) return 'lost_pet';
    return 'lost_object';
  }

  static String resolveReason({
    required String type,
    required String mode,
    required String itemCategory,
    bool freeItemWanted = false,
  }) {
    if (type == 'free_item') {
      return freeItemWanted ? 'no_longer_needed' : 'collected';
    }
    if (mode == foundMode) return 'returned';
    if (itemCategory == petCategory) return 'reunited';
    return 'found';
  }

  static String resolveActionLabel({
    required String type,
    required String mode,
    required String itemCategory,
  }) {
    if (type == 'free_item') {
      return mode == wantedMode ? 'No longer needed' : 'Mark as collected';
    }
    if (mode == foundMode) return 'Returned to owner';
    if (itemCategory == petCategory) return 'Pet reunited';
    return 'I found it';
  }

  static String friendlyStatus(Map<String, dynamic> data, DateTime now) {
    if (isExpired(data, now)) return 'Expired';
    if (isResolved(data)) {
      final reason = data['resolvedReason'] as String?;
      switch (reason) {
        case 'returned':
          return 'Returned';
        case 'collected':
          return 'Collected';
        case 'no_longer_needed':
          return 'No longer needed';
        case 'reunited':
          return 'Reunited';
        default:
          return 'Found';
      }
    }

    final type = data['type'] as String? ?? 'lost_found';
    final mode = data['mode'] as String? ?? lostMode;
    if (type == 'free_item') {
      return mode == wantedMode ? 'Wanted' : 'Available';
    }
    if (mode == foundMode) return 'Looking for owner';
    return 'Missing';
  }

  static String responseActionLabel(Map<String, dynamic> data) {
    final mode = data['mode'] as String? ?? lostMode;
    final category = data['itemCategory'] as String? ?? '';
    if (mode == foundMode && category == petCategory) {
      return 'I know this pet / owner';
    }
    if (mode == foundMode) return 'I think this is mine';
    return 'I may have seen this';
  }

  static List<String> keywordsFor(String text) {
    final words =
        text
            .toLowerCase()
            .split(RegExp('[^a-z0-9]+'))
            .where((word) => word.length > 2)
            .toSet()
            .toList()
          ..sort();
    return words.take(24).toList();
  }

  static DateTime? asDateTime(Object? value) {
    if (value is DateTime) return value;
    try {
      final dynamic maybeTimestamp = value;
      final dynamic converted = maybeTimestamp?.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      return null;
    }
    return null;
  }

  static bool canMutate({
    required String? currentUserId,
    required Map<String, dynamic> post,
  }) {
    return currentUserId != null &&
        currentUserId.isNotEmpty &&
        post['createdBy'] == currentUserId;
  }

  static bool shouldMatch(
    Map<String, dynamic> current,
    Map<String, dynamic> candidate,
    DateTime now,
  ) {
    if (!isActiveForDiscovery(current, now) ||
        !isActiveForDiscovery(candidate, now)) {
      return false;
    }
    if ((current['type'] as String? ?? '') != 'lost_found' ||
        (candidate['type'] as String? ?? '') != 'lost_found') {
      return false;
    }
    if ((current['mode'] as String? ?? '') ==
        (candidate['mode'] as String? ?? '')) {
      return false;
    }
    if ((current['itemCategory'] as String? ?? '') !=
        (candidate['itemCategory'] as String? ?? '')) {
      return false;
    }

    final distance = distanceMiles(current, candidate);
    if (distance != null) {
      final currentRadius = asDouble(current['discoveryRadiusMiles']) ?? 5;
      final candidateRadius = asDouble(candidate['discoveryRadiusMiles']) ?? 5;
      return distance <= currentRadius || distance <= candidateRadius;
    }

    return keywordOverlap(current, candidate) > 0 ||
        areaOverlap(current, candidate);
  }

  static double? distanceMiles(
    Map<String, dynamic> current,
    Map<String, dynamic> candidate,
  ) {
    final currentLat = asDouble(current['approxLatitude']);
    final currentLng = asDouble(current['approxLongitude']);
    final candidateLat = asDouble(candidate['approxLatitude']);
    final candidateLng = asDouble(candidate['approxLongitude']);
    if (currentLat == null ||
        currentLng == null ||
        candidateLat == null ||
        candidateLng == null) {
      return null;
    }
    return _haversineMiles(currentLat, currentLng, candidateLat, candidateLng);
  }

  static bool areaOverlap(
    Map<String, dynamic> current,
    Map<String, dynamic> candidate,
  ) {
    final currentPlace = (current['publicLocation'] as String? ?? '')
        .trim()
        .toLowerCase();
    final candidatePlace = (candidate['publicLocation'] as String? ?? '')
        .trim()
        .toLowerCase();
    return currentPlace.isNotEmpty &&
        candidatePlace.isNotEmpty &&
        (currentPlace.contains(candidatePlace) ||
            candidatePlace.contains(currentPlace));
  }

  static int keywordOverlap(
    Map<String, dynamic> current,
    Map<String, dynamic> candidate,
  ) {
    final currentWords = ((current['keywords'] as List?) ?? const [])
        .whereType<String>()
        .toSet();
    final candidateWords = ((candidate['keywords'] as List?) ?? const [])
        .whereType<String>()
        .toSet();
    return currentWords.intersection(candidateWords).length;
  }

  static double? asDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return null;
  }

  static double _haversineMiles(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    const earthRadiusMiles = 3958.8;
    final dLat = _degreesToRadians(endLat - startLat);
    final dLng = _degreesToRadians(endLng - startLng);
    final lat1 = _degreesToRadians(startLat);
    final lat2 = _degreesToRadians(endLat);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMiles * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  static Map<String, dynamic> messagingIntent({
    required String postId,
    required Map<String, dynamic> post,
    required String responderId,
    required String responderName,
    required String message,
  }) {
    return {
      'postId': postId,
      'postOwnerId': post['createdBy'],
      'responderId': responderId,
      'responderName': responderName,
      'message': message.trim(),
      'status': 'open',
    };
  }
}
