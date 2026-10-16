import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/screens/post_service_request_screen.dart';

void main() {
  test('actual cooldown retains the existing 30-minute guidance', () {
    expect(
      communityHelpPublicUpdateFailureMessage(
        FirebaseFunctionsException(
          code: 'resource-exhausted',
          message: 'Please wait',
        ),
      ),
      'Updates can be sent every 30 minutes.',
    );
  });

  for (final code in [
    'unavailable',
    'unauthenticated',
    'permission-denied',
    'not-found',
    'failed-precondition',
    'unknown',
  ]) {
    test('$code never reports a false cooldown', () {
      expect(
        communityHelpPublicUpdateFailureMessage(
          FirebaseFunctionsException(code: code, message: 'Synthetic failure'),
        ),
        "We couldn't share your update. Please try again.",
      );
    });
  }

  test('unexpected failures provide friendly retry guidance', () {
    expect(
      communityHelpPublicUpdateFailureMessage(StateError('Synthetic failure')),
      "We couldn't share your update. Please try again.",
    );
  });
}
