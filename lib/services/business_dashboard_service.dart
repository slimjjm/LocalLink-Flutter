import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/business_dashboard_model.dart';

class BusinessDashboardService {

  static Future<BusinessDashboardModel>
      loadDashboard(
    String businessId,
  ) async {

    final firestore =
        FirebaseFirestore.instance;

    // =====================================
    // TODAY RANGE
    // =====================================

    final now = DateTime.now();

    final startOfDay = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final endOfDay = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
    );

    // =====================================
    // BOOKINGS
    // =====================================

    final bookingsSnap =
        await firestore
            .collection('bookings')
            .where(
              'businessId',
              isEqualTo: businessId,
            )
            .where(
              'status',
              isEqualTo: 'confirmed',
            )
            .where(
              'startDate',
              isGreaterThanOrEqualTo:
                  Timestamp.fromDate(
                startOfDay,
              ),
            )
            .where(
              'startDate',
              isLessThanOrEqualTo:
                  Timestamp.fromDate(
                endOfDay,
              ),
            )
            .get();

    int todayRevenue = 0;

    for (final doc in bookingsSnap.docs) {

      final data = doc.data();

      final price =
          (data['price'] ?? 0) as num;

      todayRevenue += price.toInt();
    }

    // =====================================
    // STAFF
    // =====================================

    final staffSnap =
        await firestore
            .collection('businesses')
            .doc(businessId)
            .collection('staff')
            .where(
              'isActive',
              isEqualTo: true,
            )
            .get();

    // =====================================
    // SERVICES
    // =====================================

    final servicesSnap =
        await firestore
            .collection('businesses')
            .doc(businessId)
            .collection('services')
            .limit(1)
            .get();

    // =====================================
    // AVAILABILITY
    // =====================================

    bool hasAvailability = false;

    final staffDocs =
        staffSnap.docs;

    for (final staffDoc in staffDocs) {

      final availabilitySnap =
          await firestore
              .collection('businesses')
              .doc(businessId)
              .collection('staff')
              .doc(staffDoc.id)
              .collection('availableSlots')
              .limit(1)
              .get();

      if (availabilitySnap.docs.isNotEmpty) {

        hasAvailability = true;
        break;
      }
    }

    // =====================================
    // BUSINESS
    // =====================================

    final businessSnap =
        await firestore
            .collection('businesses')
            .doc(businessId)
            .get();

    final businessData =
        businessSnap.data() ?? {};

        final photoURLs =
    List<String>.from(
  businessData['photoURLs'] ?? [],
);

final hasPhotos =
    photoURLs.isNotEmpty;

final profileComplete =
    hasPhotos &&
    (businessData['businessName'] ?? '')
        .toString()
        .isNotEmpty &&
    (businessData['address'] ?? '')
        .toString()
        .isNotEmpty &&
    (businessData['category'] ?? '')
        .toString()
        .isNotEmpty;

    final stripeConnected =
        businessData[
            'stripeConnected'] ==
        true;

    // =====================================
    // ENTITLEMENTS
    // =====================================

    final entitlementsSnap =
        await firestore
            .collection('businesses')
            .doc(businessId)
            .collection('entitlements')
            .doc('default')
            .get();

    final entitlements =
        entitlementsSnap.data() ?? {};

    final restrictionMode =
        entitlements[
            'restrictionMode'] ==
        true;

    final freeStaffSlots =
        entitlements[
            'freeStaffSlots'] ?? 1;

    final extraStaffSlots =
        entitlements[
            'extraStaffSlots'] ?? 0;

    // =====================================
    // RETURN MODEL
    // =====================================

    return BusinessDashboardModel(

      todayBookings:
          bookingsSnap.docs.length,

      todayRevenue:
          todayRevenue,

      activeStaff:
          staffSnap.docs.length,

      freeStaffSlots:
          freeStaffSlots,

      extraStaffSlots:
          extraStaffSlots,

      stripeConnected:
          stripeConnected,

      restrictionMode:
          restrictionMode,

      hasServices:
          servicesSnap.docs.isNotEmpty,

      hasAvailability:
          hasAvailability,

      hasStaff:
          staffSnap.docs.isNotEmpty,

          hasPhotos: hasPhotos,
profileComplete: profileComplete,
    );
  }
}