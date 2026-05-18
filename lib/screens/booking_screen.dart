import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'login_screen.dart';
import 'booking_success_screen.dart';

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
final TextEditingController
    nameController =
        TextEditingController();

final TextEditingController
    addressController =
        TextEditingController();
  DateTime selectedDate = DateTime.now();

// 🔹 PAYMENT
String selectedPaymentMethod = '';

 @override
void initState() {
  super.initState();
  print("🟢 INIT STATE RUNNING"); // 👈 add this line
  loadSlots();
}

  // =====================================================
  // 🔹 LOAD SLOTS
  // =====================================================
Future<void> loadSlots() async {

  try {

    print("🚀 LOAD SLOTS START");

    setState(() => isLoadingSlots = true);

    // =====================================
    // LOAD ALLOWED STAFF
    // =====================================

    final staffSnapshot =
        await FirebaseFirestore.instance
            .collection('businesses')
            .doc(widget.businessId)
            .collection('staff')
            .where(
              'serviceIds',
              arrayContains:
                  widget.serviceId,
            )
            .where(
              'isActive',
              isEqualTo: true,
            )
            .get();

    allowedStaffIds =
        staffSnapshot.docs
            .map((doc) => doc.id)
            .toList();

    print(
      "👥 ALLOWED STAFF: $allowedStaffIds",
    );

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

    final endOfDay =
        startOfDay.add(
          const Duration(days: 1),
        );

    // =====================================
    // LOAD AVAILABLE SLOTS
    // =====================================
final snapshot =
    await FirebaseFirestore.instance
        .collectionGroup(
          'availableSlots',
        )
        .where(
          'businessId',
          isEqualTo: widget.businessId,
        )
        .where(
          'staffId',
          whereIn: allowedStaffIds,
        )
        .where(
          'isBooked',
          isEqualTo: false,
        )
        .where(
          'startTime',
          isGreaterThanOrEqualTo:
              Timestamp.fromDate(startOfDay),
        )
        .where(
          'startTime',
          isLessThan:
              Timestamp.fromDate(endOfDay),
        )
        .orderBy('startTime')
        .get();
final slots =
    snapshot.docs.map((doc) {

  final data =
      doc.data();

  return {

    'id': doc.id,

    'slotPath':
        doc.reference.path,

    'staffId':
        data['staffId'],

    'staffName':
        data['staffName'],

    ...data,
  };

}).toList();

slots.sort((a, b) {

  final aTime =
      (a['startTime'] as Timestamp)
          .toDate();

  final bTime =
      (b['startTime'] as Timestamp)
          .toDate();

  return aTime.compareTo(bTime);
});

print(
  "📦 TOTAL SLOTS FOUND: ${snapshot.docs.length}",
);

print(
  "✅ FILTERED SLOTS: ${slots.length}",
);

    setState(() {

      availableSlots = slots;

      isLoadingSlots = false;
    });

  } catch (e) {

    print(
      "🔥 LOAD SLOTS ERROR: $e",
    );

    setState(() {

      isLoadingSlots = false;
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(

      SnackBar(
        content:
            Text(
              'Error loading slots: $e',
            ),
      ),
    );
  }
}
  // =====================================================
  // 🔹 FILTER BY DATE
  // =====================================================
bool hasEnoughConsecutiveSlots(
  Map<String, dynamic> slot,
) {

  final durationMinutes =
      widget.serviceData['durationMinutes'] ?? 30;

  final slotsRequired =
      (durationMinutes / 30).ceil();

  final start =
      (slot['startTime'] as Timestamp)
          .toDate();

  final staffId =
      slot['staffId'];

  for (int i = 1; i < slotsRequired; i++) {

    final nextStart =
        start.add(Duration(minutes: i * 30));

    final exists =
        availableSlots.any((s) {

      final sStart =
          (s['startTime'] as Timestamp)
              .toDate();

      return
          s['staffId'] == staffId &&
          sStart == nextStart;
    });

    if (!exists) {
      return false;
    }
  }

  return true;
}

List<Map<String, dynamic>> get filteredSlots {

  final now = DateTime.now();

  return availableSlots.where((slot) {

   final date =
    (slot['startTime'] as Timestamp)
        .toDate()
        .toLocal();

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

    // REQUIRED NOTICE (2 HOURS)

    final minimumBookingTime =
        now.add(const Duration(hours: 2));

    if (date.isBefore(minimumBookingTime)) {
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
  print("🔎 FINDING NEXT AVAILABLE");

 final snapshot = await FirebaseFirestore.instance
    .collectionGroup('availableSlots')
    .where(
      'businessId',
      isEqualTo: widget.businessId,
    )
    .where(
      'staffId',
      whereIn: allowedStaffIds,
    )
    .where(
      'isBooked',
      isEqualTo: false,
    )
    .where(
      'startTime',
      isGreaterThan:
          Timestamp.fromDate(
            DateTime.now()
                .add(const Duration(hours: 2)),
          ),
    )
    .orderBy('startTime')
    .limit(1)
    .get();
  if (snapshot.docs.isEmpty) {
    print("❌ No future slots");
    return;
  }

  final next = (snapshot.docs.first['startTime'] as Timestamp).toDate();

  print("✅ NEXT SLOT: $next");

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

  final pounds =
      (price as num) / 100;

  return '£${pounds.toStringAsFixed(2)}';
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

    if (picked != null) {
  setState(() {
    selectedDate = picked;
    selectedSlotId = null;
    selectedSlot = null;
  });

  await loadSlots(); // 🔥 REQUIRED
}
  }

  // =====================================================
  // 🔹 CASH BOOKING
  // =====================================================

  Future<void> createCashBooking() async {
  try {
    final callable = FirebaseFunctions.instance
        .httpsCallable('createCashBooking');

await callable.call({
  'businessId': widget.businessId,
  'staffId': selectedSlot!['staffId'],
  'serviceId': widget.serviceId,
  'slotId': selectedSlot!['id'],
  'slotPath': selectedSlot!['slotPath'],

  'paymentMethod': 'cash',

 'customerName':
    nameController.text.trim(),

'customerAddress':
    addressController.text.trim(),
});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Booking confirmed')),
    );

  Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (_) => BookingSuccessScreen(
      serviceName: widget.serviceData['name'] ?? 'Service',
      businessName: widget.businessName,
      bookingDate:
          (selectedSlot!['startTime'] as Timestamp).toDate(),
      isCashBooking: true,
    ),
  ),
);

  } catch (e) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

  // =====================================================
  // 🔹 STRIPE
  // =====================================================
Future<void> startStripeBooking() async {
  try {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception("Not logged in");
    }

    if (selectedSlot == null) {
      throw Exception("No slot selected");
    }

    final callable = FirebaseFunctions.instance
        .httpsCallable('createBookingPaymentIntent');

final result = await callable.call({
  'businessId': widget.businessId,
  'staffId': selectedSlot!['staffId'],
  'serviceId': widget.serviceId,
  'slotId': selectedSlot!['id'],
  'slotPath': selectedSlot!['slotPath'],

  'paymentMethod': 'stripe',
});

    final clientSecret = result.data['clientSecret'];

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'LocalLink',
      ),
    );

    await Stripe.instance.presentPaymentSheet();

    if (!mounted) return;

   ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(
    content: Text('Payment received. Confirming booking...'),
  ),
);

   Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (_) => BookingSuccessScreen(
      serviceName: widget.serviceData['name'] ?? 'Service',
      businessName: widget.businessName,
      bookingDate:
          (selectedSlot!['startTime'] as Timestamp).toDate(),
      isCashBooking: false,
    ),
  ),
);

  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
  }
}

  // =====================================================
  // 🔹 ROUTER
  // ===================================================

 
