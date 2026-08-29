import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/inbox_conversation.dart';
import '../viewmodels/inbox_view_model.dart';
import '../theme/app_colors.dart';

import 'booking_conversation_screen.dart';

class InboxScreen extends StatefulWidget {
  final String? businessId;
  final String currentRole;

  const InboxScreen({super.key, this.businessId, required this.currentRole});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final InboxViewModel viewModel = InboxViewModel();

  @override
  void initState() {
    super.initState();

    viewModel.onUpdated = () {
      if (mounted) {
        setState(() {});
      }
    };

    viewModel.startListening(
      role: widget.currentRole,

      businessId: widget.businessId ?? '',
    );
  }

  @override
  void dispose() {
    viewModel.stopListening();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),

      body: viewModel.isLoading
          ? const Center(child: CircularProgressIndicator())
          : viewModel.errorMessage != null
          ? _errorState(viewModel.errorMessage!)
          : viewModel.conversations.isEmpty
          ? _emptyState()
          : ListView.builder(
              itemCount: viewModel.conversations.length,

              itemBuilder: (context, index) {
                final convo = viewModel.conversations[index];

                return _conversationTile(convo);
              },
            ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,

        children: [
          Icon(Icons.chat_bubble_outline, size: 70),

          SizedBox(height: 16),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              'Messages about bookings, requests and Pages will appear here.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.textMuted,
            ),

            const SizedBox(height: 16),

            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _conversationTile(InboxConversation convo) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final role = _roleForConversation(convo, currentUid);
    final style = _styleForConversation(convo);
    final displayName = convo.displayNameFor(currentUid, role);
    final viewerType = convo.viewerTypeFor(currentUid, role);
    final unreadCount = convo.unreadCountFor(currentUid, role);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: style.color.withValues(alpha: 0.12),
        child: Icon(style.icon, color: style.color, size: 20),
      ),

      title: Text(displayName),

      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            convo.serviceName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: style.color, fontWeight: FontWeight.w700),
          ),
          Text(
            convo.lastMessage.isEmpty ? 'No messages yet' : convo.lastMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),

      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _StatusPill(label: style.label, color: style.color),
          const SizedBox(height: 4),
          Text(
            _formatInboxTime(convo.lastMessageAt),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 4),
          if (unreadCount > 0)
            CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.serviceGreen,
              child: Text(
                unreadCount.toString(),
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
        ],
      ),

      onTap: () {
        Navigator.push(
          context,

          MaterialPageRoute(
            builder: (_) => BookingConversationScreen(
              conversationId: convo.id,
              bookingId: convo.bookingId.isEmpty ? null : convo.bookingId,
              viewerType: viewerType,
            ),
          ),
        );
      },
    );
  }

  String _roleForConversation(InboxConversation convo, String? currentUid) {
    if (widget.currentRole != 'all') {
      return widget.currentRole;
    }

    if (convo.isCommunityHelp) {
      return convo.isCommunityOwner(currentUid) ? 'business' : 'customer';
    }

    if (currentUid != null &&
        currentUid.isNotEmpty &&
        currentUid == convo.businessOwnerId) {
      return 'business';
    }

    return 'customer';
  }

  _ConversationStyle _styleForConversation(InboxConversation convo) {
    final type = convo.conversationType;
    final status = convo.conversationStatus;

    if (convo.isCommunityHelp) {
      return const _ConversationStyle(
        label: 'Community Help',
        color: AppColors.primary,
        icon: Icons.volunteer_activism_outlined,
      );
    }

    if (type == 'business_to_business') {
      return const _ConversationStyle(
        label: 'Business',
        color: AppColors.activityBlue,
        icon: Icons.storefront_outlined,
      );
    }

    if (type == 'activity') {
      return const _ConversationStyle(
        label: 'Activity',
        color: AppColors.activityBlue,
        icon: Icons.groups_2_outlined,
      );
    }

    if (status == 'booking' || convo.bookingId.isNotEmpty) {
      return const _ConversationStyle(
        label: 'Booking',
        color: AppColors.serviceGreen,
        icon: Icons.calendar_today_outlined,
      );
    }

    return const _ConversationStyle(
      label: 'Enquiry',
      color: AppColors.primary,
      icon: Icons.chat_bubble_outline_rounded,
    );
  }

  String _formatInboxTime(dynamic timestamp) {
    if (timestamp == null) return '';

    final date = timestamp.toDate().toLocal();
    final now = DateTime.now();
    final sameDay =
        date.year == now.year && date.month == now.month && date.day == now.day;

    if (sameDay) {
      return '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    }

    return '${date.day}/${date.month}';
  }
}

class _ConversationStyle {
  const _ConversationStyle({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
