import 'package:flutter/material.dart';

import '../models/inbox_conversation.dart';
import '../viewmodels/inbox_view_model.dart';

import 'enquiry_chat_screen.dart';

class InboxScreen extends StatefulWidget {

  final String? businessId;
  final String currentRole;

  const InboxScreen({
    super.key,
    this.businessId,
    required this.currentRole,
  });

  @override
  State<InboxScreen> createState() =>
      _InboxScreenState();
}

class _InboxScreenState
    extends State<InboxScreen> {

  final InboxViewModel viewModel =
      InboxViewModel();

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

      businessId:
          widget.businessId ?? '',
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

      appBar: AppBar(
        title: const Text('Inbox'),
      ),

      body: viewModel.conversations.isEmpty
          ? _emptyState()
          : ListView.builder(

              itemCount:
                  viewModel.conversations.length,

              itemBuilder: (
                context,
                index,
              ) {

                final convo =
                    viewModel.conversations[index];

                return _conversationTile(
                  convo,
                );
              },
            ),
    );
  }

  Widget _emptyState() {

    return const Center(

      child: Column(

        mainAxisAlignment:
            MainAxisAlignment.center,

        children: [

          Icon(
            Icons.chat_bubble_outline,
            size: 70,
          ),

          SizedBox(height: 16),

          Text(
            'No conversations yet',
          ),
        ],
      ),
    );
  }

  Widget _conversationTile(
    InboxConversation convo,
  ) {

    return ListTile(

      leading: CircleAvatar(

        child: Text(

          widget.currentRole == 'business'
              ? convo.customerName
                    .substring(0, 1)
                    .toUpperCase()
              : convo.businessName
                    .substring(0, 1)
                    .toUpperCase(),
        ),
      ),

      title: Text(

        widget.currentRole == 'business'
            ? convo.customerName
            : convo.businessName,
      ),

      subtitle: Text(

        convo.lastMessage,

        maxLines: 1,

        overflow:
            TextOverflow.ellipsis,
      ),

     trailing:
    (widget.currentRole == 'business'
            ? convo.businessUnreadCount
            : convo.customerUnreadCount) > 0
        ? CircleAvatar(

            radius: 12,

            child: Text(

              (widget.currentRole == 'business'
                      ? convo.businessUnreadCount
                      : convo.customerUnreadCount)
                  .toString(),

              style: const TextStyle(
                fontSize: 12,
              ),
            ),
          )
        : null,

      onTap: () {

        Navigator.push(

          context,

          MaterialPageRoute(

            builder: (_) =>
                EnquiryChatScreen(

              businessId:
                  convo.businessId,

              customerId:
                  convo.customerId,
            ),
          ),
        );
      },
    );
  }
}