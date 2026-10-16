import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../utils/helpers.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_surface_card.dart';

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
        title: const Text('Booking summary'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(LocalLinkSpacing.lg),
        children: [
          const Text(
            'Review your booking',
            style: LocalLinkTextStyles.screenTitle,
          ),
          const SizedBox(height: LocalLinkSpacing.xs),
          const Text(
            'Check the details before confirming.',
            style: LocalLinkTextStyles.secondary,
          ),
          const SizedBox(height: LocalLinkSpacing.xl),
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
                value: paymentMethodLabel(paymentMethod),
              ),
              _SummaryRow(
                label: 'Notes',
                value: customerNotes.isEmpty ? 'None' : customerNotes,
              ),
            ],
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          LocalLinkSurfaceCard(
            elevated: false,
            color: AppColors.serviceGreen.withValues(alpha: 0.08),
            padding: const EdgeInsets.all(LocalLinkSpacing.md),
            child: Text(
              'Cancellation policy: you can cancel from your booking details. Refund eligibility depends on timing and payment method.',
              style: LocalLinkTextStyles.secondary.copyWith(
                color: AppColors.charcoal,
              ),
            ),
          ),
          const SizedBox(height: LocalLinkSpacing.xl),
          LocalLinkButton(
            label: 'Confirm booking',
            icon: Icons.check_circle_outline_rounded,
            expand: true,
            onPressed: () {
              Navigator.pop(context, true);
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: false,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Column(children: children),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(label, style: LocalLinkTextStyles.metadata),
          ),
          Expanded(child: Text(value, style: LocalLinkTextStyles.bodyStrong)),
        ],
      ),
    );
  }
}
