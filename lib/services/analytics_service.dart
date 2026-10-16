import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class LocalLinkAnalytics {
  LocalLinkAnalytics._();

  static final LocalLinkAnalytics instance = LocalLinkAnalytics._();

  FirebaseAnalytics? _analyticsOverride;

  @visibleForTesting
  set analyticsOverride(FirebaseAnalytics? analytics) {
    _analyticsOverride = analytics;
  }

  FirebaseAnalytics? get _analytics {
    if (Firebase.apps.isEmpty) return null;
    return _analyticsOverride ?? FirebaseAnalytics.instance;
  }

  String get platform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'other';
    }
  }

  String get authenticatedState {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return 'guest';
    return 'signed_in';
  }

  Future<void> updateUserProperties({User? user}) async {
    final analytics = _analytics;
    if (analytics == null) return;

    final authState = user == null || user.isAnonymous ? 'guest' : 'signed_in';
    await _ignoreErrors(() async {
      await analytics.setUserProperty(
        name: 'authenticated_state',
        value: authState,
      );
      await analytics.setUserProperty(name: 'platform', value: platform);
    });
  }

  Future<void> logLogin({required String method}) async {
    final analytics = _analytics;
    if (analytics == null) return;
    await _ignoreErrors(
      () => analytics.logLogin(loginMethod: _safeValue(method)),
    );
    await updateUserProperties(user: FirebaseAuth.instance.currentUser);
  }

  Future<void> logSignUp({required String method}) async {
    final analytics = _analytics;
    if (analytics == null) return;
    await _ignoreErrors(
      () => analytics.logSignUp(signUpMethod: _safeValue(method)),
    );
    await updateUserProperties(user: FirebaseAuth.instance.currentUser);
  }

  Future<void> askLocalLinkSearch({
    required String intentType,
    required int resultCount,
  }) {
    return logEvent('ask_locallink_search', {
      'intent_type': _safeValue(intentType),
      'result_count': resultCount,
      'has_results': resultCount > 0 ? 1 : 0,
    });
  }

  Future<void> askLocalLinkResultOpened({
    required String resultType,
    required int resultPosition,
    required String intentType,
  }) {
    return logEvent('ask_locallink_result_opened', {
      'result_type': _safeValue(resultType),
      'result_position': resultPosition,
      'intent_type': _safeValue(intentType),
    });
  }

  Future<void> askLocalLinkActionSuggested({required String actionIntent}) {
    return logEvent('ask_locallink_action_suggested', {
      'action_intent': _safeValue(actionIntent),
    });
  }

  Future<void> askLocalLinkActionOpened({required String actionIntent}) {
    return logEvent('ask_locallink_action_opened', {
      'action_intent': _safeValue(actionIntent),
    });
  }

  Future<void> discoveryView({
    required String eventName,
    required String source,
    String category = '',
  }) {
    return logEvent(eventName, {
      'source': _safeValue(source),
      if (category.trim().isNotEmpty) 'category': _safeValue(category),
    });
  }

  Future<void> businessSaved({required String source, String category = ''}) {
    return logEvent('business_saved', {
      'source': _safeValue(source),
      if (category.trim().isNotEmpty) 'category': _safeValue(category),
    });
  }

  Future<void> activitySaved({required String source, String category = ''}) {
    return logEvent('activity_saved', {
      'source': _safeValue(source),
      if (category.trim().isNotEmpty) 'category': _safeValue(category),
    });
  }

  Future<void> challengeViewed({
    required String challengeId,
    String category = '',
    String location = '',
    String supportedBusinessId = '',
  }) {
    return _challengeEvent(
      'challenge_viewed',
      challengeId: challengeId,
      category: category,
      location: location,
      supportedBusinessId: supportedBusinessId,
    );
  }

  Future<void> challengeEntrySubmitted({
    required String challengeId,
    String category = '',
    String location = '',
    String supportedBusinessId = '',
  }) {
    return _challengeEvent(
      'challenge_entry_submitted',
      challengeId: challengeId,
      category: category,
      location: location,
      supportedBusinessId: supportedBusinessId,
    );
  }

  Future<void> challengeShared({
    required String challengeId,
    String category = '',
    String location = '',
    String supportedBusinessId = '',
  }) {
    return _challengeEvent(
      'challenge_shared',
      challengeId: challengeId,
      category: category,
      location: location,
      supportedBusinessId: supportedBusinessId,
    );
  }

  Future<void> challengeSupportedBusinessOpened({
    required String challengeId,
    required String supportedBusinessId,
    String category = '',
    String location = '',
  }) {
    return _challengeEvent(
      'challenge_supported_business_opened',
      challengeId: challengeId,
      category: category,
      location: location,
      supportedBusinessId: supportedBusinessId,
    );
  }

  Future<void> messageStarted({required String source, String type = ''}) {
    return logEvent('message_started', {
      'source': _safeValue(source),
      if (type.trim().isNotEmpty) 'message_type': _safeValue(type),
    });
  }

  Future<void> bookingStarted({
    required String source,
    required String paymentMethod,
    String businessCategory = '',
  }) {
    return logEvent('booking_started', {
      'source': _safeValue(source),
      'payment_method': _safeValue(paymentMethod),
      if (businessCategory.trim().isNotEmpty)
        'business_category': _safeValue(businessCategory),
    });
  }

  Future<void> bookingCompleted({
    required String source,
    required String paymentMethod,
    String businessCategory = '',
  }) {
    return logEvent('booking_completed', {
      'source': _safeValue(source),
      'payment_method': _safeValue(paymentMethod),
      if (businessCategory.trim().isNotEmpty)
        'business_category': _safeValue(businessCategory),
    });
  }

  Future<void> bookingCancelled({required String source}) {
    return logEvent('booking_cancelled', {'source': _safeValue(source)});
  }

  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    final analytics = _analytics;
    if (analytics == null) return;

    final safeParameters = <String, Object>{
      'platform': platform,
      'authenticated_state': authenticatedState,
    };
    parameters.forEach((key, value) {
      safeParameters[key] = value is String ? _safeValue(value) : value;
    });

    await _ignoreErrors(
      () => analytics.logEvent(name: name, parameters: safeParameters),
    );
  }

  Future<void> _challengeEvent(
    String name, {
    required String challengeId,
    String category = '',
    String location = '',
    String supportedBusinessId = '',
  }) {
    return logEvent(name, {
      'challenge_id': _safeValue(challengeId),
      if (category.trim().isNotEmpty) 'category': _safeValue(category),
      if (location.trim().isNotEmpty) 'location': _safeValue(location),
      if (supportedBusinessId.trim().isNotEmpty)
        'supported_business_id': _safeValue(supportedBusinessId),
    });
  }

  Future<void> _ignoreErrors(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Analytics should never block or change product behavior.
    }
  }

  String _safeValue(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_]+'),
      '_',
    );
    if (normalized.isEmpty) return 'unknown';
    return normalized.length <= 100 ? normalized : normalized.substring(0, 100);
  }
}
