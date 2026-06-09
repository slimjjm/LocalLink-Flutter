import 'package:flutter/material.dart';

import '../screens/business_detail_screen.dart';
import '../services/next_available_service.dart';
import '../theme/app_colors.dart';

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

    final businessName =
        widget.businessData['businessName']
            ?? 'Business';

    final category =
        widget.businessData['category']
            ?? 'Service';

    final address =
        widget.businessData['address']
            ?? '';

    final bio =
        widget.businessData['bio']
            ?? '';

   final verified =
    widget.businessData[
        'stripeChargesEnabled'
    ] == true;

    final paymentMethods =
        List<String>.from(
      widget.businessData[
              'paymentMethods'] ??
          [],
    );

    final photoURLs =
        List<String>.from(
      widget.businessData[
              'photoURLs'] ??
          [],
    );

    final hasCoverPhoto =
        photoURLs.isNotEmpty;

    final coverPhoto =
        hasCoverPhoto
            ? photoURLs.first
            : null;

final distanceMiles =
    widget.businessData['distanceMiles'];


    return Container(

      margin:
          const EdgeInsets.only(
        bottom: 18,
      ),

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius:
            BorderRadius.circular(28),

        boxShadow: [

          BoxShadow(

            color:
                Colors.black.withOpacity(
              0.06,
            ),

            blurRadius: 18,

            offset:
                const Offset(0, 10),
          ),
        ],
      ),

      child: InkWell(

        borderRadius:
            BorderRadius.circular(28),

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

        child: Column(

          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [

            // =========================================
            // COVER IMAGE
            // =========================================

            Stack(

              children: [

                ClipRRect(

                  borderRadius:
                      const BorderRadius.only(

                    topLeft:
                        Radius.circular(
                      28,
                    ),

                    topRight:
                        Radius.circular(
                      28,
                    ),
                  ),

                  child:
                      hasCoverPhoto

                          ? Image.network(

  coverPhoto!,

  height: 170,

  width: double.infinity,

  fit: BoxFit.cover,

  errorBuilder:
      (context, error, stackTrace) {

    return Container(

      height: 170,

      width: double.infinity,

      decoration: BoxDecoration(

        gradient: LinearGradient(

          colors: [

            AppColors.primary
                .withOpacity(0.90),

            const Color(0xFFE65100),

          ],
        ),
      ),

      child: const Center(

        child: Icon(

          Icons.storefront,

          color: Colors.white,

          size: 54,
        ),
      ),
    );
  },
)

                          : Container(

                              height: 170,

                              width:
                                  double.infinity,

                              decoration:
                                  BoxDecoration(

                                gradient:
                                    LinearGradient(

                                  colors: [

                                    AppColors
                                        .primary
                                        .withOpacity(
                                      0.90,
                                    ),

                                    const Color(
                                      0xFFE65100,
                                    ),
                                  ],
                                ),
                              ),

                              child:
                                  const Center(

                                child: Icon(

                                  Icons.storefront,

                                  color:
                                      Colors.white,

                                  size: 54,
                                ),
                              ),
                            ),
                ),

                // CATEGORY BADGE

                Positioned(

                  left: 14,
                  top: 14,

                  child: Container(

                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),

                    decoration:
                        BoxDecoration(

                      color:
                          Colors.black87,

                      borderRadius:
                          BorderRadius.circular(
                        999,
                      ),
                    ),

                    child: Text(

                      category,

                      style:
                          const TextStyle(

                        color:
                            Colors.white,

                        fontWeight:
                            FontWeight.w700,

                        fontSize: 12,
                      ),
                    ),
                  ),
                ),

                // VERIFIED

                if (verified)

                  Positioned(

                    right: 14,
                    top: 14,

                    child: Container(

                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),

                      decoration:
                          BoxDecoration(

                        color:
                            AppColors.success,

                        borderRadius:
                            BorderRadius.circular(
                          999,
                        ),
                      ),

                      child: const Row(

                        children: [

                          Icon(

                            Icons.verified,

                            color:
                                Colors.white,

                            size: 14,
                          ),

                          SizedBox(width: 4),

                          Text(

                            'Payments Verified',

                            style: TextStyle(

                              color:
                                  Colors.white,

                              fontWeight:
                                  FontWeight.bold,

                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            // =========================================
            // CONTENT
            // =========================================

            Padding(

              padding:
                  const EdgeInsets.all(
                18,
              ),

              child: Column(

                crossAxisAlignment:
                    CrossAxisAlignment.start,

                children: [

                  // BUSINESS NAME

                  Text(

                    businessName,

                    style:
                        const TextStyle(

                      fontSize: 22,

                      fontWeight:
                          FontWeight.w800,

                      color:
                          AppColors.charcoal,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // BIO

                  if (bio
                      .toString()
                      .trim()
                      .isNotEmpty)

                    Text(

                      bio,

                      maxLines: 3,

                      overflow:
                          TextOverflow.ellipsis,

                      style: TextStyle(

                        height: 1.45,

                        color:
                            Colors.grey.shade700,
                      ),
                    ),

                  if (bio
                      .toString()
                      .trim()
                      .isNotEmpty)

                    const SizedBox(
                      height: 14,
                    ),

                  // ADDRESS

                  if (address
                      .toString()
                      .trim()
                      .isNotEmpty)

                    Row(

                      children: [

                        Icon(

                          Icons.location_on_outlined,

                          size: 18,

                          color:
                              Colors.grey.shade600,
                        ),

                        const SizedBox(
                          width: 6,
                        ),

                        Expanded(

                          child: Text(

                            address,

                            maxLines: 1,

                            overflow:
                                TextOverflow.ellipsis,

                            style: TextStyle(

                              color:
                                  Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 18),

                  if (distanceMiles != null) ...[

  const SizedBox(height: 10),

  Row(

    children: [

      Icon(
        Icons.near_me,
        size: 16,
        color:
            Colors.grey.shade600,
      ),

      const SizedBox(width: 6),

      Text(

        '${distanceMiles.toStringAsFixed(1)} miles away',

        style: TextStyle(

          color:
              Colors.grey.shade700,

          fontWeight:
              FontWeight.w600,
        ),
      ),
    ],
  ),
],

              

                  // PAYMENT ROW

                  Wrap(

                    spacing: 8,
                    runSpacing: 8,

                    children: [

                      if (paymentMethods
                          .contains('stripe'))

                        _InfoBadge(
                          icon:
                              Icons.credit_card,
                          label:
                              'Card Payments',
                        ),

                      if (paymentMethods
                          .contains('cash'))

                        _InfoBadge(
                          icon:
                              Icons.payments_outlined,
                          label: 'Cash Accepted',
                        ),
                    ],
                  ),

                  // NEXT AVAILABLE

                  if (nextSlot != null) ...[

                    const SizedBox(
                      height: 18,
                    ),

                    Container(

                      padding:
                          const EdgeInsets.all(
                        14,
                      ),

                      decoration:
                          BoxDecoration(

                        color:
                            AppColors.success
                                .withOpacity(
                          0.08,
                        ),

                        borderRadius:
                            BorderRadius.circular(
                          18,
                        ),
                      ),

                      child: Row(

                        children: [

                          const Icon(

                            Icons.schedule,

                            color:
                                AppColors.success,
                          ),

                          const SizedBox(
                            width: 10,
                          ),

                          Expanded(

                            child: Text(

                              'Next available: '
                              '${nextSlot!.day}/'
                              '${nextSlot!.month} '
                              '${nextSlot!.hour.toString().padLeft(2, '0')}:'
                              '${nextSlot!.minute.toString().padLeft(2, '0')}',

                              style:
                                  const TextStyle(

                                fontWeight:
                                    FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // CTA

                  SizedBox(

                    width: double.infinity,

                    child: ElevatedButton(

                      onPressed: () {

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

                      style:
                          ElevatedButton.styleFrom(

                        backgroundColor:
                            AppColors.primary,

                        foregroundColor:
                            Colors.white,

                        padding:
                            const EdgeInsets.symmetric(
                          vertical: 16,
                        ),

                        elevation: 0,

                        shape:
                            RoundedRectangleBorder(

                          borderRadius:
                              BorderRadius.circular(
                            18,
                          ),
                        ),
                      ),

                      child: const Text(

                        'View Business',

                        style: TextStyle(

                          fontWeight:
                              FontWeight.bold,

                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// INFO BADGE
// =====================================================

class _InfoBadge
    extends StatelessWidget {

  final IconData icon;
  final String label;

  const _InfoBadge({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {

    return Container(

      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),

      decoration: BoxDecoration(

        color:
            AppColors.primary
                .withOpacity(0.08),

        borderRadius:
            BorderRadius.circular(999),
      ),

      child: Row(

        mainAxisSize:
            MainAxisSize.min,

        children: [

          Icon(

            icon,

            size: 16,

            color:
                AppColors.primary,
          ),

          const SizedBox(width: 6),

          Text(

            label,

            style: const TextStyle(

              fontWeight:
                  FontWeight.w600,

              color:
                  AppColors.charcoal,
            ),
          ),
        ],
      ),
    );
  }
}