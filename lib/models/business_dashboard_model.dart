class BusinessDashboardModel {
  final int todayBookings;
  final int upcomingBookings;
  final int upcomingRevenue;
  final int unreadMessages;
  final int newEnquiries;
  final int activeStaff;
  final int liveAvailability;
  final int scheduledAvailability;
  final int pendingApprovalBookings;
  final int expiredAvailabilityToday;

  final int freeStaffSlots;
  final int extraStaffSlots;

  final bool stripeConnected;
  final bool restrictionMode;

  final bool hasServices;
  final bool hasAvailability;
  final bool hasStaff;

  final bool hasPhotos;
  final bool profileComplete;

  BusinessDashboardModel({
    required this.todayBookings,
    required this.upcomingBookings,
    required this.upcomingRevenue,
    required this.unreadMessages,
    required this.newEnquiries,
    required this.activeStaff,
    required this.liveAvailability,
    required this.scheduledAvailability,
    required this.pendingApprovalBookings,
    required this.expiredAvailabilityToday,

    required this.freeStaffSlots,
    required this.extraStaffSlots,

    required this.stripeConnected,
    required this.restrictionMode,

    required this.hasServices,
    required this.hasAvailability,
    required this.hasStaff,

    required this.hasPhotos,
    required this.profileComplete,
  });

  // =====================================
  // COMPUTED
  // =====================================

  int get allowedStaff => freeStaffSlots + extraStaffSlots;

  String get healthTitle {
    if (!hasServices || !hasStaff || !hasPhotos) {
      return 'Needs Attention';
    }

    if (!hasAvailability || !stripeConnected) {
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

class BusinessDashboardMessagingModel {
  final int unreadMessages;
  final int newEnquiries;

  const BusinessDashboardMessagingModel({
    required this.unreadMessages,
    required this.newEnquiries,
  });
}
