import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/helpers.dart';
import '../services/local_link_share_service.dart';
import 'booking_screen.dart';
import 'business_detail_screen.dart';

class AvailabilityDetailScreen extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> availabilityData;
  final Map<String, dynamic> businessData;

  const AvailabilityDetailScreen({
    super.key,
    required this.postId,
    required this.availabilityData,
    required this.businessData,
  });

  String _dateTimeLabel(BuildContext context) {
    final type = safeText(
      availabilityData['type'] ?? availabilityData['availabilityType'],
      'exact',
    );
    final value =
        availabilityData['startDateTime'] ?? availabilityData['availabilityAt'];
    if (value is! Timestamp) return 'Time to agree';

    final date = value.toDate();
    final time = TimeOfDay.fromDateTime(date).format(context);

    if (type == 'flexible') {
      final until = availabilityData['availableUntil'];
      if (until is Timestamp) {
        final untilDate = until.toDate();
        return '${date.day}/${date.month}/${date.year} to ${untilDate.day}/${untilDate.month}/${untilDate.year}';
      }
    }

    if (type == 'window') {
      final end =
          availabilityData['endDateTime'] ?? availabilityData['endTime'];
      if (end is Timestamp) {
        return '${date.day}/${date.month}/${date.year}, $time to ${TimeOfDay.fromDateTime(end.toDate()).format(context)}';
      }
    }

    return '${date.day}/${date.month}/${date.year} at $time';
  }

  bool get _isFlexible {
    final type = safeText(
      availabilityData['type'] ?? availabilityData['availabilityType'],
      'exact',
    );
    return type == 'flexible';
  }

  String _buttonLabel() {
    if (_isFlexible) return 'Ask to Book';
    final type = safeText(
      availabilityData['type'] ?? availabilityData['availabilityType'],
      'exact',
    );
    if (type == 'window') return 'Choose a Time';
    return 'Book This Time';
  }

  Future<void> _requestFlexibleBooking(BuildContext context) async {
    final businessId = safeText(availabilityData['businessId'], '');
    final serviceId = safeText(availabilityData['serviceId'], '');
    final user = FirebaseAuth.instance.currentUser;
    if (businessId.isEmpty || serviceId.isEmpty) return;

    if (user == null || user.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to request a booking.')),
      );
      return;
    }

    final note = await showAskToBookDialog(context);

    if (note == null || note.isEmpty || !context.mounted) return;

    try {
      await FirebaseFirestore.instance.collection('serviceRequests').add({
        'customerId': user.uid,
        'businessId': businessId,
        'availabilityPostId': postId,
        'serviceId': serviceId,
        'category': safeText(availabilityData['category'], ''),
        'title': safeText(availabilityData['serviceName'], 'Request for help'),
        'description': note,
        'timingType': 'flexible',
        'status': 'open',
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': availabilityData['availableUntil'],
      });

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your request has been sent.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('We could not send that request.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessId = safeText(availabilityData['businessId'], '');
    final serviceId = safeText(availabilityData['serviceId'], '');
    final businessName = safeText(
      availabilityData['businessName'] ?? businessData['businessName'],
      'Business',
    );
    final serviceName = safeText(availabilityData['serviceName'], 'Service');
    final description = safeText(availabilityData['description'], '');
    final duration = availabilityData['durationMinutes'];
    final price = formatPrice(availabilityData['price']);
    final paymentMethods = resolvePaymentMethods(businessData);
    final rating = businessData['averageRating'];
    final reviewCount = businessData['reviewCount'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Time Available'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: 'Share',
            onPressed: () async {
              try {
                final photoURLs = businessData['photoURLs'];
                await LocalLinkShareService().shareItem(
                  item: LocalLinkShareItem(
                    type: LocalLinkShareItemType.availability,
                    id: postId,
                    data: {
                      ...availabilityData,
                      'businessName': businessName,
                      'coverPhoto': photoURLs is List && photoURLs.isNotEmpty
                          ? photoURLs.first
                          : null,
                    },
                  ),
                );
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sharing could not be started.'),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            serviceName,
            style: const TextStyle(
              color: AppColors.charcoal,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            businessName,
            style: const TextStyle(
              color: AppColors.serviceGreen,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          _DetailRow(
            icon: Icons.schedule_outlined,
            label: _dateTimeLabel(context),
          ),
          if (duration != null)
            _DetailRow(icon: Icons.timer_outlined, label: '$duration minutes'),
          _DetailRow(icon: Icons.payments_outlined, label: price),
          const SizedBox(height: 18),
          if (description.isNotEmpty)
            Text(
              description,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 16,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 24),
          if (rating is num)
            _DetailRow(
              icon: Icons.star_rounded,
              label:
                  '${rating.toStringAsFixed(1)} stars from ${reviewCount ?? 0} reviews',
            )
          else
            const Text(
              'Reviews and trust signals are shown on the business profile.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: businessId.isEmpty || serviceId.isEmpty
                ? null
                : () {
                    if (_isFlexible) {
                      _requestFlexibleBooking(context);
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BookingScreen(
                          businessId: businessId,
                          businessName: businessName,
                          serviceId: serviceId,
                          serviceData: {
                            'name': serviceName,
                            'details':
                                availabilityData['serviceDetails'] ??
                                availabilityData['description'],
                            'price': availabilityData['price'],
                            'durationMinutes': duration,
                            'availabilityPostId': postId,
                            'availabilityType':
                                availabilityData['type'] ??
                                availabilityData['availabilityType'],
                            'availabilityStartTime':
                                availabilityData['startDateTime'] ??
                                availabilityData['startTime'] ??
                                availabilityData['availabilityAt'],
                            'availabilityEndTime': availabilityData['endTime'],
                            'availabilityAvailableUntil':
                                availabilityData['availableUntil'],
                            'availabilitySlotId': availabilityData['slotId'],
                            'availabilitySlotPath':
                                availabilityData['slotPath'],
                            'availabilityStaffId': availabilityData['staffId'],
                            'availabilityStaffName':
                                availabilityData['staffName'],
                          },
                          paymentMethods: paymentMethods,
                        ),
                      ),
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.serviceGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: Text(_buttonLabel()),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: businessId.isEmpty
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BusinessDetailScreen(businessId: businessId),
                      ),
                    );
                  },
            child: const Text('View Business'),
          ),
        ],
      ),
    );
  }
}

@visibleForTesting
Future<String?> showAskToBookDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const AskToBookDialog(),
  );
}

@visibleForTesting
class AskToBookDialog extends StatefulWidget {
  const AskToBookDialog({super.key});

  @override
  State<AskToBookDialog> createState() => _AskToBookDialogState();
}

class _AskToBookDialogState extends State<AskToBookDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasSubmitted = false;

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    if (_hasSubmitted) return;
    _hasSubmitted = true;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ask to book'),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        minLines: 3,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Tell the business what time would suit you.',
        ),
        onSubmitted: (_) => _send(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _send, child: const Text('Send')),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: AppColors.serviceGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
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
