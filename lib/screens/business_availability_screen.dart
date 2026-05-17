import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class BusinessAvailabilityScreen
    extends StatefulWidget {

  final String businessId;
  final String staffId;
  final String staffName;

  const BusinessAvailabilityScreen({
    super.key,
    required this.businessId,
    required this.staffId,
    required this.staffName,
  });

  @override
  State<BusinessAvailabilityScreen>
      createState() =>
          _BusinessAvailabilityScreenState();
}

class _BusinessAvailabilityScreenState
    extends State<BusinessAvailabilityScreen> {

  final List<String> days = [

    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  Map<String, bool> enabledDays = {};

  Map<String, TimeOfDay> startTimes = {};

  Map<String, TimeOfDay> endTimes = {};

  bool isLoading = true;

  // =====================================
  // INIT
  // =====================================

  @override
  void initState() {
    super.initState();

    loadAvailability();
  }

  // =====================================
  // LOAD
  // =====================================

  Future<void> loadAvailability() async {

  // =====================================
  // DEFAULT VALUES
  // =====================================

  for (final day in days) {

    enabledDays[day] = false;

    startTimes[day] =
        const TimeOfDay(hour: 9, minute: 0);

    endTimes[day] =
        const TimeOfDay(hour: 17, minute: 0);
  }

  try {

    final snapshot = await FirebaseFirestore.instance
        .collection('businesses')
.doc(widget.businessId)
.collection('staff')
.doc(widget.staffId)
.collection('weeklyAvailability')
        .get();

    for (final doc in snapshot.docs) {

      final data = doc.data();

      final day = doc.id;

      final open =
          (data['open'] ?? '09:00')
              .split(':');

      final close =
          (data['close'] ?? '17:00')
              .split(':');

      enabledDays[day] =
          !(data['closed'] ?? true);

      startTimes[day] = TimeOfDay(

        hour: int.parse(open[0]),
        minute: int.parse(open[1]),
      );

      endTimes[day] = TimeOfDay(

        hour: int.parse(close[0]),
        minute: int.parse(close[1]),
      );
    }

  } catch (e) {

    debugPrint(
      'Availability load error: $e',
    );
  }

  setState(() {

    isLoading = false;
  });
}

  // =====================================
  // SAVE
  // =====================================

  Future<void> saveAvailability() async {

  setState(() {
    isLoading = true;
  });

  try {

    for (final day in days) {

      final start = startTimes[day]!;
      final end = endTimes[day]!;

      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .collection('staff')
          .doc(widget.staffId)
          .collection('weeklyAvailability')
          .doc(day)
          .set({

        'open':
            '${start.hour.toString().padLeft(2, '0')}:'
            '${start.minute.toString().padLeft(2, '0')}',

        'close':
            '${end.hour.toString().padLeft(2, '0')}:'
            '${end.minute.toString().padLeft(2, '0')}',

        'closed':
            !(enabledDays[day] ?? false),
            
            'staffName': widget.staffName,
      });
    }
// =====================================
// REGENERATE AVAILABLE SLOTS
// =====================================

HttpsCallable callable =
    FirebaseFunctions.instance
        .httpsCallable(
            'regenerateAvailability');

await callable.call({

  'businessId': widget.businessId,

  'staffId': widget.staffId,
});
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(

      const SnackBar(
        content: Text(
          'Availability saved',
        ),
      ),
    );

  } catch (e) {

    debugPrint('SAVE ERROR: $e');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(

      SnackBar(
        content: Text(
          'Save failed: $e',
        ),
      ),
    );
  }

  setState(() {
    isLoading = false;
  });
}

  // =====================================
  // TIME PICKER
  // =====================================

  Future<void> pickTime({

    required String day,
    required bool isStart,
  }) async {

    final initialTime = isStart
        ? startTimes[day]!
        : endTimes[day]!;

    final picked = await showTimePicker(

      context: context,

      initialTime: initialTime,
    );

    if (picked == null) return;

    setState(() {

      if (isStart) {

        startTimes[day] = picked;

      } else {

        endTimes[day] = picked;
      }
    });
  }

  // =====================================
  // UI
  // =====================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(

       title:
    Text('${widget.staffName} Availability'),

        actions: [

          IconButton(

            onPressed:
                isLoading
                    ? null
                    : saveAvailability,

            icon: const Icon(Icons.save),
          ),
        ],
      ),

      body:
          isLoading

              ? const Center(
                  child:
                      CircularProgressIndicator(),
                )

              : ListView.builder(

                  padding:
                      const EdgeInsets.all(20),

                  itemCount: days.length,

                  itemBuilder: (context, index) {

                    final day = days[index];

                    return Card(

                      margin:
                          const EdgeInsets.only(
                        bottom: 16,
                      ),

                      child: Padding(

                        padding:
                            const EdgeInsets.all(16),

                        child: Column(

                          crossAxisAlignment:
                              CrossAxisAlignment.start,

                          children: [

                            Row(

                              mainAxisAlignment:
                                  MainAxisAlignment
                                      .spaceBetween,

                              children: [

                                Text(

                                  day.toUpperCase(),

                                  style: const TextStyle(

                                    fontSize: 18,

                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),

                                Switch(

                                  value:
                                      enabledDays[day] ??
                                          false,

                                  onChanged: (value) {

                                    setState(() {

                                      enabledDays[day] =
                                          value;
                                    });
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            if (enabledDays[day] == true)

                              Row(

                                children: [

                                  Expanded(

                                    child:
                                        ElevatedButton(

                                      onPressed: () {

                                        pickTime(

                                          day: day,
                                          isStart: true,
                                        );
                                      },

                                      child: Text(

                                        'Start: '
                                        '${startTimes[day]!.format(context)}',
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  Expanded(

                                    child:
                                        ElevatedButton(

                                      onPressed: () {

                                        pickTime(

                                          day: day,
                                          isStart: false,
                                        );
                                      },

                                      child: Text(

                                        'End: '
                                        '${endTimes[day]!.format(context)}',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}