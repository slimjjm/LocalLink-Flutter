import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'booking_success_screen.dart';

class BookingConfirmationWaitScreen extends StatefulWidget {
  final String bookingId;
  final String serviceName;
  final String businessName;
  final DateTime bookingDate;

  const BookingConfirmationWaitScreen({
    super.key,
    required this.bookingId,
    required this.serviceName,
    required this.businessName,
    required this.bookingDate,
  });

  @override
  State<BookingConfirmationWaitScreen> createState() =>
      _BookingConfirmationWaitScreenState();
}

class _BookingConfirmationWaitScreenState
    extends State<BookingConfirmationWaitScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  bool _showRecovery = false;

  @override
  void initState() {
    super.initState();

    if (widget.bookingId.isEmpty) {
      _showDelayedRecovery();
      return;
    }

    _subscription = FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.bookingId)
        .snapshots()
        .listen(
          _handleBookingSnapshot,
          onError: (_) {
            if (mounted) setState(() => _showRecovery = true);
          },
        );

    _showDelayedRecovery();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _showDelayedRecovery() {
    Future.delayed(const Duration(seconds: 20), () {
      if (mounted) setState(() => _showRecovery = true);
    });
  }

  void _handleBookingSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (!snapshot.exists || !mounted) return;

    final data = snapshot.data() ?? {};
    final status = data['status']?.toString() ?? '';

    if (status == 'confirmed') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BookingSuccessScreen(
            serviceName: widget.serviceName,
            businessName: widget.businessName,
            bookingDate: widget.bookingDate,
            isCashBooking: false,
          ),
        ),
      );
      return;
    }

    if (status == 'pending_business_confirmation') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BookingSuccessScreen(
            serviceName: widget.serviceName,
            businessName: widget.businessName,
            bookingDate: widget.bookingDate,
            isCashBooking: false,
            pendingBusinessConfirmation: true,
          ),
        ),
      );
      return;
    }

    if (status == 'payment_failed' ||
        status == 'cancelled_by_system' ||
        status == 'declined') {
      setState(() => _showRecovery = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: _showRecovery
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, size: 72),
                    const SizedBox(height: 18),
                    const Text(
                      'We are still confirming your booking',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your payment was received, but confirmation is taking longer than usual. Please check My Bookings or contact LocalLink support if this does not update shortly.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.popUntil(context, (route) => route.isFirst);
                      },
                      child: const Text('Back Home'),
                    ),
                  ],
                )
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text(
                      'Confirming your booking...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'This usually only takes a few seconds.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
