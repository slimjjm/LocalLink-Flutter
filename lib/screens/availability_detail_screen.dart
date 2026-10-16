import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../utils/helpers.dart';
import '../services/auth_required_action.dart';
import '../services/booking_visibility_service.dart';
import '../services/local_link_share_service.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_form.dart';
import '../widgets/local_link_image.dart';
import '../widgets/local_link_surface_card.dart';
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

  DateTime? _startDate() {
    final value =
        availabilityData['startDateTime'] ?? availabilityData['availabilityAt'];
    return value is Timestamp ? value.toDate() : null;
  }

  DateTime? _endDate() {
    final value =
        availabilityData['endDateTime'] ?? availabilityData['endTime'];
    return value is Timestamp ? value.toDate() : null;
  }

  DateTime? _availableUntilDate() {
    final value = availabilityData['availableUntil'];
    return value is Timestamp ? value.toDate() : null;
  }

  String _dateLabel() {
    final type = safeText(
      availabilityData['type'] ?? availabilityData['availabilityType'],
      'exact',
    );
    final date = _startDate();
    if (date == null) return 'Time to agree';

    if (type == 'flexible') {
      final untilDate = _availableUntilDate();
      if (untilDate != null) {
        return '${_shortDate(date)} to ${_shortDate(untilDate)}';
      }
    }

    return '${_weekday(date)} ${date.day} ${_month(date)}';
  }

  String _timeLabel(BuildContext context) {
    final type = safeText(
      availabilityData['type'] ?? availabilityData['availabilityType'],
      'exact',
    );
    final start = _startDate();
    if (start == null) return 'Time to agree';
    if (type == 'flexible') return 'Flexible timing';

    final startTime = TimeOfDay.fromDateTime(start).format(context);
    final end = _endDate();
    if (end != null) {
      return '$startTime - ${TimeOfDay.fromDateTime(end).format(context)}';
    }

    return startTime;
  }

  String _shortDate(DateTime value) {
    return '${value.day} ${_month(value)}';
  }

  String _weekday(DateTime value) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[value.weekday - 1];
  }

  String _month(DateTime value) {
    const labels = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return labels[value.month - 1];
  }

  bool get _isFlexible {
    final type = safeText(
      availabilityData['type'] ?? availabilityData['availabilityType'],
      'exact',
    );
    return type == 'flexible';
  }

  String _buttonLabel() {
    if (_isFlexible) return 'Ask to book';
    return 'Choose this time';
  }

  Future<void> _requestFlexibleBooking(BuildContext context) async {
    final businessId = safeText(availabilityData['businessId'], '');
    final serviceId = safeText(availabilityData['serviceId'], '');
    final user = FirebaseAuth.instance.currentUser;
    if (businessId.isEmpty || serviceId.isEmpty) return;

    if (user == null || user.isAnonymous) {
      await AuthRequiredAction.run(
        context,
        action: () => _requestFlexibleBooking(context),
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
    final description = safeText(
      availabilityData['serviceDetails'] ??
          availabilityData['details'] ??
          availabilityData['description'],
      '',
    );
    final duration = availabilityData['durationMinutes'];
    final price = formatPrice(availabilityData['price']);
    final paymentMethods = resolvePaymentMethods(businessData);
    final isUsable = isAvailabilityUsable(availabilityData, DateTime.now());

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
        padding: const EdgeInsets.all(LocalLinkSpacing.lg),
        children: [
          Text(
            serviceName,
            style: LocalLinkTextStyles.screenTitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: LocalLinkSpacing.sm),
          _BusinessSummaryCard(
            businessName: businessName,
            businessData: businessData,
            onTap: businessId.isEmpty
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
          ),
          const SizedBox(height: LocalLinkSpacing.lg),
          _AvailabilityHeroCard(
            dateLabel: _dateLabel(),
            timeLabel: _timeLabel(context),
            durationLabel: duration == null ? null : '$duration min',
            priceLabel: price,
            isUsable: isUsable,
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: LocalLinkSpacing.md),
            LocalLinkSurfaceCard(
              elevated: false,
              padding: const EdgeInsets.all(LocalLinkSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('About this service', style: LocalLinkTextStyles.label),
                  const SizedBox(height: LocalLinkSpacing.xs),
                  Text(description, style: LocalLinkTextStyles.body),
                ],
              ),
            ),
          ],
          const SizedBox(height: LocalLinkSpacing.xl),
          LocalLinkButton(
            label: isUsable ? _buttonLabel() : 'No longer available',
            icon: _isFlexible
                ? Icons.chat_bubble_outline_rounded
                : Icons.event_available_outlined,
            expand: true,
            onPressed: businessId.isEmpty || serviceId.isEmpty || !isUsable
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
          ),
          const SizedBox(height: LocalLinkSpacing.xs),
          LocalLinkButton(
            label: 'View business',
            icon: Icons.storefront_outlined,
            variant: LocalLinkButtonVariant.secondary,
            expand: true,
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
  bool _hasSubmitted = false;

  @override
  void dispose() {
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
      content: LocalLinkFormField(
        controller: _controller,
        maxLines: 5,
        label: 'Message',
        hintText: 'Tell the business what time would suit you.',
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

class _AvailabilityHeroCard extends StatelessWidget {
  const _AvailabilityHeroCard({
    required this.dateLabel,
    required this.timeLabel,
    required this.priceLabel,
    required this.isUsable,
    this.durationLabel,
  });

  final String dateLabel;
  final String timeLabel;
  final String priceLabel;
  final String? durationLabel;
  final bool isUsable;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      elevated: true,
      color: AppColors.elevatedSurface,
      padding: const EdgeInsets.all(LocalLinkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LocalLinkIconBadge(
                icon: Icons.event_available_outlined,
                color: AppColors.serviceGreen,
              ),
              const SizedBox(width: LocalLinkSpacing.sm),
              Expanded(
                child: Text(
                  isUsable ? 'Available appointment' : 'No longer available',
                  style: LocalLinkTextStyles.label.copyWith(
                    color: isUsable ? AppColors.serviceGreen : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LocalLinkSpacing.lg),
          Text(
            dateLabel,
            style: LocalLinkTextStyles.sectionTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: LocalLinkSpacing.xs),
          Text(
            timeLabel,
            style: const TextStyle(
              color: AppColors.charcoal,
              fontSize: 28,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          Wrap(
            spacing: LocalLinkSpacing.sm,
            runSpacing: LocalLinkSpacing.sm,
            children: [
              if (durationLabel != null)
                _InfoPill(icon: Icons.timer_outlined, label: durationLabel!),
              _InfoPill(
                icon: Icons.payments_outlined,
                label: priceLabel,
                strong: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusinessSummaryCard extends StatelessWidget {
  const _BusinessSummaryCard({
    required this.businessName,
    required this.businessData,
    this.onTap,
  });

  final String businessName;
  final Map<String, dynamic> businessData;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = _businessImageUrl(businessData);
    final location = safeText(
      businessData['publicLocation'] ??
          businessData['serviceArea'] ??
          businessData['location'] ??
          businessData['address'],
      '',
    );
    final rating = businessData['rating'] ?? businessData['averageRating'];
    final reviewCount = businessData['reviewCount'];
    final verified =
        businessData['verified'] == true ||
        businessData['stripeChargesEnabled'] == true ||
        businessData['chargesEnabled'] == true;
    final claimed =
        businessData['isClaimed'] == true ||
        businessData['listingOwnershipStatus'] == 'claimed';
    final trustItems = <Widget>[
      if (rating is num)
        _InfoPill(
          icon: Icons.star_rounded,
          label: reviewCount is num && reviewCount > 0
              ? '${rating.toStringAsFixed(1)} (${reviewCount.toInt()})'
              : rating.toStringAsFixed(1),
        ),
      if (verified)
        const _InfoPill(icon: Icons.verified_rounded, label: 'Verified')
      else if (claimed)
        const _InfoPill(icon: Icons.storefront_outlined, label: 'Claimed'),
    ];

    return LocalLinkSurfaceCard(
      elevated: false,
      onTap: onTap,
      padding: const EdgeInsets.all(LocalLinkSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _BusinessAvatar(imageUrl: imageUrl, fallbackName: businessName),
          const SizedBox(width: LocalLinkSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  businessName,
                  style: LocalLinkTextStyles.cardTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: LocalLinkSpacing.xxs),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: AppColors.textMuted,
                        size: 16,
                      ),
                      const SizedBox(width: LocalLinkSpacing.xxs),
                      Expanded(
                        child: Text(
                          location,
                          style: LocalLinkTextStyles.metadata,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (trustItems.isNotEmpty) ...[
                  const SizedBox(height: LocalLinkSpacing.xs),
                  Wrap(
                    spacing: LocalLinkSpacing.xs,
                    runSpacing: LocalLinkSpacing.xs,
                    children: trustItems,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: LocalLinkSpacing.xs),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }

  static String _businessImageUrl(Map<String, dynamic> data) {
    final coverUrl = businessCoverImageUrl(data);
    if (coverUrl.isNotEmpty) return coverUrl;
    return safeText(data['logoUrl'], '');
  }
}

class _BusinessAvatar extends StatelessWidget {
  const _BusinessAvatar({required this.imageUrl, required this.fallbackName});

  final String imageUrl;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    final initial = fallbackName.trim().isEmpty
        ? 'L'
        : fallbackName.trim().characters.first.toUpperCase();

    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.serviceSoft,
        borderRadius: BorderRadius.circular(LocalLinkRadius.md),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
      ),
      alignment: Alignment.center,
      child: imageUrl.isEmpty
          ? Text(
              initial,
              style: const TextStyle(
                color: AppColors.serviceGreen,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(LocalLinkRadius.md),
              child: LocalLinkImage(
                imageUrl: imageUrl,
                aspectRatio: 1,
                fallbackIcon: Icons.storefront_outlined,
                accentColor: AppColors.serviceGreen,
                semanticLabel: fallbackName,
              ),
            ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    this.strong = false,
  });

  final IconData icon;
  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.sm,
        vertical: LocalLinkSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: strong ? AppColors.serviceGreen : AppColors.serviceSoft,
        borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: strong ? AppColors.inverseText : AppColors.serviceGreen,
          ),
          const SizedBox(width: LocalLinkSpacing.xxs),
          Text(
            label,
            style: LocalLinkTextStyles.status.copyWith(
              color: strong ? AppColors.inverseText : AppColors.serviceGreen,
            ),
          ),
        ],
      ),
    );
  }
}
