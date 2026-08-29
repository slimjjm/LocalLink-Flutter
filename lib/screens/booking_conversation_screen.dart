import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/booking_conversation.dart';
import '../models/booking_message.dart';
import '../services/booking_messaging_service.dart';
import '../theme/app_colors.dart';

class BookingConversationScreen extends StatefulWidget {
  const BookingConversationScreen({
    super.key,
    required this.conversationId,
    required this.viewerType,
    this.bookingId,
  });

  final String conversationId;
  final String viewerType;
  final String? bookingId;

  @override
  State<BookingConversationScreen> createState() =>
      _BookingConversationScreenState();
}

class _BookingConversationScreenState extends State<BookingConversationScreen> {
  final BookingMessagingService _service = BookingMessagingService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _composerFocusNode = FocusNode();

  late final Future<String> _conversationFuture;
  String? _resolvedConversationId;
  bool _isSending = false;
  bool _isMarkingRead = false;
  String? _retryText;
  int? _initialUnreadCount;

  @override
  void initState() {
    super.initState();

    _conversationFuture = widget.bookingId == null
        ? _service.ensureConversationAccess(widget.conversationId)
        : _service.ensureBookingConversation(widget.bookingId!);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  void _scheduleScrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;

      final target = _scrollController.position.maxScrollExtent;

      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _markReadIfNeeded(BookingConversation conversation) {
    final unreadCount = conversation.unreadCountFor(widget.viewerType);

    _initialUnreadCount ??= unreadCount > 0 ? unreadCount : 0;

    if (unreadCount == 0 || _isMarkingRead) return;

    final conversationId = _resolvedConversationId;
    if (conversationId == null) return;

    _isMarkingRead = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isMarkingRead = false;
        return;
      }

      _service.markRead(conversationId).whenComplete(() {
        _isMarkingRead = false;
      });
    });
  }

  Future<void> _sendMessage(
    BookingConversation conversation, {
    String? retryText,
  }) async {
    final text = (retryText ?? _controller.text).trim();

    if (text.isEmpty || _isSending || conversation.archived) return;

    setState(() {
      _isSending = true;
      _retryText = null;
    });

    try {
      if (retryText == null) {
        _controller.clear();
      }

      await _service.sendMessage(conversationId: conversation.id, text: text);

      _scheduleScrollToBottom();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _retryText = text;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Message could not be sent. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _editMessage(BookingMessage message) async {
    final editController = TextEditingController(text: message.text);

    final newText = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit message'),
          content: TextField(
            controller: editController,
            autofocus: true,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Message'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, editController.text.trim());
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    editController.dispose();

    if (newText == null || newText.isEmpty || newText == message.text) {
      return;
    }

    try {
      await _service.editMessage(
        conversationId: _resolvedConversationId!,
        messageId: message.id,
        text: newText,
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That message can no longer be edited.')),
      );
    }
  }

  Future<void> _deleteMessage(BookingMessage message) async {
    try {
      await _service.deleteMessage(
        conversationId: _resolvedConversationId!,
        messageId: message.id,
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message could not be deleted.')),
      );
    }
  }

  void _showMessageActions(BookingMessage message, bool isMine, bool archived) {
    if (message.deleted) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy message'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message.text));
                  Navigator.pop(context);
                },
              ),
              if (isMine && !archived && message.canStillEdit)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit message'),
                  onTap: () {
                    Navigator.pop(context);
                    _editMessage(message);
                  },
                ),
              if (isMine && !archived)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete message'),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteMessage(message);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _conversationFuture,
      builder: (context, futureSnapshot) {
        if (futureSnapshot.connectionState != ConnectionState.done) {
          return const _MessagingSkeleton();
        }

        if (futureSnapshot.hasError) {
          return const _ConversationError();
        }

        _resolvedConversationId = futureSnapshot.data;

        return StreamBuilder<BookingConversation?>(
          stream: _service.watchConversation(_resolvedConversationId!),
          builder: (context, conversationSnapshot) {
            final conversation = conversationSnapshot.data;

            if (conversationSnapshot.hasError) {
              return const _ConversationError();
            }

            if (conversation == null) {
              return const _MessagingSkeleton();
            }

            _markReadIfNeeded(conversation);

            return Scaffold(
              resizeToAvoidBottomInset: true,
              backgroundColor: AppColors.background,
              appBar: AppBar(
                title: Text(
                  conversation.isCommunityHelp
                      ? 'Community Help'
                      : widget.viewerType == 'business'
                      ? 'Message Customer'
                      : 'Message Business',
                ),
              ),
              body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  FocusScope.of(context).unfocus();
                },
                child: Column(
                  children: [
                    _PinnedBookingHeader(
                      conversation: conversation,
                      viewerType: widget.viewerType,
                    ),
                    if (conversation.archived) const _ArchivedBanner(),
                    Expanded(
                      child: StreamBuilder<List<BookingMessage>>(
                        stream: _service.watchMessages(
                          _resolvedConversationId!,
                        ),
                        builder: (context, messagesSnapshot) {
                          final messages =
                              messagesSnapshot.data ?? const <BookingMessage>[];

                          if (messagesSnapshot.hasError) {
                            return const _InlineError(
                              message:
                                  'Messages are having trouble loading. Pull back and try again.',
                            );
                          }

                          if (messagesSnapshot.connectionState ==
                                  ConnectionState.waiting &&
                              messages.isEmpty) {
                            return const _MessageSkeletonList();
                          }

                          if (messages.isEmpty) {
                            return const _EmptyMessages();
                          }

                          _scheduleScrollToBottom(animated: false);

                          return _MessageList(
                            messages: messages,
                            controller: _scrollController,
                            initialUnreadCount: _initialUnreadCount ?? 0,
                            archived: conversation.archived,
                            onMessageLongPress: _showMessageActions,
                          );
                        },
                      ),
                    ),
                    if (_retryText != null)
                      _RetrySendBanner(
                        onRetry: () =>
                            _sendMessage(conversation, retryText: _retryText),
                        onDismiss: () {
                          setState(() {
                            _retryText = null;
                          });
                        },
                      ),
                    _TypingPlaceholder(archived: conversation.archived),
                    _Composer(
                      controller: _controller,
                      focusNode: _composerFocusNode,
                      isSending: _isSending,
                      archived: conversation.archived,
                      waitingForCustomer:
                          widget.viewerType == 'business' &&
                          !conversation.customerHasMessaged,
                      onSend: () => _sendMessage(conversation),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MessagingSkeleton extends StatelessWidget {
  const _MessagingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _SkeletonBlock(height: 92, margin: EdgeInsets.all(16)),
            Expanded(child: _MessageSkeletonList()),
          ],
        ),
      ),
    );
  }
}

class _MessageSkeletonList extends StatelessWidget {
  const _MessageSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: const [
        _SkeletonBlock(height: 46, widthFactor: 0.72, alignRight: false),
        _SkeletonBlock(height: 62, widthFactor: 0.64, alignRight: true),
        _SkeletonBlock(height: 48, widthFactor: 0.55, alignRight: false),
      ],
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.height,
    this.widthFactor = 1,
    this.alignRight = false,
    this.margin,
  });

  final double height;
  final double widthFactor;
  final bool alignRight;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: height,
          margin: margin ?? const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

class _ConversationError extends StatelessWidget {
  const _ConversationError();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: const _InlineError(
        message:
            'Messages are available once this confirmed booking can be verified.',
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}

class _PinnedBookingHeader extends StatelessWidget {
  const _PinnedBookingHeader({
    required this.conversation,
    required this.viewerType,
  });

  final BookingConversation conversation;
  final String viewerType;

  @override
  Widget build(BuildContext context) {
    final hasBooking = conversation.currentBookingId.isNotEmpty;
    final isCommunityHelp = conversation.isCommunityHelp;
    final otherName = viewerType == 'business'
        ? conversation.customerName
        : conversation.businessName;
    final headline = isCommunityHelp ? otherName : conversation.businessName;
    final contextTitle = isCommunityHelp
        ? conversation.currentBookingServiceName
        : hasBooking
        ? conversation.currentBookingServiceName
        : 'Enquiry';
    final detailText = isCommunityHelp
        ? 'Community Help'
        : hasBooking
        ? _formatBookingDate(conversation.bookingStartAt)
        : 'Started from ${conversation.originatingServiceName}';

    return Semantics(
      label:
          'Conversation with $headline, status ${isCommunityHelp
              ? 'Community Help'
              : hasBooking
              ? conversation.currentBookingStatus
              : 'Enquiry'}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            _ServiceImage(imageUrl: conversation.serviceImageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.charcoal,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    contextTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.charcoal,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detailText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _StatusChip(
                        status: isCommunityHelp
                            ? 'community_help'
                            : hasBooking
                            ? conversation.conversationStatus
                            : 'enquiry',
                      ),
                      Text(
                        isCommunityHelp
                            ? 'Private reply'
                            : viewerType == 'business'
                            ? otherName
                            : 'Origin: ${conversation.originatingServiceName}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBookingDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Date to be confirmed';

    final date = timestamp.toDate().toLocal();
    final minute = date.minute.toString().padLeft(2, '0');

    return '${date.day}/${date.month}/${date.year} at ${date.hour}:$minute';
  }
}

class _ServiceImage extends StatelessWidget {
  const _ServiceImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.serviceGreen.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.handshake_outlined,
          color: AppColors.serviceGreen,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: 52,
            height: 52,
            color: AppColors.surface,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 52,
            height: 52,
            color: AppColors.surface,
            child: const Icon(
              Icons.handshake_outlined,
              color: AppColors.serviceGreen,
            ),
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.serviceGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status == 'booking'
            ? 'Booking'
            : status == 'completed'
            ? 'Completed'
            : status == 'community_help'
            ? 'Community Help'
            : 'Enquiry',
        style: const TextStyle(
          color: AppColors.serviceGreen,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ArchivedBanner extends StatelessWidget {
  const _ArchivedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Text(
        'This conversation is archived and read-only.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'No messages yet. Share arrival details, access notes or questions here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, height: 1.35),
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.controller,
    required this.initialUnreadCount,
    required this.archived,
    required this.onMessageLongPress,
  });

  final List<BookingMessage> messages;
  final ScrollController controller;
  final int initialUnreadCount;
  final bool archived;
  final void Function(BookingMessage message, bool isMine, bool archived)
  onMessageLongPress;

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final firstUnreadIndex = _firstUnreadIndex(messages, currentUid);

    return ListView.builder(
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final previous = index == 0 ? null : messages[index - 1];
        final isMine = message.senderId == currentUid;
        final showDate = _shouldShowDateSeparator(previous, message);
        final showUnread = initialUnreadCount > 0 && index == firstUnreadIndex;
        final isLastOwnRead =
            isMine &&
            message.read &&
            !_hasLaterOwnMessage(messages, index, currentUid);

        return Column(
          children: [
            if (showDate) _DateSeparator(timestamp: message.timestamp),
            if (showUnread) const _UnreadDivider(),
            TweenAnimationBuilder<double>(
              key: ValueKey(message.id),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: _MessageBubble(
                message: message,
                isMine: isMine,
                showSeen: isLastOwnRead,
                onLongPress: () {
                  onMessageLongPress(message, isMine, archived);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  int _firstUnreadIndex(List<BookingMessage> messages, String? currentUid) {
    if (initialUnreadCount <= 0) return -1;

    final candidateIndexes = <int>[];

    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message.senderId != currentUid && !message.read) {
        candidateIndexes.add(i);
      }
    }

    if (candidateIndexes.isEmpty) return -1;

    final offset = candidateIndexes.length - initialUnreadCount;

    return candidateIndexes[offset < 0 ? 0 : offset];
  }

  bool _hasLaterOwnMessage(
    List<BookingMessage> messages,
    int index,
    String? currentUid,
  ) {
    for (var i = index + 1; i < messages.length; i++) {
      if (messages[i].senderId == currentUid) {
        return true;
      }
    }

    return false;
  }

  bool _shouldShowDateSeparator(
    BookingMessage? previous,
    BookingMessage current,
  ) {
    final currentDate = current.timestamp?.toDate().toLocal();

    if (currentDate == null) return false;
    if (previous == null) return true;

    final previousDate = previous.timestamp?.toDate().toLocal();

    if (previousDate == null) return true;

    return currentDate.year != previousDate.year ||
        currentDate.month != previousDate.month ||
        currentDate.day != previousDate.day;
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.timestamp});

  final Timestamp? timestamp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        _label(timestamp),
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _label(Timestamp? timestamp) {
    final date = timestamp?.toDate().toLocal();
    if (date == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);
    final difference = today.difference(messageDay).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return _weekday(date.weekday);

    return '${date.day}/${date.month}/${date.year}';
  }

  String _weekday(int weekday) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return names[weekday - 1];
  }
}

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.serviceGreen)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'Unread',
              style: TextStyle(
                color: AppColors.serviceGreen,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(child: Divider(color: AppColors.serviceGreen)),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showSeen,
    required this.onLongPress,
  });

  final BookingMessage message;
  final bool isMine;
  final bool showSeen;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine ? AppColors.serviceGreen : AppColors.card;
    final textColor = isMine ? AppColors.buttonText : AppColors.charcoal;
    final mutedColor = isMine
        ? AppColors.buttonText.withValues(alpha: 0.78)
        : AppColors.textMuted;
    final imageAttachments = message.deleted
        ? const <Map<String, dynamic>>[]
        : message.attachments
              .where(
                (attachment) =>
                    attachment['type'] == 'image' &&
                    (attachment['url'] as String? ?? '').trim().isNotEmpty,
              )
              .toList();

    return Semantics(
      label: isMine ? 'Your message' : 'Message received',
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMine ? 18 : 5),
                bottomRight: Radius.circular(isMine ? 5 : 18),
              ),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...imageAttachments.map(
                  (attachment) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MessageImageAttachment(
                      imageUrl: (attachment['url'] as String).trim(),
                    ),
                  ),
                ),
                Text(
                  message.deleted ? 'Message deleted' : message.text,
                  softWrap: true,
                  style: TextStyle(
                    color: message.deleted ? mutedColor : textColor,
                    fontSize: 15,
                    height: 1.3,
                    fontStyle: message.deleted
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _formatTime(message.timestamp),
                      style: TextStyle(color: mutedColor, fontSize: 11),
                    ),
                    if (message.edited && !message.deleted)
                      Text(
                        'edited',
                        style: TextStyle(color: mutedColor, fontSize: 11),
                      ),
                    if (isMine)
                      Icon(
                        message.read ? Icons.done_all : Icons.done,
                        size: 14,
                        color: mutedColor,
                      ),
                    if (showSeen)
                      Text(
                        'Seen',
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return 'Sending';

    final date = timestamp.toDate().toLocal();

    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}

class _MessageImageAttachment extends StatelessWidget {
  const _MessageImageAttachment({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              color: AppColors.surface,
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: AppColors.surface,
              alignment: Alignment.center,
              child: const Icon(
                Icons.image_not_supported_outlined,
                color: AppColors.textMuted,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RetrySendBanner extends StatelessWidget {
  const _RetrySendBanner({required this.onRetry, required this.onDismiss});

  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Message not sent.',
              style: TextStyle(
                color: AppColors.charcoal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _TypingPlaceholder extends StatelessWidget {
  const _TypingPlaceholder({required this.archived});

  final bool archived;

  @override
  Widget build(BuildContext context) {
    if (archived) {
      return const SizedBox.shrink();
    }

    return const SizedBox(height: 4);
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.archived,
    required this.waitingForCustomer,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final bool archived;
  final bool waitingForCustomer;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Semantics(
                label: 'Message input',
                textField: true,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !archived && !isSending && !waitingForCustomer,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: archived
                        ? 'Conversation archived'
                        : waitingForCustomer
                        ? 'Waiting for the customer to message first'
                        : 'Message...',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 48,
              height: 48,
              child: IconButton.filled(
                tooltip: 'Send message',
                onPressed: archived || isSending || waitingForCustomer
                    ? null
                    : onSend,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.serviceGreen,
                  disabledBackgroundColor: AppColors.disabled,
                  minimumSize: const Size(48, 48),
                ),
                icon: isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.buttonText,
                        ),
                      )
                    : const Icon(Icons.send),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
