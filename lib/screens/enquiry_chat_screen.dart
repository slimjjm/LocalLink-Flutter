import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../viewmodels/enquiry_chat_view_model.dart';
import '../models/chat_message.dart';

class EnquiryChatScreen
    extends StatefulWidget {

  final String businessId;
  final String customerId;

  const EnquiryChatScreen({
    super.key,
    required this.businessId,
    required this.customerId,
  });

  @override
  State<EnquiryChatScreen> createState() =>
      _EnquiryChatScreenState();
}

class _EnquiryChatScreenState
    extends State<EnquiryChatScreen> {

  final EnquiryChatViewModel
      viewModel =
          EnquiryChatViewModel();

  final TextEditingController
      controller =
          TextEditingController();

  final ScrollController
      scrollController =
          ScrollController();

  @override
  void initState() {
    super.initState();

    viewModel.onUpdated = () {

      if (mounted) {
        setState(() {});
      }

      Future.delayed(
        const Duration(milliseconds: 100),
        scrollToBottom,
      );
    };

    viewModel.startListening(
      businessId: widget.businessId,
      customerId: widget.customerId,
    );
  }

  @override
  void dispose() {

    controller.dispose();

    scrollController.dispose();

    viewModel.dispose();

    super.dispose();
  }

  void scrollToBottom() {

    if (!scrollController.hasClients) {
      return;
    }

    scrollController.animateTo(

      scrollController.position.maxScrollExtent,

      duration:
          const Duration(milliseconds: 300),

      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text('Chat'),
      ),

      body: Column(

        children: [

          Expanded(

            child: ListView.builder(

              controller:
                  scrollController,

              padding:
                  const EdgeInsets.all(16),

              itemCount:
                  viewModel.messages.length,

              itemBuilder:
                  (context, index) {

                final message =
                    viewModel.messages[index];

                return _messageBubble(
                  message,
                );
              },
            ),
          ),

          _inputBar(),
        ],
      ),
    );
  }

  Widget _messageBubble(
    ChatMessage message,
  ) {

    final currentUid =
        FirebaseAuth.instance
            .currentUser
            ?.uid;

    final isMine =
        message.senderId ==
            currentUid;

    return Align(

      alignment:
          isMine
              ? Alignment.centerRight
              : Alignment.centerLeft,

      child: Container(

        margin:
            const EdgeInsets.only(
          bottom: 10,
        ),

        padding:
            const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),

        constraints:
            const BoxConstraints(
          maxWidth: 280,
        ),

        decoration: BoxDecoration(

          color:
              isMine
                  ? const Color(
                      0xFFF26A2E,
                    )
                  : Colors.grey.shade200,

          borderRadius:
              BorderRadius.circular(
            18,
          ),
        ),

        child: Text(

          message.text,

          style: TextStyle(

            color:
                isMine
                    ? Colors.white
                    : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _inputBar() {

    return SafeArea(

      child: Container(

        padding:
            const EdgeInsets.all(12),

        child: Row(

          children: [

            Expanded(

              child: TextField(

                controller:
                    controller,

                decoration:
                    InputDecoration(

                  hintText:
                      'Type message...',

                  filled: true,

                  fillColor:
                      Colors.grey.shade100,

                  border:
                      OutlineInputBorder(

                    borderRadius:
                        BorderRadius.circular(
                      24,
                    ),

                    borderSide:
                        BorderSide.none,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 10),

            CircleAvatar(

              radius: 24,

              backgroundColor:
                  const Color(
                0xFFF26A2E,
              ),

              child: IconButton(

                icon: const Icon(
                  Icons.send,
                  color: Colors.white,
                ),

                onPressed: () async {

                  final text =
                      controller.text;

                  controller.clear();

                  await viewModel
                      .sendMessage(
                    text,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}