Future<void> handleBooking() async {
  if (isProcessingBooking) return;

  final user = FirebaseAuth.instance.currentUser;

  final isLoggedIn =
      user != null && !user.isAnonymous;

  if (!isLoggedIn) {
    showLoginSheet();
    return;
  }

  if (selectedSlot == null || selectedPaymentMethod.isEmpty) {
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
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
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
                  MaterialPageRoute(
                    builder: (_) =>
                        const LoginScreen(),
                  ),
                );
              },

              child: const Text("Continue"),
            ),

            const SizedBox(height: 10),

            TextButton(
              onPressed: () =>
                  Navigator.pop(context),

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
            Text(serviceName,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),

            const SizedBox(height: 8),
            Text(duration == null ? price : '$price • $duration mins'),

            const SizedBox(height: 20),

            // DATE
            const Text('Select a date',
                style: TextStyle(fontWeight: FontWeight.bold)),

            Row(
              children: [
                Text(
                  '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                ),
                const Spacer(),
                TextButton(
                  onPressed: pickDate,
                  child: const Text('Change'),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // TIME
            const Text('Select a time',
                style: TextStyle(fontWeight: FontWeight.bold)),

            if (isLoadingSlots)
              const Center(child: CircularProgressIndicator()),

            if (!isLoadingSlots && filteredSlots.isEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("No slots for this day"),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: goToNextAvailableDate,
                    child: const Text("View next available"),
                  ),
                ],
              ),

            if (!isLoadingSlots && filteredSlots.isNotEmpty)
              Wrap(
                spacing: 10,
                children: filteredSlots.map((slot) {
                  final time = formatTime(slot['startTime']);
                  final isSelected = selectedSlotId == slot['id'];

                  return ChoiceChip(
                   label: Text(
  '$time • ${slot['staffName']} • ${duration}m',
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
if (selectedSlot != null)
  Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      'Selected staff: ${selectedSlot!['staffName']}',
      style: const TextStyle(
        fontWeight: FontWeight.bold,
      ),
    ),
  ),
            const Spacer(),
const SizedBox(height: 20),

const Text(
  'Your details',
  style: TextStyle(
    fontWeight: FontWeight.bold,
  ),
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

const SizedBox(height: 20),
            // PAYMENT
            const Text('Select payment method',
                style: TextStyle(fontWeight: FontWeight.bold)),

            Wrap(
              spacing: 10,
              children: widget.paymentMethods.map((method) {
                final isSelected =
    selectedPaymentMethod == method.toLowerCase().trim();

                return ChoiceChip(
                  label: Text(
  method.toLowerCase() == 'stripe'
      ? 'Card'
      : 'Cash',
),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      selectedPaymentMethod =
                          method.toLowerCase().trim();
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

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
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
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