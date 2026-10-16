import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/email_action_route.dart';

void main() {
  test('parses Firebase email verification action links', () {
    final route = EmailActionRoute.fromUri(
      Uri.parse(
        'https://locallinkapp.co.uk/?mode=verifyEmail&oobCode=abc123&apiKey=test-key&continueUrl=https%3A%2F%2Flocallinkapp.co.uk&lang=en',
      ),
    );

    expect(route, isNotNull);
    expect(route!.mode, 'verifyEmail');
    expect(route.oobCode, 'abc123');
    expect(route.apiKey, 'test-key');
    expect(route.continueUrl, 'https://locallinkapp.co.uk');
    expect(route.lang, 'en');
    expect(route.isEmailVerification, isTrue);
  });

  test('parses Firebase password reset action links', () {
    final route = EmailActionRoute.fromUri(
      Uri.parse(
        'https://locallinkapp.co.uk/?mode=resetPassword&oobCode=reset123',
      ),
    );

    expect(route, isNotNull);
    expect(route!.mode, 'resetPassword');
    expect(route.oobCode, 'reset123');
    expect(route.isPasswordResetMode, isTrue);
    expect(route.isPasswordReset, isTrue);
    expect(route.isEmailVerification, isFalse);
  });

  test('missing password reset action code is parsed but invalid', () {
    final route = EmailActionRoute.fromUri(
      Uri.parse('https://locallinkapp.co.uk/?mode=resetPassword'),
    );

    expect(route, isNotNull);
    expect(route!.isPasswordResetMode, isTrue);
    expect(route.isPasswordReset, isFalse);
  });

  test('missing verification action code is parsed but invalid', () {
    final route = EmailActionRoute.fromUri(
      Uri.parse('https://locallinkapp.co.uk/?mode=verifyEmail'),
    );

    expect(route, isNotNull);
    expect(route!.isEmailVerification, isFalse);
  });
}
