import 'package:flutter/material.dart';

class BookingSuccessScreen extends StatelessWidget {
  final String serviceName;
  final String businessName;
  final DateTime bookingDate;
  final bool isCashBooking;

  const BookingSuccessScreen({
    super.key,
    required this.serviceName,
    required this.businessName,
    required this.bookingDate,
    required this.isCashBooking,
  });

  String formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year}";
  }

  String formatTime(DateTime date) {
    return "${date.hour.toString().padLeft(2, '0')}:"
        "${date.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
      ),

      body: Padding(
        padding: const EdgeInsets.all(24),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [

            const SizedBox(height: 40),

            const Icon(
              Icons.check_circle,
              size: 90,
              color: Colors.green,
            ),

            const SizedBox(height: 24),

            const Text(
              'Booking Confirmed',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              isCashBooking
                  ? 'Your cash booking is confirmed.'
                  : 'Your payment was successful and your booking is confirmed.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 40),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),

              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.grey.shade100,
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Text(
                    serviceName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    businessName,
                    style: const TextStyle(fontSize: 16),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    "${formatDate(bookingDate)} at ${formatTime(bookingDate)}",
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed: () {
                  Navigator.popUntil(
                    context,
                    (route) => route.isFirst,
                  );
                },

                child: const Text('Back Home'),
              ),
            ),

            const SizedBox(height: 12),

          ],
        ),
      ),
    );
  }
}