import 'package:flutter/material.dart';

import '../screens/business_detail_screen.dart';
import '../services/next_available_service.dart';

class BusinessCard extends StatefulWidget {

  final String businessId;
  final Map<String, dynamic> businessData;

  const BusinessCard({
    super.key,
    required this.businessId,
    required this.businessData,
  });

  @override
  State<BusinessCard> createState() =>
      _BusinessCardState();
}

class _BusinessCardState
    extends State<BusinessCard> {

  DateTime? nextSlot;

  @override
  void initState() {
    super.initState();

    loadNextSlot();
  }

  Future<void> loadNextSlot() async {

    final slot =
        await NextAvailableService
            .getNextAvailableSlot(
      widget.businessId,
    );

    if (!mounted) return;

    setState(() {
      nextSlot = slot;
    });
  }

  @override
  Widget build(BuildContext context) {

    final name =
        widget.businessData['businessName'] ??
        'Business';

    final category =
        widget.businessData['category'] ??
        'Service';

    final address =
        widget.businessData['address'] ?? '';

    return Card(

      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),

      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(16),
      ),

      elevation: 2,

      child: InkWell(

        borderRadius:
            BorderRadius.circular(16),

        onTap: () {

          Navigator.push(
            context,

            MaterialPageRoute(
              builder: (_) =>
                  BusinessDetailScreen(
                businessId:
                    widget.businessId,
              ),
            ),
          );
        },

        child: Padding(

          padding:
              const EdgeInsets.all(16),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [

              Row(
                children: [

                  Expanded(
                    child: Text(

                      name,

                      style:
                          const TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),

                  const Icon(
                    Icons.chevron_right,
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Text(

                category,

                style: TextStyle(
                  color:
                      Colors.grey.shade700,
                ),
              ),

              if (address.isNotEmpty) ...[

                const SizedBox(height: 6),

                Text(

                  address,

                  style: TextStyle(
                    color:
                        Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ],

              // NEXT AVAILABLE SLOT

              if (nextSlot != null) ...[

                const SizedBox(height: 10),

                Text(

                  'Next available: '
                  '${nextSlot!.day}/'
                  '${nextSlot!.month} '
                  '${nextSlot!.hour.toString().padLeft(2, '0')}:'
                  '${nextSlot!.minute.toString().padLeft(2, '0')}',

                  style: const TextStyle(
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}