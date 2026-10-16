import '../services/business_activation_policy.dart';

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
  // Dashboard readiness only; legacy seat enforcement and bookings are unchanged.
  final bool hasDirectAvailability;
  final bool hasStaff;

  final bool hasPhotos;
  final bool profileComplete;
  final bool listingLive;
  final bool hasClaimedOwner;
  final bool hasContactOptions;
  final bool acceptingEnquiries;
  final bool hasPaymentMethod;
  final String category;

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
    this.hasDirectAvailability = false,
    required this.hasStaff,

    required this.hasPhotos,
    required this.profileComplete,
    this.listingLive = false,
    this.hasClaimedOwner = false,
    this.hasContactOptions = false,
    this.acceptingEnquiries = true,
    this.hasPaymentMethod = false,
    this.category = '',
  });

  // =====================================
  // COMPUTED
  // =====================================

  int get allowedStaff => freeStaffSlots + extraStaffSlots;

  bool get canEnquire =>
      listingLive &&
      hasClaimedOwner &&
      (hasContactOptions || (hasServices && acceptingEnquiries));
  bool get canBook =>
      listingLive &&
      hasClaimedOwner &&
      hasServices &&
      acceptingEnquiries &&
      hasAvailability &&
      hasPaymentMethod &&
      (!restrictionMode || hasDirectAvailability);
  bool get suggestsFirstService =>
      acceptingEnquiries && BusinessActivationPolicy.suggestsServices(category);
  String get nextStep {
    if (!listingLive) {
      return 'Your listing is not currently live. Check your page details.';
    }
    if (!hasClaimedOwner) {
      return 'A verified owner needs to claim this page before managing customer enquiries.';
    }
    if (!acceptingEnquiries) {
      return 'Keep your contact details and opening hours up to date. LocalLink booking requests are switched off for this page.';
    }
    if (!hasServices) {
      return BusinessActivationPolicy.firstStep(category);
    }
    if (restrictionMode && !hasDirectAvailability) {
      return 'Check your subscription details to see which booking tools are available.';
    }
    if (!hasPaymentMethod) {
      return 'Choose a supported payment method. Cash and bank transfer do not need Stripe.';
    }
    if (!hasAvailability) {
      return 'Share available appointment times if you want customers to book.';
    }
    return 'Keep your services, contact details and available times up to date.';
  }

  String get healthTitle => canBook
      ? 'Customers can make bookings'
      : canEnquire
      ? 'Customers can make enquiries'
      : listingLive
      ? 'Listing is live'
      : 'Listing is not live';
  bool get isHealthy => canBook;
}

class BusinessDashboardMessagingModel {
  final int unreadMessages;
  final int newEnquiries;

  const BusinessDashboardMessagingModel({
    required this.unreadMessages,
    required this.newEnquiries,
  });
}
