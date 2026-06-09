import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_colors.dart';
import '../utils/helpers.dart';

import 'booking_screen.dart';
import 'enquiry_chat_screen.dart';

class BusinessDetailScreen extends StatelessWidget {

  final String businessId;

  const BusinessDetailScreen({
    super.key,
    required this.businessId,
  });

  @override
  Widget build(BuildContext context) {

    return FutureBuilder<DocumentSnapshot>(

      future:
          FirebaseFirestore.instance
              .collection('businesses')
              .doc(businessId)
              .get(),

      builder: (context, snapshot) {

        if (!snapshot.hasData) {

          return const Scaffold(

            body: Center(
              child:
                  CircularProgressIndicator(),
            ),
          );
        }

        final businessData =
            snapshot.data!.data()
                as Map<String, dynamic>? ??
            {};

        final businessName =
            safeText(
          businessData['businessName'],
          'Business',
        );

        final category =
            safeText(
          businessData['category'],
          'No category',
        );

        final bio =
            safeText(
          businessData['bio'],
          '',
        );

        final address =
            safeText(
          businessData['address'],
          '',
        );

      final verified =
    businessData[
        'stripeChargesEnabled'
    ] == true;

        final paymentMethods =
            resolvePaymentMethods(
          businessData,
        );

        final photoURLs =
            List<String>.from(
          businessData['photoURLs'] ??
              [],
        );

        final coverPhoto =
            photoURLs.isNotEmpty
                ? photoURLs.first
                : null;

        return Scaffold(

          backgroundColor:
              AppColors.background,

          body: CustomScrollView(

            slivers: [

              // =====================================
              // HERO
              // =====================================

              SliverAppBar(

                expandedHeight: 300,

                pinned: true,

                backgroundColor:
                    AppColors.primary,

                foregroundColor:
                    Colors.white,

                flexibleSpace:
                    FlexibleSpaceBar(

                  background:
                      Stack(

                    fit: StackFit.expand,

                    children: [

                      // IMAGE

                      if (coverPhoto != null)

                        Image.network(
                          coverPhoto,
                          fit: BoxFit.cover,
                        )

                      else

                        Container(

                          decoration:
                              const BoxDecoration(

                            gradient:
                                LinearGradient(

                              colors: [

                                AppColors.primary,

                                Color(
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

                              size: 70,
                            ),
                          ),
                        ),

                      // OVERLAY

                      Container(

                        decoration:
                            BoxDecoration(

                          gradient:
                              LinearGradient(

                            begin:
                                Alignment.topCenter,

                            end:
                                Alignment.bottomCenter,

                            colors: [

                              Colors.black
                                  .withOpacity(
                                0.15,
                              ),

                              Colors.black
                                  .withOpacity(
                                0.55,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // TITLE AREA

                      Positioned(

                        left: 20,
                        right: 20,
                        bottom: 24,

                        child: Column(

                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,

                          children: [

                            Container(

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
                                      FontWeight.bold,
                                ),
                              ),
                            ),

                            const SizedBox(
                              height: 12,
                            ),

                            Row(

                              children: [

                                Expanded(

                                  child: Text(

                                    businessName,

                                    style:
                                        const TextStyle(

                                      color:
                                          Colors.white,

                                      fontSize: 30,

                                      fontWeight:
                                          FontWeight.w800,
                                    ),
                                  ),
                                ),

                                if (verified)

                                  Container(

                                    padding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
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

                                    child:
                                        const Row(

                                      children: [

                                        Icon(

                                          Icons.verified,

                                          color:
                                              Colors.white,

                                          size: 16,
                                        ),

                                        SizedBox(
                                          width: 4,
                                        ),

                                        Text(

                                          'Payments Verified',

                                          style:
                                              TextStyle(

                                            color:
                                                Colors.white,

                                            fontWeight:
                                                FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),

                            if (address
                                .trim()
                                .isNotEmpty) ...[

                              const SizedBox(
                                height: 10,
                              ),

                              Row(

                                children: [

                                  const Icon(

                                    Icons.location_on,

                                    color:
                                        Colors.white70,

                                    size: 18,
                                  ),

                                  const SizedBox(
                                    width: 6,
                                  ),

                                  Expanded(

                                    child: Text(

                                      address,

                                      style:
                                          const TextStyle(

                                        color:
                                            Colors.white70,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // =====================================
              // CONTENT
              // =====================================

              SliverToBoxAdapter(

                child: Padding(

                  padding:
                      const EdgeInsets.all(
                    20,
                  ),

                  child: Column(

                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,

                    children: [

                      // =================================
                      // TRUST ROW
                      // =================================

                      Wrap(

                        spacing: 10,
                        runSpacing: 10,

                        children: [

                          if (paymentMethods
                              .contains(
                            'stripe',
                          ))

                            _TrustBadge(
                              icon:
                                  Icons.credit_card,
                              label:
                                  'Card Payments',
                            ),

                          if (paymentMethods
                              .contains(
                            'cash',
                          ))

                            _TrustBadge(
                              icon:
                                  Icons.payments,
                              label:
                                  'Cash Accepted',
                            ),

                          if (verified)

                            _TrustBadge(
                              icon:
                                  Icons.verified,
                              label:
                                  'Payments Business',
                            ),
                        ],
                      ),

                      // =================================
                      // ABOUT
                      // =================================

                      if (bio
                          .trim()
                          .isNotEmpty) ...[

                        const SizedBox(
                          height: 28,
                        ),

                        const Text(

                          'About',

                          style: TextStyle(

                            fontSize: 24,

                            fontWeight:
                                FontWeight.w800,

                            color:
                                AppColors.charcoal,
                          ),
                        ),

                        const SizedBox(
                          height: 12,
                        ),

                        Text(

                          bio,

                          style: TextStyle(

                            height: 1.6,

                            fontSize: 15,

                            color:
                                Colors.grey.shade800,
                          ),
                        ),
                      ],

                      // =================================
                      // CONTACT CTA
                      // =================================

                      const SizedBox(
                        height: 28,
                      ),

                      SizedBox(

                        width: double.infinity,

                        child: OutlinedButton.icon(

                          icon: const Icon(
                            Icons.chat_bubble_outline,
                          ),

                          label: const Text(
                            'Ask a Question',
                          ),

                          style:
                              OutlinedButton.styleFrom(

                            foregroundColor:
                                AppColors.primary,

                            side:
                                const BorderSide(
                              color:
                                  AppColors.primary,
                            ),

                            padding:
                                const EdgeInsets.symmetric(
                              vertical: 16,
                            ),

                            shape:
                                RoundedRectangleBorder(

                              borderRadius:
                                  BorderRadius.circular(
                                18,
                              ),
                            ),
                          ),

                          onPressed: () {

                            final customerId =
                                FirebaseAuth
                                    .instance
                                    .currentUser
                                    ?.uid;

                            if (customerId ==
                                null) {
                              return;
                            }

                            Navigator.push(

                              context,

                              MaterialPageRoute(

                                builder: (_) =>
                                    EnquiryChatScreen(

                                  businessId:
                                      businessId,

                                  customerId:
                                      customerId,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // =================================
                      // SERVICES HEADER
                      // =================================

                      const SizedBox(
                        height: 36,
                      ),

                      const Text(

                        'Services',

                        style: TextStyle(

                          fontSize: 28,

                          fontWeight:
                              FontWeight.w800,

                          color:
                              AppColors.charcoal,
                        ),
                      ),

                      const SizedBox(
                        height: 16,
                      ),

                      // =================================
                      // SERVICES
                      // =================================

                      StreamBuilder<QuerySnapshot>(

                        stream:
                            FirebaseFirestore
                                .instance
                                .collection(
                                  'businesses',
                                )
                                .doc(
                                  businessId,
                                )
                                .collection(
                                  'services',
                                )
                                .where(
                                  'isActive',
                                  isEqualTo:
                                      true,
                                )
                                .snapshots(),

                        builder:
                            (context, snapshot) {

                          if (!snapshot
                              .hasData) {

                            return const Padding(

                              padding:
                                  EdgeInsets.all(
                                30,
                              ),

                              child: Center(

                                child:
                                    CircularProgressIndicator(),
                              ),
                            );
                          }

                          final services =
                              snapshot
                                      .data
                                      ?.docs ??
                                  [];

                          if (services
                              .isEmpty) {

                            return Container(

                              width:
                                  double.infinity,

                              padding:
                                  const EdgeInsets.all(
                                24,
                              ),

                              decoration:
                                  BoxDecoration(

                                color:
                                    Colors.white,

                                borderRadius:
                                    BorderRadius.circular(
                                  24,
                                ),
                              ),

                              child:
                                  const Text(

                                'No services available yet.',
                              ),
                            );
                          }

                          return Column(

                            children:
                                services.map(
                              (doc) {

                                final data =
                                    doc.data()
                                        as Map<String,
                                            dynamic>;

                                return _ServiceCard(

                                  businessId:
                                      businessId,

                                  businessName:
                                      businessName,

                                  serviceId:
                                      doc.id,

                                  serviceData:
                                      data,

                                  paymentMethods:
                                      paymentMethods,
                                );
                              },
                            ).toList(),
                          );
                        },
                      ),

                      const SizedBox(
                        height: 40,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =====================================================
// TRUST BADGE
// =====================================================

class _TrustBadge extends StatelessWidget {

  final IconData icon;
  final String label;

  const _TrustBadge({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {

    return Container(

      padding:
          const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),

      decoration: BoxDecoration(

        color:
            AppColors.primary
                .withOpacity(0.08),

        borderRadius:
            BorderRadius.circular(
          999,
        ),
      ),

      child: Row(

        mainAxisSize:
            MainAxisSize.min,

        children: [

          Icon(

            icon,

            size: 18,

            color:
                AppColors.primary,
          ),

          const SizedBox(width: 7),

          Text(

            label,

            style: const TextStyle(

              fontWeight:
                  FontWeight.w700,

              color:
                  AppColors.charcoal,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// SERVICE CARD
// =====================================================

class _ServiceCard extends StatelessWidget {

  final String businessId;
  final String businessName;
  final String serviceId;

  final Map<String, dynamic>
      serviceData;

  final List<String>
      paymentMethods;

  const _ServiceCard({
    required this.businessId,
    required this.businessName,
    required this.serviceId,
    required this.serviceData,
    required this.paymentMethods,
  });

  @override
  Widget build(BuildContext context) {

    final name =
        safeText(
      serviceData['name'],
      'Service',
    );

    final details =
        safeText(
      serviceData['details'],
      '',
    );

    final price =
        formatPrice(
      serviceData['price'],
    );

    final duration =
        serviceData[
            'durationMinutes'];

    return Container(

      margin:
          const EdgeInsets.only(
        bottom: 16,
      ),

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius:
            BorderRadius.circular(
          24,
        ),

        boxShadow: [

          BoxShadow(

            color:
                Colors.black.withOpacity(
              0.04,
            ),

            blurRadius: 12,

            offset:
                const Offset(0, 6),
          ),
        ],
      ),

      child: Padding(

        padding:
            const EdgeInsets.all(
          18,
        ),

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

                      fontSize: 20,

                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                ),

                Text(

                  price,

                  style:
                      const TextStyle(

                    fontWeight:
                        FontWeight.w800,

                    fontSize: 18,

                    color:
                        AppColors.primary,
                  ),
                ),
              ],
            ),

            if (duration != null) ...[

              const SizedBox(
                height: 6,
              ),

              Text(
                '$duration mins',
              ),
            ],

            if (details
                .trim()
                .isNotEmpty) ...[

              const SizedBox(
                height: 12,
              ),

              Text(

                details,

                style: TextStyle(

                  height: 1.5,

                  color:
                      Colors.grey.shade700,
                ),
              ),
            ],

            const SizedBox(
              height: 18,
            ),

            SizedBox(

              width: double.infinity,

              child: ElevatedButton(

                onPressed: () {

                  Navigator.push(

                    context,

                    MaterialPageRoute(

                      builder: (_) =>
                          BookingScreen(

                        businessId:
                            businessId,

                        businessName:
                            businessName,

                        serviceId:
                            serviceId,

                        serviceData:
                            serviceData,

                        paymentMethods:
                            paymentMethods,
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
                    vertical: 15,
                  ),

                  shape:
                      RoundedRectangleBorder(

                    borderRadius:
                        BorderRadius.circular(
                      18,
                    ),
                  ),
                ),

                child: const Text(

                  'Book Now',

                  style: TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}