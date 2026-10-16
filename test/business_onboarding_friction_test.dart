import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/screens/business_onboarding_screen.dart';

void main() {
  test('basic business onboarding leaves booking payments unconfigured', () {
    expect(kBusinessOnboardingDefaultPaymentMethods, isEmpty);
    expect(kBusinessOnboardingDefaultStripeRequested, isFalse);
  });

  test(
    'business onboarding no longer asks for payment setup before listing',
    () {
      final source = File(
        'lib/screens/business_onboarding_screen.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('How would you like customers to pay?')));
      expect(source, isNot(contains('Cash Payments')));
      expect(source, isNot(contains('Card Payments')));
      expect(
        source,
        isNot(contains('Choose at least one way customers can pay.')),
      );
    },
  );

  test('business profile separates booking acceptance from payment setup', () {
    final source = File(
      'lib/screens/business_profile_screen.dart',
    ).readAsStringSync();

    expect(source, contains('How customers can book'));
    expect(source, contains('Take bookings through LocalLink'));
    expect(
      source,
      contains(
        'Customers can request appointments or services directly from your page.',
      ),
    );
    expect(source, contains('How customers can pay'));
    expect(source, contains('Bank transfer'));
    expect(source, contains('Connect Stripe'));
    expect(source, contains('Opening Stripe...'));
    expect(source, isNot(contains('Choose at least one payment method.')));
  });
}
