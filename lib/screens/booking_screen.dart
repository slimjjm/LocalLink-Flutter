import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'login_screen.dart';
import 'booking_success_screen.dart';
import 'booking_summary_screen.dart';
import 'booking_confirmation_wait_screen.dart';

const Duration kShortNoticeApprovalWindow = Duration(hours: 2);

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
  // 🔹 CASH BOOKING
  // =====================================================

  Future<void> createCashBooking() async {
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
        'paymentMethod': 'cash',
        'customerName': nameController.text.trim(),
        'customerAddress': addressController.text.trim(),
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
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception("Not logged in");
      }

      if (selectedSlot == null) {
        throw Exception("No slot selected");
      }

      final callable = FirebaseFunctions.instance.httpsCallable(
        isDirectAvailability
            ? 'createDirectAvailabilityPaymentIntent'
            : 'createBookingPaymentIntent',
      );

      final payload = {
        'businessId': widget.businessId,
        'serviceId': widget.serviceId,
        'availabilityPostId': widget.serviceData['availabilityPostId'],
        'selectedStartMillis': (selectedSlot!['startTime'] as Timestamp)
            .toDate()
            .millisecondsSinceEpoch,
        'paymentMethod': 'stripe',
        'customerName': nameController.text.trim(),
        'customerAddress': addressController.text.trim(),
        'customerNotes': notesController.text.trim(),
      };

      if (!isDirectAvailability) {
        payload.addAll({
          'staffId': selectedSlot!['staffId'],
          'slotId': selectedSlot!['id'],
          'slotPath': selectedSlot!['slotPath'],
        });
      }

      final result = await callable.call(payload);
      pendingBookingId = result.data['bookingId']?.toString();

      final clientSecret = result.data['clientSecret'];

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'LocalLink',
        ),
      );

      await Stripe.instance.presentPaymentSheet();

      if (!mounted) return;

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
        debugPrint('Stripe booking failed before completion: $error');
        debugPrintStack(stackTrace: stack);
      }
      if (pendingBookingId != null && pendingBookingId.isNotEmpty) {
        await _releasePendingCardBooking(pendingBookingId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _paymentErrorMessage(error),
          ),
        ),
      );
    }
  }

  Future<void> _releasePendingCardBooking(String bookingId) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('cancelPendingCardBooking')
          .call({'bookingId': bookingId});
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('Unable to release pending card booking $bookingId: $error');
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
      return error.error.localizedMessage ??
          'We could not complete your payment. Please try again.';
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
      return;
    }

    if (!mounted) return;

    final stillAvailable = await _validateSelectedAvailability();
    if (!mounted) return;

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
        await createCashBooking();
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
                onPressed: () {
                  Navigator.pop(context);

                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
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
      appBar: AppBar(title: Text(serviceName)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              serviceName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),
            Text(duration == null ? price : '$price • $duration mins'),

            const SizedBox(height: 20),

            if (!isDirectAvailability || availabilityType == 'window') ...[
              const Text(
                'Choose a day',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Text(
                    '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                  ),
                  const Spacer(),
                  TextButton(onPressed: pickDate, child: const Text('Change')),
                ],
              ),
              const SizedBox(height: 20),
            ],

            // TIME
            const Text(
              'Choose a time',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            if (hasAvailabilityContext)
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  'You chose this from the business\'s free time.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),

            if (isDirectAvailability && selectedSlot != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, color: Colors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${formatTime(selectedSlot!['startTime'])} • ${duration ?? 30}m',
                        style: const TextStyle(fontWeight: FontWeight.bold),
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
              const Center(child: CircularProgressIndicator()),

            if (!isDirectAvailability &&
                !isLoadingSlots &&
                filteredSlots.isEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("No appointments that day"),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: goToNextAvailableDate,
                    child: const Text("Find another time"),
                  ),
                ],
              ),

            if (!isDirectAvailability &&
                !isLoadingSlots &&
                filteredSlots.isNotEmpty)
              Wrap(
                spacing: 10,
                children: filteredSlots.map((slot) {
                  final time = formatTime(slot['startTime']);
                  final isSelected = selectedSlotId == slot['id'];

                  return ChoiceChip(
                    label: Text('$time • ${slot['staffName']} • ${duration}m'),
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
            if (selectedSlot != null && !isDirectAvailability)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'With ${selectedSlot!['staffName']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            const Spacer(),
            const SizedBox(height: 20),

            const Text(
              'Your details',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            TextField(
              controller: nameController,

              decoration: const InputDecoration(
                labelText: 'Your name',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: addressController,

              decoration: const InputDecoration(
                labelText: 'Address',
                border: OutlineInputBorder(),
              ),

              maxLines: 2,
            ),

            const SizedBox(height: 12),

            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Notes for the business',
                hintText: 'Access details, preferences or anything useful',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 20),
            // PAYMENT
            const Text(
              'How would you like to pay?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            Wrap(
              spacing: 10,
              children: widget.paymentMethods.map((method) {
                final isSelected =
                    selectedPaymentMethod == method.toLowerCase().trim();

                return ChoiceChip(
                  label: Text(
                    method.toLowerCase() == 'stripe' ? 'Card' : 'Cash',
                  ),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      selectedPaymentMethod = method.toLowerCase().trim();
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            if (selectedSlot != null &&
                _requiresBusinessApproval(selectedSlot!)) ...[
              const Text(
                'This starts soon, so the business will quickly confirm they can still fit you in.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
            ],

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed:
                    (selectedSlot == null ||
                        selectedPaymentMethod.isEmpty ||
                        isProcessingBooking)
                    ? null
                    : handleBooking,

                child: isProcessingBooking
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        selectedPaymentMethod == 'stripe'
                            ? 'Pay Now'
                            : 'Confirm Booking',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
