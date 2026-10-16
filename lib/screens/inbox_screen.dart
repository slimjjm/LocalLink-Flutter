import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/inbox_conversation.dart';
import '../theme/app_colors.dart';
import '../viewmodels/inbox_view_model.dart';
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
  _InboxFilter _selectedFilter = _InboxFilter.all;

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
    final visibleConversations = _filteredConversations();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: _InboxHeader(),
            ),
            if (_showFilters)
              _InboxFilters(
                selected: _selectedFilter,
                onSelected: (filter) {
                  setState(() {
                    _selectedFilter = filter;
                  });
                },
              ),
            Expanded(
              child: viewModel.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : viewModel.errorMessage != null
                  ? _errorState(viewModel.errorMessage!)
                  : viewModel.conversations.isEmpty
                  ? _emptyState()
                  : visibleConversations.isEmpty
                  ? _emptyFilterState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      itemCount: visibleConversations.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _conversationTile(visibleConversations[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _EmptyInboxIcon(icon: Icons.chat_bubble_outline_rounded),
          SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Conversations about bookings, enquiries and Community Help will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyFilterState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'No conversations in this view yet.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
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
    final isUnread = unreadCount > 0;
    final preview = convo.lastMessage.isEmpty
        ? 'No messages yet'
        : convo.lastMessage;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUnread
                  ? AppColors.charcoal.withValues(alpha: 0.18)
                  : AppColors.border.withValues(alpha: 0.82),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.charcoal.withValues(alpha: 0.045),
                blurRadius: 18,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 64,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: isUnread ? 0.70 : 0.30),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 10),
              _ConversationAvatar(style: style, isUnread: isUnread),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.charcoal,
                              fontSize: 17,
                              fontWeight: isUnread
                                  ? FontWeight.w900
                                  : FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (unreadCount > 0) _UnreadBadge(count: unreadCount),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _StatusPill(label: style.label, color: style.color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            convo.serviceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatInboxTime(convo.lastMessageAt),
                          style: TextStyle(
                            color: isUnread
                                ? AppColors.charcoal
                                : AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: isUnread
                                ? FontWeight.w900
                                : FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        height: 1.25,
                        fontWeight: isUnread
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<InboxConversation> _filteredConversations() {
    return viewModel.conversations.where((convo) {
      return switch (_selectedFilter) {
        _InboxFilter.all => true,
        _InboxFilter.enquiries => _isEnquiry(convo),
        _InboxFilter.bookings => _isBooking(convo),
        _InboxFilter.community =>
          convo.isCommunityHelp || convo.conversationType == 'activity',
        _InboxFilter.business =>
          convo.conversationType == 'business_to_business',
      };
    }).toList();
  }

  bool get _showFilters =>
      !viewModel.isLoading &&
      viewModel.errorMessage == null &&
      viewModel.conversations.length >= 6;

  bool _isBooking(InboxConversation convo) {
    return convo.conversationStatus == 'booking' || convo.bookingId.isNotEmpty;
  }

  bool _isEnquiry(InboxConversation convo) {
    if (convo.isCommunityHelp) return false;
    if (convo.conversationType == 'business_to_business') return false;
    if (convo.conversationType == 'activity') return false;
    return !_isBooking(convo);
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
        label: 'Community',
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

    final dynamic rawDate = timestamp is DateTime
        ? timestamp
        : timestamp.toDate();
    if (rawDate is! DateTime) return '';

    final date = rawDate.toLocal();
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

enum _InboxFilter {
  all('All'),
  enquiries('Enquiries'),
  bookings('Bookings'),
  community('Community'),
  business('Business');

  const _InboxFilter(this.label);

  final String label;
}

class _InboxHeader extends StatelessWidget {
  const _InboxHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Inbox',
          style: TextStyle(
            color: AppColors.charcoal,
            fontSize: 34,
            height: 1.02,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Bookings, enquiries and community replies in one place.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 15,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 18),
      ],
    );
  }
}

class _InboxFilters extends StatelessWidget {
  const _InboxFilters({required this.selected, required this.onSelected});

  final _InboxFilter selected;
  final ValueChanged<_InboxFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final filter = _InboxFilter.values[index];
          final isSelected = selected == filter;
          return ChoiceChip(
            label: Text(filter.label),
            selected: isSelected,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            selectedColor: AppColors.primary.withValues(alpha: 0.14),
            backgroundColor: AppColors.card,
            side: BorderSide(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : AppColors.border,
            ),
            labelStyle: TextStyle(
              color: isSelected ? AppColors.primary : AppColors.textMuted,
              fontWeight: FontWeight.w900,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            onSelected: (_) => onSelected(filter),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemCount: _InboxFilter.values.length,
      ),
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({required this.style, required this.isUnread});

  final _ConversationStyle style;
  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: style.color.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(style.icon, color: style.color, size: 23),
        ),
        if (isUnread)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: style.color,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.card, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : count.toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.buttonText,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptyInboxIcon extends StatelessWidget {
  const _EmptyInboxIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 34, color: AppColors.primary),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
