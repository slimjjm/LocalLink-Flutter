import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_block_time_screen.dart';

class BusinessCalendarScreen extends StatefulWidget {

  final String businessId;

  const BusinessCalendarScreen({
    super.key,
    required this.businessId,
  });

  @override
  State<BusinessCalendarScreen> createState() =>
      _BusinessCalendarScreenState();
}

class _BusinessCalendarScreenState
    extends State<BusinessCalendarScreen> {

  DateTime selectedDate = DateTime.now();

  bool isLoading = true;

  List<QueryDocumentSnapshot> bookings = [];
  List<QueryDocumentSnapshot> staff = [];

  @override
  void initState() {
    super.initState();
    loadBookings();
loadStaff();
  }

// =====================================================
// LOAD BOOKINGS + DAY BLOCKS
// =====================================================

List<QueryDocumentSnapshot> dayBlocks = [];

Future<void> loadBookings() async {

  try {

    setState(() {
      isLoading = true;
    });

    final startOfDay = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );

    final endOfDay =
        startOfDay.add(
          const Duration(days: 1),
        );

     

    // =====================================================
    // LOAD BOOKINGS
    // =====================================================

    final bookingSnapshot =
        await FirebaseFirestore.instance
            .collection('bookings')
            .where(
              'businessId',
              isEqualTo: widget.businessId,
            )
            .where(
              'startDate',
              isGreaterThanOrEqualTo:
                  Timestamp.fromDate(startOfDay),
            )
            .where(
              'startDate',
              isLessThan:
                  Timestamp.fromDate(endOfDay),
            )
            .orderBy('startDate')
            .get();

    // =====================================================
    // LOAD STAFF DAY BLOCKS
    // =====================================================

    List<QueryDocumentSnapshot> allBlocks = [];

    for (final staffDoc in staff) {

      final blockSnapshot =
          await FirebaseFirestore.instance
              .collection('businesses')
              .doc(widget.businessId)
              .collection('staff')
              .doc(staffDoc.id)
              .collection('dayBlocks')
              .where(
                'startDate',
                isLessThan:
                    Timestamp.fromDate(endOfDay),
              )
              .where(
                'endDate',
                isGreaterThanOrEqualTo:
                    Timestamp.fromDate(startOfDay),
              )
              .get();

      allBlocks.addAll(blockSnapshot.docs);
    }

    setState(() {

      bookings =
          bookingSnapshot.docs;

      dayBlocks =
          allBlocks;

      isLoading = false;
    });

  } catch (e) {

    print(
      "🔥 CALENDAR LOAD ERROR: $e",
    );

    setState(() {
      isLoading = false;
    });
  }
}
   Future<void> loadStaff() async {

  final snapshot =
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .collection('staff')
          .where(
            'isActive',
            isEqualTo: true,
          )
          .orderBy('seatRank')
          .get();

  setState(() {

    staff = snapshot.docs;
  });
}
  // =====================================================
  // DATE PICKER
  // =====================================================

  Future<void> pickDate() async {

    final picked =
        await showDatePicker(
          context: context,
          initialDate: selectedDate,
          firstDate:
              DateTime.now()
                  .subtract(
                    const Duration(days: 365),
                  ),
          lastDate:
              DateTime.now()
                  .add(
                    const Duration(days: 365),
                  ),
        );

    if (picked != null) {

      setState(() {
        selectedDate = picked;
      });

      await loadBookings();
    }
  }
