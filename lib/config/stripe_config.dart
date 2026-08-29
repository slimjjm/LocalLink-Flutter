import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

enum StripeRuntimeMode {
  test,
  live,
}

class StripeConfigurationException implements Exception {
  final String message;

  const StripeConfigurationException(this.message);

  @override
  String toString() => message;
}

class StripeEnvironmentConfig {
  final String publishableKey;
  final StripeRuntimeMode mode;

  const StripeEnvironmentConfig({
    required this.publishableKey,
    required this.mode,
  });

  static const _key = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
  static const _mode = String.fromEnvironment('STRIPE_MODE');
  static const _allowLiveInDebug = bool.fromEnvironment(
    'STRIPE_ALLOW_LIVE_IN_DEBUG',
  );

  bool get isLive => mode == StripeRuntimeMode.live;

  static StripeEnvironmentConfig? maybeFromEnvironment({
    bool isDebug = kDebugMode,
    String key = _key,
    String mode = _mode,
    bool allowLiveInDebug = _allowLiveInDebug,
  }) {
    final normalisedKey = key.trim();
    final normalisedMode = mode.trim().toLowerCase();

    if (normalisedKey.isEmpty || normalisedMode.isEmpty) {
      debugPrint(
        'Stripe is not configured for this build. '
        'Pass STRIPE_PUBLISHABLE_KEY and STRIPE_MODE to enable card payments.',
      );
      return null;
    }

    final configuredMode = switch (normalisedMode) {
      'test' => StripeRuntimeMode.test,
      'live' => StripeRuntimeMode.live,
      _ => throw const StripeConfigurationException(
          'Invalid STRIPE_MODE. Use test or live.',
        ),
    };

    final keyMode = _modeForPublishableKey(normalisedKey);
    if (keyMode == null) {
      throw const StripeConfigurationException(
        'Stripe publishable key must start with pk_test_ or pk_live_.',
      );
    }

    if (keyMode != configuredMode) {
      throw StripeConfigurationException(
        'Stripe publishable key does not match STRIPE_MODE=$normalisedMode.',
      );
    }

    if (isDebug && configuredMode == StripeRuntimeMode.live && !allowLiveInDebug) {
      throw const StripeConfigurationException(
        'Live Stripe mode is blocked in debug builds. Use STRIPE_MODE=test, '
        'or pass STRIPE_ALLOW_LIVE_IN_DEBUG=true only for an intentional '
        'live-mode test.',
      );
    }

    return StripeEnvironmentConfig(
      publishableKey: normalisedKey,
      mode: configuredMode,
    );
  }

  static StripeRuntimeMode? _modeForPublishableKey(String key) {
    if (key.startsWith('pk_test_')) return StripeRuntimeMode.test;
    if (key.startsWith('pk_live_')) return StripeRuntimeMode.live;
    return null;
  }
}

Future<StripeEnvironmentConfig?> configureStripeForApp() async {
  final config = StripeEnvironmentConfig.maybeFromEnvironment();
  if (config == null) return null;

  Stripe.publishableKey = config.publishableKey;
  await Stripe.instance.applySettings();

  if (kDebugMode) {
    debugPrint('Stripe configured in ${config.mode.name} mode.');
  }

  return config;
}
