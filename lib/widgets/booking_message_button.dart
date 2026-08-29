import 'package:flutter/material.dart';

import '../models/booking_conversation.dart';
import '../services/booking_messaging_service.dart';
import '../theme/app_colors.dart';

class BookingMessageButton extends StatelessWidget {
  const BookingMessageButton({
    super.key,
    required this.bookingId,
    required this.viewerType,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String bookingId;
  final String viewerType;
  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final service = BookingMessagingService();

    return StreamBuilder<BookingConversation?>(
      stream: service.watchConversation(bookingId),
      builder: (context, snapshot) {
        final conversation = snapshot.data;
        final unreadCount =
            conversation?.unreadCountFor(viewerType) ?? 0;
        final isArchived = conversation?.archived == true;

        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: enabled && !isArchived ? onPressed : null,
            icon: const Icon(Icons.chat_bubble_outline),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    isArchived ? 'Conversation archived' : label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(width: 10),
                  _UnreadBadge(count: unreadCount),
                ],
              ],
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.serviceGreen,
              foregroundColor: AppColors.buttonText,
              disabledBackgroundColor: AppColors.disabled,
              disabledForegroundColor: AppColors.textMuted,
              padding: const EdgeInsets.symmetric(
                vertical: 14,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({
    required this.count,
  });

  final int count;

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';

    return Container(
      constraints: const BoxConstraints(
        minWidth: 22,
        minHeight: 22,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.serviceGreen,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