Future<void> showStaffPicker() async {

  if (staff.isEmpty) {

    ScaffoldMessenger.of(context)
        .showSnackBar(

      const SnackBar(
        content: Text(
          'No active staff',
        ),
      ),
    );

    return;
  }

  showModalBottomSheet(

    context: context,

    builder: (_) {

      return SafeArea(

        child: ListView.builder(

          shrinkWrap: true,

          itemCount: staff.length,

          itemBuilder: (context, index) {

            final data =
                staff[index].data()
                    as Map<String, dynamic>;

            final staffId =
                staff[index].id;

            final staffName =
                data['name'] ?? 'Staff';

            return ListTile(

              title: Text(staffName),

              leading:
                  const Icon(Icons.person),

              onTap: () async {

                Navigator.pop(context);

                await Navigator.push(

                  context,

                  MaterialPageRoute(

                    builder: (_) =>
                        AddBlockTimeScreen(

                      businessId:
                          widget.businessId,

                      staffId: staffId,
                    ),
                  ),
                );

                await loadBookings();
              },
            );
          },
        ),
      );
    },
  );
}
  // =====================================================
  // HELPERS
  // =====================================================

  String formatTime(Timestamp timestamp) {

    final date =
        timestamp.toDate();

    return
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  Color statusColor(String status) {

    switch (status) {

      case 'confirmed':
        return Colors.green;

      case 'pending_payment':
        return Colors.orange;

      case 'completed':
        return Colors.blue;

      case 'cancelled_by_customer':
      case 'cancelled_by_business':
      case 'payment_failed':
        return Colors.red;

      default:
        return Colors.grey;
    }
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(
floatingActionButton:
    FloatingActionButton(

  onPressed: showStaffPicker,

  child: const Icon(
    Icons.block,
  ),
),
      appBar: AppBar(

        title:
            const Text(
              'Business Calendar',
            ),

        actions: [

          IconButton(

            onPressed: pickDate,

            icon:
                const Icon(
                  Icons.calendar_month,
                ),
          ),
        ],
      ),

      body: Padding(

        padding:
            const EdgeInsets.all(16),

        child: Column(

          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [

            Text(

              '${selectedDate.day}/'
              '${selectedDate.month}/'
              '${selectedDate.year}',

              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            // =====================================================
// DAY BLOCKS
// =====================================================

if (!isLoading && dayBlocks.isNotEmpty)

  Container(

    margin:
        const EdgeInsets.only(
      bottom: 20,
    ),

    child: Column(

      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [

        const Text(

          'Staff Time Off',

          style: TextStyle(
            fontSize: 18,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        const SizedBox(height: 12),

        ...dayBlocks.map((doc) {

          final data =
              doc.data()
                  as Map<String, dynamic>;

          final staffName =
              data['staffName']
                  ?? 'Staff';

          final type =
              data['type']
                  ?? 'blocked';

          final reason =
              data['reason']
                  ?? '';

          Color color;

          switch (type) {

            case 'holiday':
              color = Colors.purple;
              break;

            case 'sick':
              color = Colors.red;
              break;

            case 'training':
              color = Colors.indigo;
              break;

            default:
              color = Colors.orange;
          }

          return Card(

            child: ListTile(

              leading: CircleAvatar(

                backgroundColor: color,

                child: const Icon(
                  Icons.block,
                  color: Colors.white,
                ),
              ),

              title: Text(staffName),

              subtitle: Text(
                type.toUpperCase(),
              ),

              trailing:
                  reason.isEmpty
                      ? null
                      : Text(reason),
            ),
          );
        }),
      ],
    ),
  ),

            if (isLoading)
              const Expanded(
                child: Center(
                  child:
                      CircularProgressIndicator(),
                ),
              ),

            if (!isLoading && bookings.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No bookings for this day',
                  ),
                ),
              ),

            if (!isLoading && bookings.isNotEmpty)
              Expanded(

                child: ListView.builder(

                  itemCount: bookings.length,

                  itemBuilder: (context, index) {

                    final booking =
                        bookings[index]
                            .data()
                            as Map<String, dynamic>;

                    final status =
                        booking['status'] ?? '';

                    final serviceName =
                        booking['serviceName']
                        ?? 'Service';

                    final customerName =
                        booking['customerName']
                        ?? 'Customer';

                    final staffName =
                        booking['staffName']
                        ?? 'Staff';

                    final startDate =
                        booking['startDate']
                        as Timestamp;

                    final endDate =
                        booking['endDate']
                        as Timestamp;

                    final price =
                        booking['price'] ?? 0;

                    final pounds =
                        (price as num) / 100;

                    return Card(

                      margin:
                          const EdgeInsets.only(
                            bottom: 12,
                          ),

                      child: ListTile(

                        contentPadding:
                            const EdgeInsets.all(16),

                        leading: CircleAvatar(

                          backgroundColor:
                              statusColor(status),

                          child: Text(
                            formatTime(startDate),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),

                        title: Text(
                          serviceName,
                          style: const TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        subtitle: Padding(

                          padding:
                              const EdgeInsets.only(
                                top: 8,
                              ),

                          child: Column(

                            crossAxisAlignment:
                                CrossAxisAlignment.start,

                            children: [

                              Text(
                                'Customer: $customerName',
                              ),

                              Text(
                                'Staff: $staffName',
                              ),

                              Text(
                                '${formatTime(startDate)} - ${formatTime(endDate)}',
                              ),

                              Text(
                                '£${pounds.toStringAsFixed(2)}',
                              ),

                              const SizedBox(height: 6),

                              Container(

                                padding:
                                    const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),

                                decoration: BoxDecoration(

                                  color:
                                      statusColor(status)
                                          .withOpacity(0.15),

                                  borderRadius:
                                      BorderRadius.circular(20),
                                ),

                                child: Text(

                                  status.replaceAll('_', ' '),

                                  style: TextStyle(
                                    color:
                                        statusColor(status),
                                    fontWeight:
                                        FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        onTap: () {

                          // NEXT:
                          // Booking detail screen
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}