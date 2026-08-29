import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/helpers.dart';
import '../widgets/booking_status_chip.dart';
import 'business_booking_detail_screen.dart';
import 'post_availability_screen.dart';

class BusinessCalendarScreen extends StatefulWidget {
  final String businessId;

  const BusinessCalendarScreen({super.key, required this.businessId});

  @override
  State<BusinessCalendarScreen> createState() => _BusinessCalendarScreenState();
}

class _BusinessCalendarScreenState extends State<BusinessCalendarScreen> {
  DateTime selectedDate = DateTime.now();
  bool isLoading = true;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> bookings = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> availabilityPosts = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> blockedTime = [];

  @override
  void initState() {
    super.initState();
    loadDiary();
  }

  Future<void> loadDiary() async {
    setState(() => isLoading = true);

    try {
      final startOfDay = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final firestore = FirebaseFirestore.instance;

      final bookingSnapshot = await firestore
          .collection('bookings')
          .where('businessId', isEqualTo: widget.businessId)
          .where(
            'startDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('startDate', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('startDate')
          .get();

      final availabilitySnapshot = await firestore
          .collection('availabilityPosts')
          .where('businessId', isEqualTo: widget.businessId)
          .where('isActive', isEqualTo: true)
          .where(
            'availabilityAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('availabilityAt', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('availabilityAt')
          .get();

      final staffSnapshot = await firestore
          .collection('businesses')
          .doc(widget.businessId)
          .collection('staff')
          .where('isActive', isEqualTo: true)
          .get();

      final blocks = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      for (final staffDoc in staffSnapshot.docs) {
        final blockSnapshot = await firestore
            .collection('businesses')
            .doc(widget.businessId)
            .collection('staff')
            .doc(staffDoc.id)
            .collection('dayBlocks')
            .where('startDate', isLessThan: Timestamp.fromDate(endOfDay))
            .where(
              'endDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
            )
            .get();

        blocks.addAll(blockSnapshot.docs);
      }

      if (!mounted) return;

      setState(() {
        bookings = bookingSnapshot.docs;
        availabilityPosts = availabilitySnapshot.docs;
        blockedTime = blocks;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked == null || !mounted) return;

    setState(() => selectedDate = picked);
    await loadDiary();
  }

  String formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String formatTime(Timestamp? timestamp) {
    if (timestamp == null) return 'Time not set';

    final date = timestamp.toDate();
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  bool get hasDiaryItems =>
      bookings.isNotEmpty ||
      availabilityPosts.isNotEmpty ||
      blockedTime.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Diary'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Add availability',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PostAvailabilityScreen(businessId: widget.businessId),
                ),
              );
            },
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: 'Choose date',
            onPressed: pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.serviceGreen,
        onRefresh: loadDiary,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _DiaryHeader(
              date: formatDate(selectedDate),
              bookingCount: bookings.length,
              pendingCount: bookings
                  .where(
                    (doc) =>
                        doc.data()['status'] == 'pending_business_confirmation',
                  )
                  .length,
              availabilityCount: availabilityPosts.length,
            ),
            const SizedBox(height: 18),
            if (isLoading)
              const _DiaryLoading()
            else if (!hasDiaryItems)
              _DiaryEmpty(
                onPostAvailability: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PostAvailabilityScreen(businessId: widget.businessId),
                    ),
                  );
                },
              )
            else ...[
              if (bookings.isNotEmpty) ...[
                const _DiarySectionTitle(
                  title: 'Bookings',
                  subtitle: 'Confirmed and pending customer appointments.',
                ),
                const SizedBox(height: 10),
                ...bookings.map(
                  (doc) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _BookingDiaryCard(
                      bookingId: doc.id,
                      booking: doc.data(),
                      formatTime: formatTime,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (availabilityPosts.isNotEmpty) ...[
                const _DiarySectionTitle(
                  title: 'Unfilled availability',
                  subtitle: 'Live openings customers can still book.',
                ),
                const SizedBox(height: 10),
                ...availabilityPosts.map(
                  (doc) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AvailabilityDiaryCard(
                      postId: doc.id,
                      post: doc.data(),
                      formatTime: formatTime,
                      onChanged: loadDiary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (blockedTime.isNotEmpty) ...[
                const _DiarySectionTitle(
                  title: 'Blocked time',
                  subtitle: 'Time currently unavailable for bookings.',
                ),
                const SizedBox(height: 10),
                ...blockedTime.map(
                  (doc) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _BlockedTimeCard(block: doc.data()),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DiaryHeader extends StatelessWidget {
  final String date;
  final int bookingCount;
  final int pendingCount;
  final int availabilityCount;

  const _DiaryHeader({
    required this.date,
    required this.bookingCount,
    required this.pendingCount,
    required this.availabilityCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Operational diary',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            date,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _DiaryMetric(label: 'Bookings', value: bookingCount),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DiaryMetric(label: 'Pending', value: pendingCount),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DiaryMetric(
                  label: 'Open slots',
                  value: availabilityCount,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiaryMetric extends StatelessWidget {
  final String label;
  final int value;

  const _DiaryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.toString(),
            style: const TextStyle(
              color: AppColors.charcoal,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiarySectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _DiarySectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.charcoal,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.textMuted, height: 1.3),
        ),
      ],
    );
  }
}

class _BookingDiaryCard extends StatelessWidget {
  final String bookingId;
  final Map<String, dynamic> booking;
  final String Function(Timestamp?) formatTime;

  const _BookingDiaryCard({
    required this.bookingId,
    required this.booking,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final serviceName = safeText(booking['serviceName'], 'Service');
    final customerName = safeText(booking['customerName'], 'Customer');
    final startDate = booking['startDate'] as Timestamp?;
    final endDate = booking['endDate'] as Timestamp?;
    final status = safeText(booking['status'], 'unknown');
    final price = formatPrice(booking['price']);

    return _DiaryCard(
      icon: Icons.event_available_outlined,
      color: AppColors.primary,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BusinessBookingDetailScreen(bookingId: bookingId),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  serviceName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              BookingStatusChip(status: status, compact: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$customerName • ${formatTime(startDate)} - ${formatTime(endDate)}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            price,
            style: const TextStyle(
              color: AppColors.charcoal,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityDiaryCard extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> post;
  final String Function(Timestamp?) formatTime;
  final Future<void> Function() onChanged;

  const _AvailabilityDiaryCard({
    required this.postId,
    required this.post,
    required this.formatTime,
    required this.onChanged,
  });

  Future<void> _removeAvailability(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove availability?'),
          content: const Text(
            'This removes the available time from LocalLink discovery. Existing bookings are not changed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('availabilityPosts')
          .doc(postId)
          .set({
            'isActive': false,
            'archived': true,
            'archivedReason': 'removed_by_business',
            'updatedAt': FieldValue.serverTimestamp(),
            'archivedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await onChanged();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('We could not remove that time.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final serviceName = safeText(post['serviceName'], 'Service');
    final start = post['startTime'] as Timestamp?;
    final end = post['endTime'] as Timestamp?;
    final type = safeText(
      post['type'] ?? post['availabilityType'],
      'available',
    );
    final capacity = post['remainingCapacity'] ?? post['capacity'];

    return _DiaryCard(
      icon: Icons.campaign_outlined,
      color: AppColors.serviceGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            serviceName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.charcoal,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${formatTime(start)} - ${formatTime(end)} • ${type.replaceAll('_', ' ')}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (capacity != null) ...[
            const SizedBox(height: 4),
            Text(
              '$capacity space${capacity == 1 ? '' : 's'} still available',
              style: const TextStyle(
                color: AppColors.serviceGreen,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _removeAvailability(context),
              icon: const Icon(Icons.remove_circle_outline),
              label: const Text('Remove'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockedTimeCard extends StatelessWidget {
  final Map<String, dynamic> block;

  const _BlockedTimeCard({required this.block});

  @override
  Widget build(BuildContext context) {
    final type = safeText(block['type'], 'blocked');
    final reason = safeText(block['reason'], '');

    return _DiaryCard(
      icon: Icons.block_outlined,
      color: AppColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            type.replaceAll('_', ' '),
            style: const TextStyle(
              color: AppColors.charcoal,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Widget child;
  final VoidCallback? onTap;

  const _DiaryCard({
    required this.icon,
    required this.color,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiaryEmpty extends StatelessWidget {
  final VoidCallback onPostAvailability;

  const _DiaryEmpty({required this.onPostAvailability});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 54),
      child: Column(
        children: [
          const Icon(
            Icons.event_note_outlined,
            size: 54,
            color: AppColors.serviceGreen,
          ),
          const SizedBox(height: 14),
          const Text(
            'Nothing scheduled for this day',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bookings, pending requests, blocked time and unfilled availability will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, height: 1.35),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onPostAvailability,
            icon: const Icon(Icons.campaign_outlined),
            label: const Text('Post availability'),
          ),
        ],
      ),
    );
  }
}

class _DiaryLoading extends StatelessWidget {
  const _DiaryLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 54),
      child: Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: 14),
          Text(
            'Checking your diary...',
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
