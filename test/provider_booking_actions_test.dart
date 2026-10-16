import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('provider booking screens use backend booking lifecycle callables', () {
    final listScreen = File(
      'lib/screens/business_bookings_screen.dart',
    ).readAsStringSync();
    final detailScreen = File(
      'lib/screens/business_booking_detail_screen.dart',
    ).readAsStringSync();

    expect(listScreen, contains('httpsCallable'));
    expect(listScreen, contains("'cancelBooking'"));
    expect(listScreen, contains("'completeBooking'"));
    expect(detailScreen, contains('httpsCallable'));
    expect(detailScreen, contains("'cancelBooking'"));
    expect(detailScreen, contains("'completeBooking'"));

    expect(listScreen, isNot(contains("status': 'cancelled_by_business'")));
    expect(listScreen, isNot(contains("status': 'completed'")));
    expect(detailScreen, isNot(contains("status': 'cancelled_by_business'")));
    expect(detailScreen, isNot(contains("status': 'completed'")));
  });

  test(
    'booking participants cannot directly change protected booking status',
    () {
      final rules = File('firestore.rules').readAsStringSync();

      expect(
        rules,
        contains("changed.hasOnly(['unreadForCustomer', 'unreadForBusiness'])"),
      );
      expect(
        rules,
        isNot(
          contains(
            "request.resource.data.status in ['completed', 'cancelled_by_business']",
          ),
        ),
      );
    },
  );
}
