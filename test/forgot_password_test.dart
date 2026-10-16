import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/screens/login_screen.dart';

void main() {
  test('password reset email validation accepts ordinary email addresses', () {
    expect(isValidPasswordResetEmail('  james@example.co.uk  '), isTrue);
  });

  test('password reset email validation rejects invalid email addresses', () {
    expect(isValidPasswordResetEmail('not-an-email'), isFalse);
    expect(isValidPasswordResetEmail('missing-domain@'), isFalse);
  });
}
