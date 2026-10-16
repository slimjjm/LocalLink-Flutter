import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/business_dashboard_model.dart';
import 'business_activation_policy.dart';
import '../utils/helpers.dart';

class BusinessDashboardService {
  static bool hasUsableDirectAvailability({
    required List<Map<String, dynamic>> services,
    required List<Map<String, dynamic>> posts,
    required DateTime now,
  }) => BusinessActivationPolicy.hasBookingOptions(
    services: services,
    staff: const [],
    slots: const [],
    posts: posts.where((post) {
      final raw = post['remainingCapacity'] ?? post['capacity'] ?? 1;
      final remaining = raw is num ? raw : num.tryParse(raw.toString());
      return post['archived'] != true &&
          remaining != null &&
          remaining.isFinite &&
          remaining > 0;
    }).toList(),
    now: now,
  );

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
        .get();

    final activeServiceIds = servicesSnap.docs.map((doc) => doc.id).toSet();
    final assignedStaff = staffSnap.docs.where((doc) {
      final ids = doc.data()['serviceIds'];
      return ids is List && ids.any(activeServiceIds.contains);
    });
    // One range query per relevant staff member uses existing single-field
    // indexes, avoiding a new collection-group composite index or migration.
    final slotSnapshots = await Future.wait(
      assignedStaff.map(
        (person) => person.reference
            .collection('availableSlots')
            .where('startTime', isGreaterThan: Timestamp.fromDate(now))
            .get(),
      ),
    );
    final hasDirectBookingOptions = hasUsableDirectAvailability(
      services: servicesSnap.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList(),
      posts: liveAvailabilitySnap.docs.map((doc) => doc.data()).toList(),
      now: now,
    );
    final hasBookingOptions = BusinessActivationPolicy.hasBookingOptions(
      services: servicesSnap.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList(),
      staff: staffSnap.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList(),
      slots: slotSnapshots
          .expand((snapshot) => snapshot.docs.map((doc) => doc.data()))
          .toList(),
      posts: liveAvailabilitySnap.docs.map((doc) => doc.data()).toList(),
      now: now,
    );

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

      hasAvailability: hasBookingOptions,
      hasDirectAvailability: hasDirectBookingOptions,

      hasStaff: staffSnap.docs.isNotEmpty,

      hasPhotos: hasPhotos,
      profileComplete: profileComplete,
      listingLive: BusinessActivationPolicy.listingLive(businessData),
      hasClaimedOwner: BusinessActivationPolicy.hasClaimedOwner(businessData),
      hasContactOptions: BusinessActivationPolicy.contactLinks(
        businessData,
      ).isNotEmpty,
      acceptingEnquiries: businessData['acceptingLeads'] != false,
      hasPaymentMethod: resolvePaymentMethods(
        businessData,
      ).any((method) => {'cash', 'bank_transfer', 'stripe'}.contains(method)),
      category: (businessData['category'] ?? '').toString(),
    );
  }
}
