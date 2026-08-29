import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/config/stripe_config.dart';

void main() {
  group('StripeEnvironmentConfig', () {
    test('allows missing Stripe config in debug without using a live fallback', () {
      final config = StripeEnvironmentConfig.maybeFromEnvironment(
        isDebug: true,
        key: '',
        mode: '',
      );

      expect(config, isNull);
    });

    test('allows missing Stripe config in release without using a fallback', () {
      final config = StripeEnvironmentConfig.maybeFromEnvironment(
        isDebug: false,
        key: '',
        mode: '',
      );

      expect(config, isNull);
    });

    test('rejects mismatched Stripe key and mode', () {
      expect(
        () => StripeEnvironmentConfig.maybeFromEnvironment(
          isDebug: false,
          key: 'pk_live_example',
          mode: 'test',
        ),
        throwsA(isA<StripeConfigurationException>()),
      );
    });

    test('blocks live Stripe mode in debug unless explicitly allowed', () {
      expect(
        () => StripeEnvironmentConfig.maybeFromEnvironment(
          isDebug: true,
          key: 'pk_live_example',
          mode: 'live',
        ),
        throwsA(isA<StripeConfigurationException>()),
      );
    });

    test('accepts an intentional live config outside debug', () {
      final config = StripeEnvironmentConfig.maybeFromEnvironment(
        isDebug: false,
        key: 'pk_live_example',
        mode: 'live',
      );

      expect(config?.mode, StripeRuntimeMode.live);
      expect(config?.publishableKey, 'pk_live_example');
    });
  });
}
