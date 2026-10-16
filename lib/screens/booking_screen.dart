import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'booking_success_screen.dart';
import 'booking_summary_screen.dart';
import 'booking_confirmation_wait_screen.dart';
import '../config/stripe_config.dart';
import '../models/address_result.dart';
import '../services/address_search_service.dart';
import '../services/analytics_service.dart';
import '../services/auth_required_action.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../utils/helpers.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_form.dart';
import '../widgets/local_link_states.dart';
import '../widgets/local_link_surface_card.dart';

const Duration kShortNoticeApprovalWindow = Duration(hours: 2);
const String kBookingPreferenceDocumentId = 'booking';
const String kBookingPreferenceLastAddressField = 'lastAddress';
const String kStripePaymentReturnUrl = 'locallink://stripe-return';
const String kStripePaymentAccountContextPlatform = 'platform';

@visibleForTesting
String savedGeneralBookingAddressFromPreference(Map<String, dynamic>? data) {
  return data?[kBookingPreferenceLastAddressField]?.toString().trim() ?? '';
}

@visibleForTesting
String savedBookingAddressFromPreference(Map<String, dynamic>? data) {
  return data?['lastAddress']?.toString().trim() ?? '';
}

@visibleForTesting
String preferredSavedBookingAddress({
  required Map<String, dynamic>? generalPreference,
  required Map<String, dynamic>? businessPreference,
}) {
  final generalAddress = savedGeneralBookingAddressFromPreference(
    generalPreference,
  );
  if (generalAddress.isNotEmpty) return generalAddress;

  return savedBookingAddressFromPreference(businessPreference);
}

@visibleForTesting
SetupPaymentSheetParameters bookingPaymentSheetParametersFromBackend(
  Map<String, dynamic> data, {
  bool? enableApplePay,
}) {
  final clientSecret = data['clientSecret']?.toString().trim() ?? '';
  if (!_looksLikePaymentIntentClientSecret(clientSecret)) {
    throw const StripeConfigurationException(
      'Booking payment setup did not return a valid PaymentIntent client secret.',
    );
  }

  final shouldEnableApplePay =
      enableApplePay ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  return SetupPaymentSheetParameters(
    paymentIntentClientSecret: clientSecret,
    merchantDisplayName: 'LocalLink',
    returnURL: kStripePaymentReturnUrl,
    applePay: shouldEnableApplePay
        ? const PaymentSheetApplePay(merchantCountryCode: 'GB')
        : null,
  );
}

bool _looksLikePaymentIntentClientSecret(String value) {
  return value.startsWith('pi_') && value.contains('_secret_');
}

@visibleForTesting
String? stripeAccountIdForPaymentSheet(Map<String, dynamic> data) {
  final context = data['stripeAccountContext']?.toString().trim();
  final accountId = data['stripeAccountId']?.toString().trim() ?? '';

  if (context == null ||
      context.isEmpty ||
      context == kStripePaymentAccountContextPlatform) {
    return null;
  }

  return accountId.isEmpty ? null : accountId;
}

@visibleForTesting
String bookingCustomerAddressForPayload(String address) {
  return address.trim();
}

class BookingScreen extends StatefulWidget {
  final String businessId;
  final String serviceId;
  final Map<String, dynamic> serviceData;
  final List<String> paymentMethods;
  final String businessName;

