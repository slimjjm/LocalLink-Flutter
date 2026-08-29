import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class BookingStatusChip extends StatelessWidget {
  final String status;
  final bool compact;

  const BookingStatusChip({
    super.key,
    required this.status,
    this.compact = false,
  });

  BookingStatusPresentation get _presentation {
    switch (status) {
      case 'pending_business_confirmation':
        return const BookingStatusPresentation(
          label: 'Waiting for confirmation',
          icon: Icons.hourglass_top_rounded,
          background: Color(0xFFFFF4D6),
          foreground: Color(0xFF8A5A00),
        );
      case 'pending_payment':
        return const BookingStatusPresentation(
          label: 'Awaiting Payment',
          icon: Icons.payments_outlined,
          background: Color(0xFFFFF4D6),
          foreground: Color(0xFF8A5A00),
        );
      case 'confirmed':
        return const BookingStatusPresentation(
          label: 'Confirmed',
          icon: Icons.check_circle_rounded,
          background: Color(0xFFE6F6EE),
          foreground: Color(0xFF116B42),
        );
      case 'completed':
        return const BookingStatusPresentation(
          label: 'Completed',
          icon: Icons.task_alt_rounded,
          background: Color(0xFFE7F0FF),
          foreground: Color(0xFF2457A6),
        );
      case 'refunded':
        return const BookingStatusPresentation(
          label: 'Refunded',
          icon: Icons.replay_circle_filled_rounded,
          background: Color(0xFFF0F2F4),
          foreground: Color(0xFF59636E),
        );
      case 'declined':
      case 'cancelled_by_customer':
      case 'cancelled_by_business':
      case 'cancelled_by_system':
      case 'payment_failed':
        return const BookingStatusPresentation(
          label: 'Cancelled',
          icon: Icons.cancel_rounded,
          background: Color(0xFFFFE8E6),
          foreground: Color(0xFFB42318),
        );
      default:
        return BookingStatusPresentation(
          label: status.trim().isEmpty
              ? 'Status unavailable'
              : status.replaceAll('_', ' '),
          icon: Icons.info_outline_rounded,
          background: AppColors.background,
          foreground: AppColors.textMuted,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation;

    return Semantics(
      label: 'Booking status: ${presentation.label}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 12,
          vertical: compact ? 5 : 7,
        ),
        decoration: BoxDecoration(
          color: presentation.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              presentation.icon,
              size: compact ? 14 : 16,
              color: presentation.foreground,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                presentation.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: presentation.foreground,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BookingStatusPresentation {
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  const BookingStatusPresentation({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });
}
