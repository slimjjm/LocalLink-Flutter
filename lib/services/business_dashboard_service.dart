import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/business_dashboard_model.dart';

class BusinessDashboardService {
  static Future<BusinessDashboardMessagingModel> loadMessagingSummary(
    String businessId,
  ) async {
    final conversationsSnap = await FirebaseFirestore.instance
        .collection('conversations')
        .where('businessId', isEqualTo: businessId)
        .where('archived', isEqualTo: false)
        .get();

    var unreadMessages = 0;
    var newEnquiries = 0;

    for (final doc in conversationsSnap.docs) {
      final data = doc.data();

      unreadMessages += ((data['unreadBusinessCount'] ?? 0) as num).toInt();

      if (data['conversationStatus'] == 'enquiry') {
        newEnquiries++;
      }
    }

    return BusinessDashboardMessagingModel(
      unreadMessages: unreadMessages,
      newEnquiries: newEnquiries,
    );
  }

  static Future<BusinessDashboardModel> loadDashboard(String businessId) async {
    final firestore = FirebaseFirestore.instance;

    // =====================================
    // TODAY RANGE
    // =====================================

    final now = DateTime.now();

    final startOfDay = DateTime(now.year, now.month, now.day);

    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    // =====================================
    // BOOKINGS
    // =====================================

    final bookingsSnap = await firestore
        .collection('bookings')
        .where('businessId', isEqualTo: businessId)
        .where('status', isEqualTo: 'confirmed')
        .where(
          'startDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where('startDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .get();

    final upcomingBookingsSnap = await firestore
        .collection('bookings')
        .where('businessId', isEqualTo: businessId)
        .where('status', isEqualTo: 'confirmed')
        .where('startDate', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .get();

    int upcomingRevenue = 0;

    for (final doc in upcomingBookingsSnap.docs) {
      final data = doc.data();

      final price = (data['price'] ?? 0) as num;

      upcomingRevenue += price.toInt();
    }

    final liveAvailabilitySnap = await firestore
        .collection('availabilityPosts')
        .where('businessId', isEqualTo: businessId)
        .where('isActive', isEqualTo: true)
        .where(
          'availabilityAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(now),
        )
        .get();

    final scheduledAvailabilitySnap = await firestore
        .collection('availabilityPosts')
        .where('businessId', isEqualTo: businessId)
        .where('isActive', isEqualTo: true)
        .where(
          'availabilityAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(endOfDay),
        )
        .get();

    final pendingApprovalSnap = await firestore
        .collection('bookings')
        .where('businessId', isEqualTo: businessId)
        .where('status', isEqualTo: 'pending_business_confirmation')
        .get();

    final expiredAvailabilitySnap = await firestore
        .collection('availabilityPosts')
        .where('businessId', isEqualTo: businessId)
        .where('isActive', isEqualTo: false)
        .where('archivedReason', isEqualTo: 'expired')
        .where(
          'availabilityAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where('availabilityAt', isLessThanOrEqualTo: Timestamp.fromDate(now))
        .get();

    // =====================================
    // STAFF
    // =====================================

    final staffSnap = await firestore
        .collection('businesses')
        .doc(businessId)
        .collection('staff')
        .where('isActive', isEqualTo: true)
        .get();

    // =====================================
    // SERVICES
    // =====================================

    final servicesSnap = await firestore
        .collection('businesses')
        .doc(businessId)
        .collection('services')
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    // =====================================
    // BUSINESS
    // =====================================

    final businessSnap = await firestore
        .collection('businesses')
        .doc(businessId)
        .get();

    final businessData = businessSnap.data() ?? {};

    final photoURLs = List<String>.from(businessData['photoURLs'] ?? []);

    final hasPhotos = photoURLs.isNotEmpty;

    final profileComplete =
        hasPhotos &&
        (businessData['businessName'] ?? '').toString().isNotEmpty &&
        (businessData['address'] ?? '').toString().isNotEmpty &&
        (businessData['category'] ?? '').toString().isNotEmpty;

    final stripeConnected = businessData['stripeConnected'] == true;

    // =====================================
    // ENTITLEMENTS
    // =====================================

    final entitlementsSnap = await firestore
        .collection('businesses')
        .doc(businessId)
        .collection('entitlements')
        .doc('default')
        .get();

    final entitlements = entitlementsSnap.data() ?? {};

    final restrictionMode = entitlements['restrictionMode'] == true;

    final freeStaffSlots = entitlements['freeStaffSlots'] ?? 1;

    final extraStaffSlots = entitlements['extraStaffSlots'] ?? 0;

    // =====================================
    // RETURN MODEL
    // =====================================

    return BusinessDashboardModel(
      todayBookings: bookingsSnap.docs.length,

      upcomingBookings: upcomingBookingsSnap.docs.length,

      upcomingRevenue: upcomingRevenue,

      unreadMessages: 0,

      newEnquiries: 0,

      activeStaff: staffSnap.docs.length,

      liveAvailability: liveAvailabilitySnap.docs.length,

      scheduledAvailability: scheduledAvailabilitySnap.docs.length,

      pendingApprovalBookings: pendingApprovalSnap.docs.length,

      expiredAvailabilityToday: expiredAvailabilitySnap.docs.length,

      freeStaffSlots: freeStaffSlots,

      extraStaffSlots: extraStaffSlots,

      stripeConnected: stripeConnected,

      restrictionMode: restrictionMode,

      hasServices: servicesSnap.docs.isNotEmpty,

      hasAvailability: liveAvailabilitySnap.docs.isNotEmpty,

      hasStaff: staffSnap.docs.isNotEmpty,

      hasPhotos: hasPhotos,
      profileComplete: profileComplete,
    );
  }
}