  const BookingScreen({
    super.key,
    required this.businessId,
    required this.serviceId,
    required this.serviceData,
    required this.paymentMethods,
    required this.businessName,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  // 🔹 SLOT STATE
  List<Map<String, dynamic>> availableSlots = [];
  List<String> allowedStaffIds = [];
  String? selectedSlotId;
  Map<String, dynamic>? selectedSlot;

  bool isLoadingSlots = true;
  bool isProcessingBooking = false;
  final TextEditingController nameController = TextEditingController();

  final TextEditingController addressController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  final AddressSearchService _addressSearch = AddressSearchService();
  List<AddressResult> _addressSuggestions = [];
  String _savedBookingAddress = '';
  bool _isSearchingAddress = false;
  int _addressSearchRequest = 0;

  // 🔹 PAYMENT
  String selectedPaymentMethod = '';

  @override
  void initState() {
    super.initState();
    final availabilityStart = widget.serviceData['availabilityStartTime'];
    if (availabilityStart is Timestamp) {
      final date = availabilityStart.toDate().toLocal();
      selectedDate = DateTime(date.year, date.month, date.day);
    }
    _loadSavedBookingAddress();
    if (isDirectAvailability) {
      _setDirectAvailabilitySlot();
      isLoadingSlots = false;
      return;
    }
    loadSlots();
  }

  @override
  void dispose() {
    nameController.dispose();
    addressController.dispose();
    notesController.dispose();
    super.dispose();
  }

  // =====================================================
  // 🔹 LOAD SLOTS
  // =====================================================
  Future<void> _loadSavedBookingAddress() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final results = await Future.wait([
        userRef
            .collection('preferences')
            .doc(kBookingPreferenceDocumentId)
            .get(),
        userRef.collection('businessPreferences').doc(widget.businessId).get(),
      ]);

      final lastAddress = preferredSavedBookingAddress(
        generalPreference: results[0].data(),
        businessPreference: results[1].data(),
      );

      if (!mounted || lastAddress.isEmpty) {
        return;
      }

      setState(() => _savedBookingAddress = lastAddress);
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('Booking saved address lookup skipped: $error');
        debugPrintStack(stackTrace: stack);
      }
    }
  }

  void _useSavedBookingAddress() {
    if (_savedBookingAddress.isEmpty) return;
    _addressSearchRequest++;
    setState(() {
      addressController.text = _savedBookingAddress;
      _addressSuggestions = [];
      _isSearchingAddress = false;
    });
  }

  Future<void> _searchBookingAddresses(String value) async {
    final query = value.trim();
    final request = ++_addressSearchRequest;

    if (query.length < 3) {
      setState(() {
        _addressSuggestions = [];
        _isSearchingAddress = false;
      });
      return;
    }

    setState(() => _isSearchingAddress = true);

    final results = await _addressSearch.search(query);

    if (!mounted || request != _addressSearchRequest) return;

    setState(() {
      _addressSuggestions = results;
      _isSearchingAddress = false;
    });
  }

  void _selectBookingAddress(AddressResult suggestion) {
    _addressSearchRequest++;
    setState(() {
      addressController.text = suggestion.description;
      _addressSuggestions = [];
      _isSearchingAddress = false;
    });
  }

  Future<void> loadSlots() async {
    if (isDirectAvailability) {
      _setDirectAvailabilitySlot();
      if (mounted) setState(() => isLoadingSlots = false);
      return;
    }

    try {
      if (!mounted) return;
      setState(() => isLoadingSlots = true);

      // =====================================
      // LOAD ALLOWED STAFF
      // =====================================

      final staffSnapshot = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .collection('staff')
          .where('serviceIds', arrayContains: widget.serviceId)
          .where('isActive', isEqualTo: true)
          .get();

      if (!mounted) return;

      allowedStaffIds = staffSnapshot.docs.map((doc) => doc.id).toList();

      // =====================================
      // NO STAFF CAN PERFORM SERVICE
      // =====================================

      if (allowedStaffIds.isEmpty) {
        setState(() {
          availableSlots = [];

          isLoadingSlots = false;
        });

        return;
      }

      // =====================================
      // DATE RANGE
      // =====================================

      final startOfDay = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );

      final endOfDay = startOfDay.add(const Duration(days: 1));

      // =====================================
      // LOAD AVAILABLE SLOTS
      // =====================================
      final snapshot = await FirebaseFirestore.instance
          .collectionGroup('availableSlots')
          .where('businessId', isEqualTo: widget.businessId)
          .where('staffId', whereIn: allowedStaffIds)
          .where('isBooked', isEqualTo: false)
          .where(
            'startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('startTime', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('startTime')
          .get();

      if (!mounted) return;

      final slots = snapshot.docs.map((doc) {
        final data = doc.data();

        return {
          'id': doc.id,

          'slotPath': doc.reference.path,

          'staffId': data['staffId'],

          'staffName': data['staffName'],

          ...data,
        };
      }).toList();

      slots.sort((a, b) {
        final aTime = (a['startTime'] as Timestamp).toDate();

        final bTime = (b['startTime'] as Timestamp).toDate();

        return aTime.compareTo(bTime);
      });

      final requestedSlotId = widget.serviceData['availabilitySlotId']
          ?.toString()
          .trim();
      final requestedStaffId = widget.serviceData['availabilityStaffId']
          ?.toString()
          .trim();
      final requestedStart = widget.serviceData['availabilityStartTime'];
      Map<String, dynamic>? preselectedSlot;

      if (requestedSlotId != null && requestedSlotId.isNotEmpty) {
        for (final slot in slots) {
          final sameSlot = slot['id']?.toString() == requestedSlotId;
          final sameStaff =
              requestedStaffId == null ||
              requestedStaffId.isEmpty ||
              slot['staffId']?.toString() == requestedStaffId;
          if (sameSlot && sameStaff) {
            preselectedSlot = slot;
            break;
          }
        }
      }

      if (preselectedSlot == null && requestedStart is Timestamp) {
        final requestedDate = requestedStart.toDate();
        for (final slot in slots) {
          final startTime = slot['startTime'];
          if (startTime is! Timestamp) continue;

          final sameStart = startTime.toDate().isAtSameMomentAs(requestedDate);
          final sameStaff =
              requestedStaffId == null ||
              requestedStaffId.isEmpty ||
              slot['staffId']?.toString() == requestedStaffId;
          if (sameStart && sameStaff) {
            preselectedSlot = slot;
            break;
          }
        }
      }

      setState(() {
        availableSlots = slots;
        if (preselectedSlot != null) {
          selectedSlot = preselectedSlot;
          selectedSlotId = preselectedSlot['id']?.toString();
        }

        isLoadingSlots = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoadingSlots = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('We could not load available times. Please try again.'),
        ),
      );
    }
  }

  // =====================================================
  // 🔹 FILTER BY DATE
  // =====================================================
  bool hasEnoughConsecutiveSlots(Map<String, dynamic> slot) {
    final durationMinutes = widget.serviceData['durationMinutes'] ?? 30;

    final slotsRequired = (durationMinutes / 30).ceil();

    final start = (slot['startTime'] as Timestamp).toDate();

    final staffId = slot['staffId'];

    for (int i = 1; i < slotsRequired; i++) {
      final nextStart = start.add(Duration(minutes: i * 30));

      final exists = availableSlots.any((s) {
        final sStart = (s['startTime'] as Timestamp).toDate();

        return s['staffId'] == staffId && sStart == nextStart;
      });

      if (!exists) {
        return false;
      }
    }

    return true;
  }

  List<Map<String, dynamic>> get filteredSlots {
    if (isDirectAvailability && selectedSlot != null) {
      return [selectedSlot!];
    }

    final now = DateTime.now();

    return availableSlots.where((slot) {
      final date = (slot['startTime'] as Timestamp).toDate().toLocal();

      // SAME DAY FILTER

      final matchesSelectedDay =
          date.year == selectedDate.year &&
          date.month == selectedDate.month &&
          date.day == selectedDate.day;

      if (!matchesSelectedDay) {
        return false;
      }

      // FUTURE ONLY

      if (date.isBefore(now)) {
        return false;
      }

      if (!hasEnoughConsecutiveSlots(slot)) {
        return false;
      }
      return true;
    }).toList();
  }

  // =====================================================
  // 🔹 NEXT AVAILABLE DATE
  // =====================================================

  Future<void> goToNextAvailableDate() async {
    if (isDirectAvailability) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('This time is fixed.')));
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collectionGroup('availableSlots')
          .where('businessId', isEqualTo: widget.businessId)
          .where('staffId', whereIn: allowedStaffIds)
          .where('isBooked', isEqualTo: false)
          .where(
            'startTime',
            isGreaterThan: Timestamp.fromDate(
              DateTime.now().add(const Duration(hours: 2)),
            ),
          )
          .orderBy('startTime')
          .limit(1)
          .get();

      if (!mounted) return;

      if (snapshot.docs.isEmpty) {
        return;
      }

      final next = (snapshot.docs.first['startTime'] as Timestamp).toDate();

      setState(() {
        selectedDate = DateTime(
          next.toLocal().year,
          next.toLocal().month,
          next.toLocal().day,
        );
        selectedSlotId = null;
        selectedSlot = null;
      });

      await loadSlots();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We could not find the next available time. Please try again.',
          ),
        ),
      );
    }
  }

  // =====================================================
  // 🔹 HELPERS
  // =====================================================

  String formatTime(Timestamp timestamp) {
    final date = timestamp.toDate();
    return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
  }

  String formatPrice(dynamic price) {
    if (price == null) {
      return '£0.00';
    }

    final pounds = (price as num) / 100;

    return '£${pounds.toStringAsFixed(2)}';
  }

  bool get hasAvailabilityContext {
    final availabilityPostId = widget.serviceData['availabilityPostId']
        ?.toString()
        .trim();
    return availabilityPostId != null && availabilityPostId.isNotEmpty;
  }

  bool get isDirectAvailability {
    final availabilityPostId = widget.serviceData['availabilityPostId']
        ?.toString()
        .trim();
    final slotPath = widget.serviceData['availabilitySlotPath']
        ?.toString()
        .trim();

    return availabilityPostId != null &&
        availabilityPostId.isNotEmpty &&
        (slotPath == null || slotPath.isEmpty || slotPath == 'null');
  }

  String get availabilityType {
    return widget.serviceData['availabilityType']?.toString().trim() ?? 'exact';
  }

  String get _analyticsSource {
    return hasAvailabilityContext ? 'availability_detail' : 'business_detail';
  }

  String get _analyticsBusinessCategory {
    return (widget.serviceData['businessCategory'] ??
            widget.serviceData['category'] ??
            '')
        .toString();
  }

  void _setDirectAvailabilitySlot() {
    final start = widget.serviceData['availabilityStartTime'];
    final end = widget.serviceData['availabilityEndTime'];
    if (start is! Timestamp) return;

    selectedSlot = {
      'id': 'direct_${widget.serviceData['availabilityPostId']}',
      'startTime': start,
      'endTime': end,
      'staffId': null,
      'staffName': '',
      'directAvailability': true,
    };
    selectedSlotId = selectedSlot!['id']?.toString();
    availableSlots = [selectedSlot!];
  }

  Future<void> _pickDirectTime() async {
    final current = selectedSlot?['startTime'];
    final initial = current is Timestamp
        ? TimeOfDay.fromDateTime(current.toDate())
        : TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;

    final start = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      picked.hour,
      picked.minute,
    );
    final duration =
        (widget.serviceData['durationMinutes'] as num?)?.toInt() ?? 30;
    final end = start.add(Duration(minutes: duration));

    setState(() {
      selectedSlot = {
        'id': 'direct_${widget.serviceData['availabilityPostId']}',
        'startTime': Timestamp.fromDate(start),
        'endTime': Timestamp.fromDate(end),
        'staffId': null,
        'staffName': '',
        'directAvailability': true,
      };
      selectedSlotId = selectedSlot!['id']?.toString();
      availableSlots = [selectedSlot!];
    });
  }

  bool _requiresBusinessApproval(Map<String, dynamic> slot) {
    final startTime = slot['startTime'];
    if (startTime is! Timestamp) return false;

    return startTime
            .toDate()
            .difference(DateTime.now())
            .compareTo(kShortNoticeApprovalWindow) <
        0;
  }

  Future<bool> _validateSelectedAvailability() async {
    final slot = selectedSlot;
    if (slot == null) return false;

    if (isDirectAvailability) {
      try {
        final availabilityPostId = widget.serviceData['availabilityPostId']
            ?.toString()
            .trim();
        if (availabilityPostId == null || availabilityPostId.isEmpty) {
          return false;
        }

        final postDoc = await FirebaseFirestore.instance
            .collection('availabilityPosts')
            .doc(availabilityPostId)
            .get();

        if (!postDoc.exists) return false;

        final data = postDoc.data() ?? {};
        final remaining = (data['remainingCapacity'] as num?)?.toInt() ?? 1;
        if (data['isActive'] == false ||
            data['archived'] == true ||
            data['status'] != 'live' ||
            remaining <= 0) {
          return false;
        }

        final start = slot['startTime'];
        final postStart = data['startDateTime'] ?? data['startTime'];
        final postEnd = data['endDateTime'] ?? data['endTime'];

        if (start is! Timestamp) return false;
        if (availabilityType != 'flexible' &&
            start.toDate().isBefore(DateTime.now())) {
          return false;
        }

        if (availabilityType == 'window' &&
            postStart is Timestamp &&
            postEnd is Timestamp) {
          final duration =
              (widget.serviceData['durationMinutes'] as num?)?.toInt() ?? 30;
          final chosenStart = start.toDate();
          final chosenEnd = chosenStart.add(Duration(minutes: duration));
          if (chosenStart.isBefore(postStart.toDate()) ||
              chosenEnd.isAfter(postEnd.toDate())) {
            return false;
          }
        }

        return true;
      } catch (_) {
        return false;
      }
    }

    final slotPath = slot['slotPath']?.toString().trim();
    if (slotPath == null || slotPath.isEmpty) return false;

    try {
      final slotDoc = await FirebaseFirestore.instance.doc(slotPath).get();

      if (!slotDoc.exists) return false;

      final slotData = slotDoc.data() ?? {};
      final isBooked =
          slotData['isBooked'] == true || slotData['isBooked'] == 1;
      if (isBooked) return false;

      final startTime = slotData['startTime'];
      if (startTime is Timestamp &&
          startTime.toDate().isBefore(DateTime.now())) {
        return false;
      }

      final availabilityPostId = widget.serviceData['availabilityPostId']
          ?.toString()
          .trim();
      if (availabilityPostId != null && availabilityPostId.isNotEmpty) {
        final postDoc = await FirebaseFirestore.instance
            .collection('availabilityPosts')
            .doc(availabilityPostId)
            .get();

        if (!postDoc.exists) return false;

        final data = postDoc.data() ?? {};
        if (data['isActive'] == false || data['archived'] == true) {
          return false;
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showSlotUnavailableDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Appointment unavailable'),
          content: const Text(
            'Unfortunately this appointment has just been booked by someone else.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                goToNextAvailableDate();
              },
              child: const Text('Next available'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // =====================================================
  // 🔹 DATE PICKER
  // =====================================================

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );

    if (!mounted) return;

    if (picked != null) {
      setState(() {
        selectedDate = picked;
        if (!isDirectAvailability) {
          selectedSlotId = null;
          selectedSlot = null;
        }
      });

      await loadSlots(); // 🔥 REQUIRED
    }
  }

  // =====================================================
  // 🔹 DIRECT PAYMENT BOOKING
  // =====================================================

  Future<void> createDirectPaymentBooking() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        isDirectAvailability
            ? 'createDirectAvailabilityCashBooking'
            : 'createCashBooking',
      );

      final payload = {
        'businessId': widget.businessId,
        'serviceId': widget.serviceId,
        'availabilityPostId': widget.serviceData['availabilityPostId'],
        'selectedStartMillis': (selectedSlot!['startTime'] as Timestamp)
            .toDate()
            .millisecondsSinceEpoch,
        'paymentMethod': selectedPaymentMethod,
        'customerName': nameController.text.trim(),
        'customerAddress': bookingCustomerAddressForPayload(
          addressController.text,
        ),
        'customerNotes': notesController.text.trim(),
      };

      if (!isDirectAvailability) {
        payload.addAll({
          'staffId': selectedSlot!['staffId'],
          'slotId': selectedSlot!['id'],
          'slotPath': selectedSlot!['slotPath'],
        });
      }

      await callable.call(payload);

      await LocalLinkAnalytics.instance.bookingCompleted(
        source: _analyticsSource,
        paymentMethod: selectedPaymentMethod,
        businessCategory: _analyticsBusinessCategory,
      );

      if (!mounted) return;

      final requiresApproval = _requiresBusinessApproval(selectedSlot!);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BookingSuccessScreen(
            serviceName: widget.serviceData['name'] ?? 'Service',
            businessName: widget.businessName,
            bookingDate: (selectedSlot!['startTime'] as Timestamp).toDate(),
            isCashBooking: true,
            pendingBusinessConfirmation: requiresApproval,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We could not complete your booking. Please try again.',
          ),
        ),
      );
    }
  }

  // =====================================================
  // 🔹 STRIPE
  // =====================================================
  Future<void> startStripeBooking() async {
    String? pendingBookingId;
    final callableName = isDirectAvailability
        ? 'createDirectAvailabilityPaymentIntent'
        : 'createBookingPaymentIntent';
    var stripeStage = 'starting';
    try {
      _stripeBookingDebugLog(3, 'stripe_booking_started', {
        'callable': callableName,
        'isDirectAvailability': isDirectAvailability,
        'businessId': widget.businessId,
        'serviceId': widget.serviceId,
      });
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception("Not logged in");
      }

      if (selectedSlot == null) {
        throw Exception("No slot selected");
      }

      final stripeConfig = await configureStripeForApp();
      if (stripeConfig == null) {
        throw const StripeConfigurationException(
          'Stripe publishable key is not configured for this app build.',
        );
      }
      _stripeBookingDebugLog(4, 'stripe_config_ready', {
        'publishableKeyConfigured': stripeConfig.publishableKey.isNotEmpty,
        'mode': stripeConfig.mode.name,
      });

      final callable = FirebaseFunctions.instance.httpsCallable(callableName);
      _stripeBookingDebugLog(5, 'callable_selected', {
        'callable': callableName,
      });

      final payload = {
        'businessId': widget.businessId,
        'serviceId': widget.serviceId,
        'availabilityPostId': widget.serviceData['availabilityPostId'],
        'selectedStartMillis': (selectedSlot!['startTime'] as Timestamp)
            .toDate()
            .millisecondsSinceEpoch,
        'paymentMethod': 'stripe',
        'customerName': nameController.text.trim(),
        'customerAddress': bookingCustomerAddressForPayload(
          addressController.text,
        ),
        'customerNotes': notesController.text.trim(),
      };

      if (!isDirectAvailability) {
        payload.addAll({
          'staffId': selectedSlot!['staffId'],
          'slotId': selectedSlot!['id'],
          'slotPath': selectedSlot!['slotPath'],
        });
      }

      _stripeBookingDebugLog(6, 'callable_invocation_starting', {
        'callable': callableName,
        'hasAvailabilityPostId':
            payload['availabilityPostId']?.toString().trim().isNotEmpty == true,
        'hasStaffId': payload['staffId']?.toString().trim().isNotEmpty == true,
        'hasSlotId': payload['slotId']?.toString().trim().isNotEmpty == true,
      });
      stripeStage = 'callable';
      final result = await callable.call(payload);
      final resultData = Map<String, dynamic>.from(result.data as Map);
      pendingBookingId = resultData['bookingId']?.toString();
      _stripeBookingDebugLog(7, 'callable_response_received', {
        'callable': callableName,
        'bookingId': pendingBookingId ?? 'missing',
        'clientSecretPresent':
            resultData['clientSecret']?.toString().trim().isNotEmpty == true,
        'clientSecretLooksValid': _looksLikePaymentIntentClientSecret(
          resultData['clientSecret']?.toString().trim() ?? '',
        ),
        'stripeAccountContext':
            resultData['stripeAccountContext']?.toString().trim() ?? 'missing',
        'stripeAccountIdPresent':
            resultData['stripeAccountId']?.toString().trim().isNotEmpty == true,
      });

      Stripe.stripeAccountId = stripeAccountIdForPaymentSheet(resultData);
      _stripeBookingDebugLog(8, 'stripe_account_context_applied', {
        'paymentSheetAccount': Stripe.stripeAccountId == null
            ? 'platform'
            : 'connected',
      });
      await Stripe.instance.applySettings();
      _debugLogStripePaymentSheetSetup(resultData);
      _stripeBookingDebugLog(9, 'initPaymentSheet_starting');
      stripeStage = 'initPaymentSheet';
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: bookingPaymentSheetParametersFromBackend(
          resultData,
        ),
      );
      _stripeBookingDebugLog(10, 'initPaymentSheet_succeeded');

      _stripeBookingDebugLog(11, 'presentPaymentSheet_starting');
      stripeStage = 'presentPaymentSheet';
      await Stripe.instance.presentPaymentSheet();
      _stripeBookingDebugLog(12, 'presentPaymentSheet_succeeded');

      await LocalLinkAnalytics.instance.bookingCompleted(
        source: _analyticsSource,
        paymentMethod: 'stripe',
        businessCategory: _analyticsBusinessCategory,
      );

      if (!mounted) return;

      _stripeBookingDebugLog(13, 'post_payment_confirmation_wait_starting', {
        'bookingId': pendingBookingId ?? 'missing',
      });
      stripeStage = 'postPaymentConfirmation';
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BookingConfirmationWaitScreen(
            bookingId: result.data['bookingId']?.toString() ?? '',
            serviceName: widget.serviceData['name'] ?? 'Service',
            businessName: widget.businessName,
            bookingDate: (selectedSlot!['startTime'] as Timestamp).toDate(),
          ),
        ),
      );
    } catch (error, stack) {
      if (kDebugMode) {
        if (error is StripeException &&
            error.error.code == FailureCode.Canceled) {
          _stripeBookingDebugLog(14, 'paymentSheet_cancelled', {
            'bookingId': pendingBookingId ?? 'missing',
            'stage': stripeStage,
          });
        } else if (error is StripeException) {
          _stripeBookingDebugLog(15, 'stripe_exception_caught', {
            'bookingId': pendingBookingId ?? 'missing',
            'stage': stripeStage,
          });
        } else if (error is FirebaseFunctionsException) {
          _stripeBookingDebugLog(16, 'firebase_functions_exception_caught', {
            'callable': callableName,
            'bookingId': pendingBookingId ?? 'missing',
            'stage': stripeStage,
            'code': error.code,
            'message': error.message ?? 'none',
          });
        } else {
          _stripeBookingDebugLog(17, 'unexpected_exception_caught', {
            'bookingId': pendingBookingId ?? 'missing',
            'stage': stripeStage,
            'type': error.runtimeType.toString(),
          });
        }
        _debugLogStripeBookingFailure(error);
        debugPrintStack(stackTrace: stack);
      }
      if (pendingBookingId != null && pendingBookingId.isNotEmpty) {
        _stripeBookingDebugLog(18, 'pending_card_booking_release_starting', {
          'bookingId': pendingBookingId,
        });
        await _releasePendingCardBooking(pendingBookingId);
      }
      if (error is StripeException &&
          error.error.code == FailureCode.Canceled) {
        await LocalLinkAnalytics.instance.bookingCancelled(
          source: _analyticsSource,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_paymentErrorMessage(error))));
    }
  }

  void _debugLogStripePaymentSheetSetup(Map<String, dynamic> data) {
    if (!kDebugMode) return;

    final config = StripeEnvironmentConfig.maybeFromEnvironment();
    final accountContext =
        data['stripeAccountContext']?.toString().trim().isEmpty ?? true
        ? 'missing'
        : data['stripeAccountContext'].toString().trim();
    final accountId = stripeAccountIdForPaymentSheet(data);
    final clientSecret = data['clientSecret']?.toString().trim() ?? '';

    debugPrint(
      'Stripe booking PaymentSheet setup: '
      'publishableKeyConfigured=${config?.publishableKey.isNotEmpty == true} '
      'mode=${config?.mode.name ?? 'missing'} '
      'clientSecretLooksValid=${_looksLikePaymentIntentClientSecret(clientSecret)} '
      'stripeAccountContext=$accountContext '
      'paymentSheetAccount=${accountId == null ? 'platform' : 'connected'}',
    );
  }

  void _stripeBookingDebugLog(
    int step,
    String event, [
    Map<String, Object?> fields = const {},
  ]) {
    if (!kDebugMode) return;
    final details = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    debugPrint(
      details.isEmpty
          ? '[StripeBooking] Flutter STEP $step event=$event'
          : '[StripeBooking] Flutter STEP $step event=$event $details',
    );
  }

  void _debugLogStripeBookingFailure(Object error) {
    if (error is StripeException) {
      final stripeError = error.error;
      debugPrint(
        '[StripeBooking] Flutter StripeException: '
        'code=${stripeError.code.name} '
        'localizedMessage=${stripeError.localizedMessage ?? 'none'} '
        'message=${stripeError.message ?? 'none'}',
      );
      return;
    }

    if (error is FirebaseFunctionsException) {
      debugPrint(
        '[StripeBooking] Flutter FirebaseFunctionsException: '
        'code=${error.code} message=${error.message ?? 'none'}',
      );
      return;
    }

    debugPrint(
      '[StripeBooking] Flutter unexpected exception: '
      'type=${error.runtimeType} message=$error',
    );
  }

  Future<void> _releasePendingCardBooking(String bookingId) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('cancelPendingCardBooking')
          .call({'bookingId': bookingId});
      _stripeBookingDebugLog(19, 'pending_card_booking_release_succeeded', {
        'bookingId': bookingId,
      });
    } catch (error, stack) {
      if (kDebugMode) {
        _stripeBookingDebugLog(20, 'pending_card_booking_release_failed', {
          'bookingId': bookingId,
          'type': error.runtimeType.toString(),
        });
        debugPrint(
          '[StripeBooking] Unable to release pending card booking: $error',
        );
        debugPrintStack(stackTrace: stack);
      }
    }
  }

  String _paymentErrorMessage(Object error) {
    if (error is StripeException) {
      final code = error.error.code;
      if (code == FailureCode.Canceled) {
        return 'Payment was cancelled. The time has been released.';
      }
      return 'We could not complete your payment. Please try again.';
    }

    if (error is FirebaseFunctionsException) {
      if (kDebugMode) {
        debugPrint(
          'Booking function error: ${error.code} ${error.message} ${error.details}',
        );
      }
      switch (error.code) {
        case 'failed-precondition':
          return error.message ?? 'This booking can no longer be completed.';
        case 'unauthenticated':
          return 'Please sign in to complete your booking.';
        case 'not-found':
          return 'This availability is no longer available.';
      }
    }

    return 'We could not complete your payment. Please try again.';
  }

  // =====================================================
  // 🔹 ROUTER
  // ===================================================

  Future<void> handleBooking() async {
    if (isProcessingBooking) return;

    _stripeBookingDebugLog(1, 'booking_button_pressed', {
      'paymentMethod': selectedPaymentMethod,
      'isDirectAvailability': isDirectAvailability,
      'hasSelectedSlot': selectedSlot != null,
    });

    final user = FirebaseAuth.instance.currentUser;

    final isLoggedIn = user != null && !user.isAnonymous;

    if (!isLoggedIn) {
      showLoginSheet();
      return;
    }

    if (selectedSlot == null || selectedPaymentMethod.isEmpty) {
      return;
    }

    final reviewed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BookingSummaryScreen(
          businessName: widget.businessName,
          serviceName: widget.serviceData['name'] ?? 'Service',
          slot: selectedSlot!,
          durationMinutes: (widget.serviceData['durationMinutes'] as num?)
              ?.toInt(),
          priceLabel: formatPrice(widget.serviceData['price']),
          address: addressController.text.trim(),
          paymentMethod: selectedPaymentMethod,
          customerNotes: notesController.text.trim(),
        ),
      ),
    );

    if (reviewed != true) {
      _stripeBookingDebugLog(2, 'booking_review_cancelled');
      return;
    }

    if (!mounted) return;

    await LocalLinkAnalytics.instance.bookingStarted(
      source: _analyticsSource,
      paymentMethod: selectedPaymentMethod,
      businessCategory: _analyticsBusinessCategory,
    );

    _stripeBookingDebugLog(2, 'availability_validation_starting');
    final stillAvailable = await _validateSelectedAvailability();
    if (!mounted) return;
    _stripeBookingDebugLog(2, 'availability_validation_finished', {
      'stillAvailable': stillAvailable,
    });

    if (!stillAvailable) {
      await _showSlotUnavailableDialog();
      await loadSlots();
      return;
    }

    setState(() {
      isProcessingBooking = true;
    });

    try {
      if (selectedPaymentMethod == 'stripe') {
        await startStripeBooking();
      } else {
        await createDirectPaymentBooking();
      }
    } finally {
      if (mounted) {
        setState(() {
          isProcessingBooking = false;
        });
      }
    }
  }

  void showLoginSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(20),

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              const Text(
                "Create an account to book",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              const Text(
                "Save your bookings, get reminders, and manage everything in one place.",
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await AuthRequiredAction.run(context, action: () async {});
                },

                child: const Text("Continue"),
              ),

              const SizedBox(height: 10),

              TextButton(
                onPressed: () => Navigator.pop(context),

                child: const Text("Not now"),
              ),
            ],
          ),
        );
      },
    );
  }
  // =====================================================
  // 🔹 UI
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final serviceName = widget.serviceData['name'] ?? 'Booking';
    final price = formatPrice(widget.serviceData['price']);
    final duration = widget.serviceData['durationMinutes'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(serviceName),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          LocalLinkSpacing.lg,
          LocalLinkSpacing.sm,
          LocalLinkSpacing.lg,
          LocalLinkSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          LocalLinkSurfaceCard(
            elevated: false,
            color: AppColors.serviceGreen.withValues(alpha: 0.07),
            padding: const EdgeInsets.all(LocalLinkSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceName,
                  style: LocalLinkTextStyles.screenTitle.copyWith(fontSize: 26),
                ),
                const SizedBox(height: LocalLinkSpacing.xs),
                Text(
                  widget.businessName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LocalLinkTextStyles.bodyStrong.copyWith(
                    color: AppColors.serviceGreen,
                  ),
                ),
                const SizedBox(height: LocalLinkSpacing.sm),
                Wrap(
                  spacing: LocalLinkSpacing.sm,
                  runSpacing: LocalLinkSpacing.xs,
                  children: [
                    _BookingMeta(icon: Icons.payments_outlined, label: price),
                    if (duration != null)
                      _BookingMeta(
                        icon: Icons.timer_outlined,
                        label: '$duration mins',
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: LocalLinkSpacing.lg),

          if (!isDirectAvailability || availabilityType == 'window') ...[
            LocalLinkFormSection(
              title: 'Choose a day',
              children: [
                LocalLinkDateTimeRow(
                  label: 'Date',
                  value:
                      '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                  onTap: pickDate,
                ),
              ],
            ),
            const SizedBox(height: LocalLinkSpacing.md),
          ],

          LocalLinkFormSection(
            title: 'Choose a time',
            helperText: hasAvailabilityContext
                ? 'You chose this from the business\'s available time.'
                : null,
            children: [
              if (isDirectAvailability && selectedSlot != null) ...[
                LocalLinkSurfaceCard(
                  elevated: false,
                  color: AppColors.serviceGreen.withValues(alpha: 0.08),
                  padding: const EdgeInsets.all(LocalLinkSpacing.sm),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, color: AppColors.serviceGreen),
                      const SizedBox(width: LocalLinkSpacing.xs),
                      Expanded(
                        child: Text(
                          '${formatTime(selectedSlot!['startTime'])} · ${duration ?? 30}m',
                          style: LocalLinkTextStyles.bodyStrong,
                        ),
                      ),
                      if (availabilityType == 'window')
                        TextButton(
                          onPressed: _pickDirectTime,
                          child: const Text('Change'),
                        ),
                    ],
                  ),
                ),
              ] else if (isLoadingSlots)
                const LocalLinkLoadingState(label: 'Loading available times')
              else if (filteredSlots.isEmpty)
                LocalLinkEmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'No appointments that day',
                  message: 'Try the next available date.',
                  actionLabel: 'Find another time',
                  onAction: goToNextAvailableDate,
                )
              else
                Wrap(
                  spacing: LocalLinkSpacing.xs,
                  runSpacing: LocalLinkSpacing.xs,
                  children: filteredSlots.map((slot) {
                    final time = formatTime(slot['startTime']);
                    final isSelected = selectedSlotId == slot['id'];

                    return ChoiceChip(
                      label: Text(
                        '$time · ${slot['staffName']} · ${duration}m',
                      ),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          selectedSlotId = slot['id'];
                          selectedSlot = slot;
                        });
                      },
                    );
                  }).toList(),
                ),
              if (selectedSlot != null && !isDirectAvailability) ...[
                const SizedBox(height: LocalLinkSpacing.sm),
                Text(
                  'With ${selectedSlot!['staffName']}',
                  style: LocalLinkTextStyles.metadata,
                ),
              ],
            ],
          ),

          const SizedBox(height: LocalLinkSpacing.md),

          LocalLinkFormSection(
            title: 'Your details',
            children: [
              LocalLinkFormField(
                controller: nameController,
                label: 'Your name',
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(
                controller: addressController,
                label: 'Address',
                maxLines: 2,
                keyboardType: TextInputType.streetAddress,
                onChanged: _searchBookingAddresses,
              ),
              if (_isSearchingAddress)
                const Padding(
                  padding: EdgeInsets.only(top: LocalLinkSpacing.xs),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (_addressSuggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: LocalLinkSpacing.xs),
                  child: LocalLinkSurfaceCard(
                    elevated: false,
                    color: AppColors.elevatedSurface,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: _addressSuggestions.map((suggestion) {
                        return ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(
                            suggestion.description,
                            style: LocalLinkTextStyles.bodyStrong,
                          ),
                          onTap: () => _selectBookingAddress(suggestion),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              if (_savedBookingAddress.isNotEmpty &&
                  addressController.text.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: LocalLinkSpacing.xs),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _useSavedBookingAddress,
                      icon: const Icon(Icons.history_outlined),
                      label: const Text('Use saved address'),
                    ),
                  ),
                ),
              const SizedBox(height: LocalLinkSpacing.sm),
              LocalLinkFormField(
                controller: notesController,
                label: 'Notes for the business',
                hintText: 'Access details, preferences or anything useful',
                maxLines: 2,
              ),
            ],
          ),

          const SizedBox(height: LocalLinkSpacing.md),

          LocalLinkFormSection(
            title: 'Payment',
            helperText: 'Choose how you would like to pay.',
            children: [
              Wrap(
                spacing: LocalLinkSpacing.xs,
                runSpacing: LocalLinkSpacing.xs,
                children: widget.paymentMethods.map((method) {
                  final normalised = method.toLowerCase().trim();
                  final isSelected = selectedPaymentMethod == normalised;

                  return ChoiceChip(
                    label: Text(paymentMethodLabel(normalised)),
                    selected: isSelected,
                    avatar: Icon(paymentMethodIcon(normalised), size: 18),
                    onSelected: (_) {
                      setState(() {
                        selectedPaymentMethod = normalised;
                      });
                    },
                  );
                }).toList(),
              ),
              if (selectedSlot != null &&
                  _requiresBusinessApproval(selectedSlot!)) ...[
                const SizedBox(height: LocalLinkSpacing.sm),
                Text(
                  'This starts soon, so the business will quickly confirm they can still fit you in.',
                  style: LocalLinkTextStyles.secondary,
                ),
              ],
            ],
          ),

          const SizedBox(height: LocalLinkSpacing.xl),

          LocalLinkButton(
            label: isProcessingBooking
                ? 'Preparing booking...'
                : selectedPaymentMethod == 'stripe'
                ? 'Review and pay'
                : 'Review booking',
            icon: Icons.check_circle_outline_rounded,
            isLoading: isProcessingBooking,
            onPressed:
                (selectedSlot == null ||
                    selectedPaymentMethod.isEmpty ||
                    isProcessingBooking)
                ? null
                : handleBooking,
            expand: true,
          ),
        ],
      ),
    );
  }
}

class _BookingMeta extends StatelessWidget {
  const _BookingMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.serviceGreen),
        const SizedBox(width: LocalLinkSpacing.xxs),
        Text(label, style: LocalLinkTextStyles.metadata),
      ],
    );
  }
}
