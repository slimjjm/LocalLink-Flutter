import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/config/stripe_config.dart';
import 'package:locallink_flutter/screens/booking_screen.dart';

void main() {
  test('general saved booking address is read from booking preferences', () {
    expect(
      savedGeneralBookingAddressFromPreference({
        'lastAddress': '  48 Market Road  ',
      }),
      '48 Market Road',
    );
  });

  test('saved booking address is read from repeat customer preference', () {
    expect(
      savedBookingAddressFromPreference({'lastAddress': '  12 High Street  '}),
      '12 High Street',
    );
  });

  test('saved general address pre-fills a new business booking first', () {
    expect(
      preferredSavedBookingAddress(
        generalPreference: {'lastAddress': '  48 Market Road  '},
        businessPreference: {'lastAddress': '12 High Street'},
      ),
      '48 Market Road',
    );
  });

  test('business-specific legacy address can be used as fallback', () {
    expect(
      preferredSavedBookingAddress(
        generalPreference: {'lastAddress': ''},
        businessPreference: {'lastAddress': '  12 High Street  '},
      ),
      '12 High Street',
    );
  });

  test('user can edit the pre-filled address used for booking payload', () {
    expect(
      bookingCustomerAddressForPayload('  77 Edited Lane  '),
      '77 Edited Lane',
    );
  });

  test('saved booking address falls back safely when absent', () {
    expect(savedBookingAddressFromPreference(null), isEmpty);
    expect(savedBookingAddressFromPreference({'lastAddress': ''}), isEmpty);
    expect(
      savedBookingAddressFromPreference({'address': 'Other field'}),
      isEmpty,
    );
    expect(
      preferredSavedBookingAddress(
        generalPreference: null,
        businessPreference: null,
      ),
      isEmpty,
    );
  });

  test('PaymentSheet receives backend client secret and return URL', () {
    final parameters = bookingPaymentSheetParametersFromBackend({
      'clientSecret': 'pi_123_secret_456',
      'bookingId': 'booking_1',
      'stripeAccountContext': kStripePaymentAccountContextPlatform,
      'stripeAccountId': null,
    }, enableApplePay: true);

    expect(parameters.paymentIntentClientSecret, 'pi_123_secret_456');
    expect(parameters.merchantDisplayName, 'LocalLink');
    expect(parameters.returnURL, kStripePaymentReturnUrl);
    expect(parameters.applePay?.merchantCountryCode, 'GB');
    expect(parameters.customerId, isNull);
    expect(parameters.customerEphemeralKeySecret, isNull);
    expect(
      stripeAccountIdForPaymentSheet({
        'stripeAccountContext': kStripePaymentAccountContextPlatform,
        'stripeAccountId': null,
      }),
      isNull,
    );
  });

  test('PaymentSheet leaves Apple Pay disabled when not running on iOS', () {
    final parameters = bookingPaymentSheetParametersFromBackend({
      'clientSecret': 'pi_123_secret_456',
      'bookingId': 'booking_1',
      'stripeAccountContext': kStripePaymentAccountContextPlatform,
      'stripeAccountId': null,
    }, enableApplePay: false);

    expect(parameters.applePay, isNull);
  });

  test('Apple Pay merchant identifier is configured for Stripe iOS builds', () {
    expect(kStripeApplePayMerchantIdentifier, 'merchant.co.uk.locallinkapp');
  });

  test('PaymentSheet can use an explicit connected-account context', () {
    expect(
      stripeAccountIdForPaymentSheet({
        'stripeAccountContext': 'connected',
        'stripeAccountId': 'acct_123',
      }),
      'acct_123',
    );
  });

  test('PaymentSheet rejects missing backend client secret', () {
    expect(
      () =>
          bookingPaymentSheetParametersFromBackend({'bookingId': 'booking_1'}),
      throwsA(isA<StripeConfigurationException>()),
    );
  });
}
