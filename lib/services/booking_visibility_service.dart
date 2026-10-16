import 'package:cloud_firestore/cloud_firestore.dart';

const Set<String> operationalBusinessBookingStatuses = {
  'confirmed',
  'pending_business_confirmation',
  'completed',
};

const String bookingDisplayStatusAwaitingCompletion = 'awaiting_completion';

bool isOperationalBusinessBooking(Map<String, dynamic> booking) {
  return operationalBusinessBookingStatuses.contains(
    booking['status']?.toString(),
  );
}

DateTime? availabilityUsableEnd(Map<String, dynamic> post) {
  final value =
      post['endDateTime'] ??
      post['endTime'] ??
      post['availableUntil'] ??
      post['startDateTime'] ??
      post['startTime'] ??
      post['availabilityAt'];

  return value is Timestamp ? value.toDate() : null;
}

bool isAvailabilityUsable(Map<String, dynamic> post, DateTime now) {
  final usableEnd = availabilityUsableEnd(post);
  return usableEnd == null || usableEnd.isAfter(now);
}

DateTime? bookingEndDate(Map<String, dynamic> booking) {
  final value =
      booking['endDate'] ?? booking['startDate'] ?? booking['startTime'];
  return value is Timestamp ? value.toDate() : null;
}

bool isPastConfirmedBooking(Map<String, dynamic> booking, DateTime now) {
  final status = booking['status']?.toString();
  final endDate = bookingEndDate(booking);
  return status == 'confirmed' && endDate != null && !endDate.isAfter(now);
}

String bookingDisplayStatus(Map<String, dynamic> booking, DateTime now) {
  if (isPastConfirmedBooking(booking, now)) {
    return bookingDisplayStatusAwaitingCompletion;
  }

  return booking['status']?.toString() ?? 'unknown';
}

bool isActiveCustomerBooking(Map<String, dynamic> booking, DateTime now) {
  final status = booking['status']?.toString();
  if (isPastConfirmedBooking(booking, now)) return false;
  return status == 'confirmed' ||
      status == 'pending_payment' ||
      status == 'pending_business_confirmation';
}

bool canCancelBookingFromUi(Map<String, dynamic> booking, DateTime now) {
  final status = booking['status']?.toString();
  final startDate = booking['startDate'] ?? booking['startTime'];
  final startsAt = startDate is Timestamp ? startDate.toDate() : null;
  if (startsAt != null && !startsAt.isAfter(now)) return false;
  return status == 'confirmed' ||
      status == 'pending_payment' ||
      status == 'pending_business_confirmation';
}

bool canCompleteBookingFromUi(Map<String, dynamic> booking) {
  return booking['status']?.toString() == 'confirmed';
}
