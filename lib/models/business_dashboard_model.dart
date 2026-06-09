class BusinessDashboardModel {

  final int todayBookings;
  final int todayRevenue;
  final int activeStaff;

  final int freeStaffSlots;
  final int extraStaffSlots;

  final bool stripeConnected;
  final bool restrictionMode;

  final bool hasServices;
  final bool hasAvailability;
  final bool hasStaff;

  // NEW
  final bool hasPhotos;
  final bool profileComplete;

  BusinessDashboardModel({

    required this.todayBookings,
    required this.todayRevenue,
    required this.activeStaff,

    required this.freeStaffSlots,
    required this.extraStaffSlots,

    required this.stripeConnected,
    required this.restrictionMode,

    required this.hasServices,
    required this.hasAvailability,
    required this.hasStaff,

    // NEW
    required this.hasPhotos,
    required this.profileComplete,
  });

  // =====================================
  // COMPUTED
  // =====================================

  int get allowedStaff =>
      freeStaffSlots + extraStaffSlots;

  String get healthTitle {

    if (!hasServices ||
        !hasStaff ||
        !hasPhotos) {

      return 'Needs Attention';
    }

    if (!hasAvailability ||
        !stripeConnected) {

      return 'Almost Ready';
    }

    return 'Operational';
  }

  bool get isHealthy {

    return hasServices &&
        hasStaff &&
        hasAvailability &&
        stripeConnected &&
        hasPhotos &&
        !restrictionMode;
  }
}