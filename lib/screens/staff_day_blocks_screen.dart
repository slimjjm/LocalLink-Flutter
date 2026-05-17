import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'add_block_time_screen.dart';

class StaffDayBlocksScreen
    extends StatelessWidget {

  final String businessId;
  final String staffId;
  final String staffName;

  const StaffDayBlocksScreen({
    super.key,
    required this.businessId,
    required this.staffId,
    required this.staffName,
  });

  // =====================================================
  // DELETE BLOCK
  // =====================================================

  Future<void> deleteBlock(
    String businessId,
    String blockId,
  ) async {

    await FirebaseFirestore.instance
        .collection('businesses')
        .doc(businessId)
        .collection('timeBlocks')
        .doc(blockId)
        .delete();
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
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title:
            Text('$staffName Blocks'),
      ),

      floatingActionButton:
          FloatingActionButton(

        child:
            const Icon(Icons.add),

        onPressed: () {

          Navigator.push(

            context,

            MaterialPageRoute(

              builder: (_) =>
                  AddBlockTimeScreen(

                businessId:
                    businessId,

                staffId:
                    staffId,
              ),
            ),
          );
        },
      ),

      body:
          StreamBuilder<QuerySnapshot>(

        stream:
            FirebaseFirestore.instance
                .collection('businesses')
                .doc(businessId)
                .collection('timeBlocks')
                .where(
                  'staffId',
                  isEqualTo: staffId,
                )
                .orderBy(
                  'startTime',
                )
                .snapshots(),

        builder: (context, snapshot) {

          // =====================================
          // LOADING
          // =====================================

          if (!snapshot.hasData) {

            return const Center(
              child:
                  CircularProgressIndicator(),
            );
          }

          final docs =
              snapshot.data!.docs;

          // =====================================
          // EMPTY
          // =====================================

          if (docs.isEmpty) {

            return Center(

              child: Padding(

                padding:
                    const EdgeInsets.all(24),

                child: Column(

                  mainAxisAlignment:
                      MainAxisAlignment.center,

                  children: [

                    Icon(
                      Icons.event_busy,
                      size: 70,
                      color:
                          Colors.grey.shade400,
                    ),

                    const SizedBox(height: 16),

                    const Text(

                      'No blocked time yet',

                      style: TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(

                      'Add holidays, lunches, sickness or unavailable time for this staff member.',

                      textAlign:
                          TextAlign.center,

                      style: TextStyle(
                        color:
                            Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // =====================================
          // LIST
          // =====================================

          return ListView.builder(

            padding:
                const EdgeInsets.only(
              top: 8,
              bottom: 100,
            ),

            itemCount:
                docs.length,

            itemBuilder:
                (context, index) {

              final doc =
                  docs[index];

              final data =
                  doc.data()
                      as Map<String, dynamic>;

              final start =
                  (data['startTime']
                          as Timestamp)
                      .toDate();

              final end =
                  (data['endTime']
                          as Timestamp)
                      .toDate();

              final title =
                  data['title']
                      ?? 'Block';

              final isInvalid =
                  end.isBefore(start);

              return Card(

                margin:
                    const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),

                elevation: 2,

                child: Padding(

                  padding:
                      const EdgeInsets.all(16),

                  child: Row(

                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [

                      // =====================================
                      // TIMELINE
                      // =====================================

                      SizedBox(

                        width: 60,

                        child: Column(

                          mainAxisAlignment:
                              MainAxisAlignment.center,

                          children: [

                            Container(
                              width: 18,
                              height: 18,

                              decoration:
                                  BoxDecoration(
                                shape:
                                    BoxShape.circle,

                                color:
                                    isInvalid
                                        ? Colors.red
                                        : Colors.teal,
                              ),
                            ),

                            Container(
                              width: 2,
                              height: 50,
                              color:
                                  Colors.teal.shade200,
                            ),

                            Container(
                              width: 18,
                              height: 18,

                              decoration:
                                  BoxDecoration(
                                shape:
                                    BoxShape.circle,

                                color:
                                    isInvalid
                                        ? Colors.red
                                        : Colors.teal.shade300,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // =====================================
                      // CONTENT
                      // =====================================

                      Expanded(

                        child: Column(

                          crossAxisAlignment:
                              CrossAxisAlignment.start,

                          children: [

                            Row(

                              children: [

                                Expanded(

                                  child: Text(

                                    title,

                                    style:
                                        const TextStyle(
                                      fontSize: 18,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                ),

                                IconButton(

                                  icon:
                                      const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),

                                  onPressed: () {

                                    deleteBlock(
                                      businessId,
                                      doc.id,
                                    );
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            Text(
                              'Start: ${formatDate(start)}',
                            ),

                            const SizedBox(height: 4),

                            Text(
                              'End: ${formatDate(end)}',
                            ),

                            if (isInvalid) ...[

                              const SizedBox(height: 10),

                              const Text(

                                '⚠ End time is before start time',

                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}