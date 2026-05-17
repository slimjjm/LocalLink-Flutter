import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AddBlockTimeScreen extends StatefulWidget {

  final String businessId;
  final String staffId;

  const AddBlockTimeScreen({
    super.key,
    required this.businessId,
    required this.staffId,
  });

  @override
  State<AddBlockTimeScreen> createState() =>
      _AddBlockTimeScreenState();
}

class _AddBlockTimeScreenState
    extends State<AddBlockTimeScreen> {

  DateTime startTime =
      DateTime.now().add(
    const Duration(hours: 1),
  );

  DateTime endTime =
      DateTime.now().add(
    const Duration(hours: 2),
  );

  String selectedReason = 'Lunch';

  bool isSaving = false;

  final reasons = [
    'Lunch',
    'Holiday',
    'Training',
    'Sick',
    'Personal',
  ];

  // =====================================================
  // DATE ONLY
  // =====================================================

  DateTime dateOnly(DateTime date) {

    return DateTime(
      date.year,
      date.month,
      date.day,
    );
  }

  // =====================================================
  // FORMAT DATE
  // =====================================================

  String formatDate(DateTime date) {

    final local =
        date.toLocal();

    final day =
        local.day.toString().padLeft(2, '0');

    final month =
        local.month.toString().padLeft(2, '0');

    final year =
        local.year;

    final hour =
        local.hour.toString().padLeft(2, '0');

    final minute =
        local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year  $hour:$minute';
  }

  // =====================================================
  // PICK START
  // =====================================================

  Future<void> pickStart() async {

    final pickedDate =
        await showDatePicker(

      context: context,

      initialDate:
          dateOnly(startTime),

      firstDate: DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      ),

      lastDate: DateTime.now()
          .add(const Duration(days: 365)),
    );

    if (pickedDate == null) return;

    final pickedTime =
        await showTimePicker(

      context: context,

      initialTime:
          TimeOfDay.fromDateTime(
        startTime,
      ),
    );

    if (pickedTime == null) return;

    final newStart = DateTime(

      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {

      startTime = newStart;

      // =====================================
      // AUTO FIX END TIME
      // =====================================

      if (endTime.isBefore(startTime) ||
          endTime.isAtSameMomentAs(startTime)) {

        endTime =
            startTime.add(
          const Duration(hours: 1),
        );
      }
    });
  }

  // =====================================================
  // PICK END
  // =====================================================

  Future<void> pickEnd() async {

    final pickedDate =
        await showDatePicker(

      context: context,

      initialDate:
          dateOnly(endTime),

      firstDate:
          dateOnly(startTime),

      lastDate: DateTime.now()
          .add(const Duration(days: 365)),
    );

    if (pickedDate == null) return;

    final pickedTime =
        await showTimePicker(

      context: context,

      initialTime:
          TimeOfDay.fromDateTime(
        endTime,
      ),
    );

    if (pickedTime == null) return;

    setState(() {

      endTime = DateTime(

        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  // =====================================================
  // SAVE BLOCK
  // =====================================================

  Future<void> saveBlock() async {

    if (endTime.isBefore(startTime) ||
        endTime.isAtSameMomentAs(startTime)) {

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(

          content: Text(
            'End time must be after start time',
          ),
        ),
      );

      return;
    }

    try {

      setState(() {
        isSaving = true;
      });

      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .collection('timeBlocks')
          .add({

        'staffId':
            widget.staffId,

        'startTime':
            Timestamp.fromDate(startTime),

        'endTime':
            Timestamp.fromDate(endTime),

        'title':
            selectedReason,

        'createdAt':
            Timestamp.now(),
      });

      // =====================================
      // REGENERATE AVAILABILITY
      // =====================================

      try {

        final callable =
            FirebaseFunctions.instance
                .httpsCallable(
          'regenerateAvailability',
        );

        await callable.call({

          'businessId':
              widget.businessId,

          'staffId':
              widget.staffId,
        });

      } catch (e) {

        print(
          '⚠️ Regen failed: $e',
        );
      }

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(
          content: Text(
            'Block created',
          ),
        ),
      );

    } catch (e) {

      ScaffoldMessenger.of(context)
          .showSnackBar(

        SnackBar(
          content: Text(
            'Error: $e',
          ),
        ),
      );
    }

    if (mounted) {

      setState(() {
        isSaving = false;
      });
    }
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {

    final invalidTime =
        endTime.isBefore(startTime) ||
        endTime.isAtSameMomentAs(startTime);

    return Scaffold(

      appBar: AppBar(
        title:
            const Text('Block Time'),
      ),

      body: Padding(

        padding:
            const EdgeInsets.all(20),

        child: Column(

          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [

            // =====================================
            // REASON
            // =====================================

            const Text(

              'Reason',

              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            DropdownButton<String>(

              value: selectedReason,

              isExpanded: true,

              items:
                  reasons.map((reason) {

                return DropdownMenuItem(

                  value: reason,

                  child: Text(reason),
                );

              }).toList(),

              onChanged: (value) {

                if (value == null) return;

                setState(() {
                  selectedReason = value;
                });
              },
            ),

            const SizedBox(height: 30),

            // =====================================
            // START
            // =====================================

            Card(

              child: ListTile(

                title:
                    const Text('Start'),

                subtitle:
                    Text(
                  formatDate(startTime),
                ),

                trailing:
                    const Icon(Icons.edit),

                onTap: pickStart,
              ),
            ),

            const SizedBox(height: 12),

            // =====================================
            // END
            // =====================================

            Card(

              child: ListTile(

                title:
                    const Text('End'),

                subtitle:
                    Text(
                  formatDate(endTime),
                ),

                trailing:
                    const Icon(Icons.edit),

                onTap: pickEnd,
              ),
            ),

            // =====================================
            // VALIDATION
            // =====================================

            if (invalidTime) ...[

              const SizedBox(height: 16),

              const Text(

                '⚠ End time must be after start time',

                style: TextStyle(
                  color: Colors.red,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],

            const Spacer(),

            // =====================================
            // SAVE
            // =====================================

            SizedBox(

              width: double.infinity,

              child: ElevatedButton(

                onPressed:
                    isSaving || invalidTime
                        ? null
                        : saveBlock,

                child:

                    isSaving

                        ? const SizedBox(

                            height: 20,
                            width: 20,

                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )

                        : const Text(
                            'Save Block',
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}