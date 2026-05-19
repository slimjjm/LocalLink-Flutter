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
  });

  // =====================================
  // COMPUTED
  // =====================================

  int get allowedStaff =>
      freeStaffSlots + extraStaffSlots;

  String get healthTitle {

    if (!hasServices || !hasStaff) {
      return 'Needs Setup';
    }

    if (!hasAvailability ||
        !stripeConnected) {
      return 'Almost Ready';
    }

    return 'Ready';
  }

  bool get isHealthy {

    return hasServices &&
        hasStaff &&
        hasAvailability &&
        stripeConnected &&
        !restrictionMode;
  }
}