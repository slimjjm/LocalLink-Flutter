import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class BusinessAvailabilityScreen extends StatefulWidget {
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
  State<BusinessAvailabilityScreen> createState() =>
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

  TimeOfDay _parseTimeOfDay(dynamic value, TimeOfDay fallback) {
    final parts = value?.toString().split(':') ?? const <String>[];
    if (parts.length != 2) return fallback;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return fallback;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

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

      startTimes[day] = const TimeOfDay(hour: 9, minute: 0);

      endTimes[day] = const TimeOfDay(hour: 17, minute: 0);
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .collection('staff')
          .doc(widget.staffId)
          .collection('weeklyAvailability')
          .get();

      if (!mounted) return;

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final day = doc.id;

        enabledDays[day] = !(data['closed'] ?? true);

        startTimes[day] = _parseTimeOfDay(
          data['open'],
          const TimeOfDay(hour: 9, minute: 0),
        );

        endTimes[day] = _parseTimeOfDay(
          data['close'],
          const TimeOfDay(hour: 17, minute: 0),
        );
      }
    } catch (_) {}

    if (!mounted) return;

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

              'closed': !(enabledDays[day] ?? false),

              'staffName': widget.staffName,
            });
      }
      // =====================================
      // REGENERATE AVAILABLE SLOTS
      // =====================================

      HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
        'regenerateAvailability',
      );

      await callable.call({
        'businessId': widget.businessId,

        'staffId': widget.staffId,
      });
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Working times saved')));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('We could not save working times. Please try again.'),
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

  Future<void> pickTime({required String day, required bool isStart}) async {
    final initialTime = isStart ? startTimes[day]! : endTimes[day]!;

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
        title: Text('${widget.staffName} Working Times'),

        actions: [
          IconButton(
            onPressed: isLoading ? null : saveAvailability,

            icon: const Icon(Icons.save),
          ),
        ],
      ),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(20),

              itemCount: days.length,

              itemBuilder: (context, index) {
                final day = days[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),

                  child: Padding(
                    padding: const EdgeInsets.all(16),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,

                          children: [
                            Text(
                              day.toUpperCase(),

                              style: const TextStyle(
                                fontSize: 18,

                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            Switch(
                              value: enabledDays[day] ?? false,

                              onChanged: (value) {
                                setState(() {
                                  enabledDays[day] = value;
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
                                child: ElevatedButton(
                                  onPressed: () {
                                    pickTime(day: day, isStart: true);
                                  },

                                  child: Text(
                                    'Start: '
                                    '${startTimes[day]!.format(context)}',
                                  ),
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    pickTime(day: day, isStart: false);
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
