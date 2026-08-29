import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class BookingSummaryScreen extends StatelessWidget {
  const BookingSummaryScreen({
    super.key,
    required this.businessName,
    required this.serviceName,
    required this.slot,
    required this.durationMinutes,
    required this.priceLabel,
    required this.address,
    required this.paymentMethod,
    required this.customerNotes,
  });

  final String businessName;
  final String serviceName;
  final Map<String, dynamic> slot;
  final int? durationMinutes;
  final String priceLabel;
  final String address;
  final String paymentMethod;
  final String customerNotes;

  @override
  Widget build(BuildContext context) {
    final start = (slot['startTime'] as Timestamp).toDate().toLocal();
    final time =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Booking Summary'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Review your booking',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Check the details before confirming.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          _SummaryCard(
            children: [
              _SummaryRow(label: 'Business', value: businessName),
              _SummaryRow(label: 'Service', value: serviceName),
              _SummaryRow(
                label: 'Date',
                value: '${start.day}/${start.month}/${start.year}',
              ),
              _SummaryRow(label: 'Time', value: time),
              _SummaryRow(
                label: 'Duration',
                value: durationMinutes == null
                    ? 'To be confirmed'
                    : '$durationMinutes mins',
              ),
              _SummaryRow(label: 'Price', value: priceLabel),
              _SummaryRow(label: 'Address', value: address),
              _SummaryRow(
                label: 'Payment',
                value: paymentMethod == 'stripe' ? 'Card' : 'Cash',
              ),
              _SummaryRow(
                label: 'Notes',
                value: customerNotes.isEmpty ? 'None' : customerNotes,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.serviceGreen.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Cancellation policy: you can cancel from your booking details. Refund eligibility depends on timing and payment method.',
              style: TextStyle(
                color: AppColors.charcoal,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.serviceGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Confirm Booking'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
