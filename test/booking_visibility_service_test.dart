import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/booking_visibility_service.dart';

void main() {
  test('provider operational booking views exclude unpaid card attempts', () {
    expect(isOperationalBusinessBooking({'status': 'confirmed'}), isTrue);
    expect(
      isOperationalBusinessBooking({'status': 'pending_business_confirmation'}),
      isTrue,
    );
    expect(isOperationalBusinessBooking({'status': 'completed'}), isTrue);

    expect(
      isOperationalBusinessBooking({'status': 'pending_payment'}),
      isFalse,
    );
    expect(
      isOperationalBusinessBooking({'status': 'payment_cancelled'}),
      isFalse,
    );
    expect(isOperationalBusinessBooking({'status': 'payment_failed'}), isFalse);
    expect(
      isOperationalBusinessBooking({'status': 'cancelled_by_system'}),
      isFalse,
    );
  });

  test('past confirmed bookings display as awaiting completion history', () {
    final now = DateTime(2026, 9, 7, 12);
    final booking = {
      'status': 'confirmed',
      'startDate': Timestamp.fromDate(DateTime(2026, 9, 7, 10)),
      'endDate': Timestamp.fromDate(DateTime(2026, 9, 7, 11)),
    };

    expect(isPastConfirmedBooking(booking, now), isTrue);
    expect(
      bookingDisplayStatus(booking, now),
      bookingDisplayStatusAwaitingCompletion,
    );
    expect(isActiveCustomerBooking(booking, now), isFalse);
    expect(canCancelBookingFromUi(booking, now), isFalse);
    expect(canCompleteBookingFromUi(booking), isTrue);
  });

  test('future confirmed bookings remain upcoming and cancellable', () {
    final now = DateTime(2026, 9, 7, 12);
    final booking = {
      'status': 'confirmed',
      'startDate': Timestamp.fromDate(DateTime(2026, 9, 7, 14)),
      'endDate': Timestamp.fromDate(DateTime(2026, 9, 7, 15)),
    };

    expect(isActiveCustomerBooking(booking, now), isTrue);
    expect(bookingDisplayStatus(booking, now), 'confirmed');
    expect(canCancelBookingFromUi(booking, now), isTrue);
  });

  test('availability remains usable until its end time passes', () {
    final now = DateTime(2026, 9, 6, 20);

    expect(
      isAvailabilityUsable({
        'availabilityAt': Timestamp.fromDate(DateTime(2026, 9, 6, 19, 50)),
        'endTime': Timestamp.fromDate(DateTime(2026, 9, 6, 20, 35)),
      }, now),
      isTrue,
    );
  });

  test('availability is unusable after its usable end time', () {
    final now = DateTime(2026, 9, 6, 21);

    expect(
      isAvailabilityUsable({
        'availabilityAt': Timestamp.fromDate(DateTime(2026, 9, 6, 19, 50)),
        'endTime': Timestamp.fromDate(DateTime(2026, 9, 6, 20, 35)),
      }, now),
      isFalse,
    );
  });
}
