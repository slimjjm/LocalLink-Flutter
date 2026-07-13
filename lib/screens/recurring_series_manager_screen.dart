import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:locallink_flutter/models/occurrence_status.dart';

class RecurringSeriesManagerScreen extends StatefulWidget {
  final String opportunityId;
  final String seriesId;

  const RecurringSeriesManagerScreen({
    super.key,
    required this.opportunityId,
    required this.seriesId,
  });

  @override
  State<RecurringSeriesManagerScreen> createState() =>
      _RecurringSeriesManagerScreenState();
}

class _RecurringSeriesManagerScreenState
    extends State<RecurringSeriesManagerScreen> {
  CollectionReference<Map<String, dynamic>> get _opportunities =>
      FirebaseFirestore.instance.collection('opportunities');

  Future<void> _moveOccurrence({
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    final timestamp = data['eventDate'];

    if (timestamp is! Timestamp) {
      return;
    }

    final currentDate = timestamp.toDate();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime.now().subtract(
        const Duration(days: 1),
      ),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) {
      return;
    }

    final newDate = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      currentDate.hour,
      currentDate.minute,
    );

    await _opportunities.doc(docId).update({
      'originalEventDate': data['originalEventDate'] ?? data['eventDate'],
      'eventDate': Timestamp.fromDate(newDate),
      'occurrenceStatus': OccurrenceStatus.moved,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _skipOccurrence({
    required String docId,
  }) async {
    final confirmed = await _confirmAction(
      title: 'Skip occurrence?',
      message:
          'This occurrence will be skipped but kept in the series history.',
      confirmText: 'Skip',
    );

    if (!confirmed) {
      return;
    }

    await _opportunities.doc(docId).update({
      'occurrenceStatus': OccurrenceStatus.skipped,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _cancelOccurrence({
    required String docId,
  }) async {
    final confirmed = await _confirmAction(
      title: 'Cancel occurrence?',
      message:
          'This occurrence will remain in the series but will be marked as cancelled.',
      confirmText: 'Cancel occurrence',
    );

    if (!confirmed) {
      return;
    }

    await _opportunities.doc(docId).update({
      'occurrenceStatus': OccurrenceStatus.cancelled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _reinstateOccurrence({
    required String docId,
  }) async {
    await _opportunities.doc(docId).update({
      'occurrenceStatus': OccurrenceStatus.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
            },
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            child: Text(confirmText),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _handleMenuAction({
    required String value,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    if (value == 'edit') {
      _returnSelection(
        editType: 'occurrence',
        opportunityId: docId,
      );
      return;
    }

    if (value == 'move') {
      await _moveOccurrence(
        docId: docId,
        data: data,
      );
      return;
    }

    if (value == 'skip') {
      await _skipOccurrence(
        docId: docId,
      );
      return;
    }

    if (value == 'cancel') {
      await _cancelOccurrence(
        docId: docId,
      );
      return;
    }

    if (value == 'reinstate') {
      await _reinstateOccurrence(
        docId: docId,
      );
      return;
    }
  }

  void _returnSelection({
    required String editType,
    required String opportunityId,
  }) {
    Navigator.pop(
      context,
      {
        'editType': editType,
        'opportunityId': opportunityId,
      },
    );
  }

  String _statusFromData(Map<String, dynamic> data) {
    final occurrenceStatus = data['occurrenceStatus'];
    final seriesStatus = data['seriesStatus'];

    if (occurrenceStatus is String && occurrenceStatus.isNotEmpty) {
      return occurrenceStatus;
    }

    if (seriesStatus is String && seriesStatus.isNotEmpty) {
      return seriesStatus;
    }

    return OccurrenceStatus.active;
  }

  String _dateTitle(DateTime? date) {
    if (date == null) {
      return 'Unknown date';
    }

    return '${date.day}/${date.month}/${date.year}';
  }

  String _timeTitle(DateTime? date) {
    if (date == null) {
      return 'Unknown time';
    }

    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  bool _canReinstate(String status) {
    return status == OccurrenceStatus.skipped ||
        status == OccurrenceStatus.cancelled;
  }

  bool _isInactive(String status) {
    return status == OccurrenceStatus.skipped ||
        status == OccurrenceStatus.cancelled;
  }

  Color _statusColor(String status) {
    switch (status) {
      case OccurrenceStatus.active:
        return Colors.blue;

      case OccurrenceStatus.moved:
        return Colors.orange;

      case OccurrenceStatus.skipped:
        return Colors.amber.shade700;

      case OccurrenceStatus.cancelled:
        return Colors.red;

      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case OccurrenceStatus.active:
        return Icons.radio_button_checked;

      case OccurrenceStatus.moved:
        return Icons.swap_horiz;

      case OccurrenceStatus.skipped:
        return Icons.fast_forward;

      case OccurrenceStatus.cancelled:
        return Icons.cancel;

      default:
        return Icons.help_outline;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case OccurrenceStatus.active:
        return 'Active';

      case OccurrenceStatus.moved:
        return 'Moved';

      case OccurrenceStatus.skipped:
        return 'Skipped';

      case OccurrenceStatus.cancelled:
        return 'Cancelled';

      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring Series'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _opportunities
            .where('seriesId', isEqualTo: widget.seriesId)
            .orderBy('eventDate')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Something went wrong loading this series.',
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text('No occurrences found.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length + 2,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _SeriesHeader(
                  occurrenceCount: docs.length,
                );
              }

              if (index == docs.length + 1) {
                return _EntireSeriesCard(
                  onTap: () {
                    _returnSelection(
                      editType: 'series',
                      opportunityId: widget.opportunityId,
                    );
                  },
                );
              }

              final doc = docs[index - 1];
              final data = doc.data();

              final eventDate =
                  (data['eventDate'] as Timestamp?)?.toDate();

              final status = _statusFromData(data);
              final isCurrent = doc.id == widget.opportunityId;
              final isInactive = _isInactive(status);
              final canReinstate = _canReinstate(status);

              return Card(
                elevation: isCurrent ? 2 : 0,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: isCurrent
                        ? Colors.green
                        : Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(
                      isCurrent ? Icons.check : Icons.event,
                      color: isCurrent
                          ? Colors.white
                          : Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  title: Text(
                    _dateTitle(eventDate),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration:
                          isInactive ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_timeTitle(eventDate)),
                        const SizedBox(height: 8),
                        _StatusChip(
                          label: _statusLabel(status),
                          icon: _statusIcon(status),
                          color: _statusColor(status),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Current occurrence',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      await _handleMenuAction(
                        value: value,
                        docId: doc.id,
                        data: data,
                      );
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit occurrence'),
                      ),
                      const PopupMenuItem(
                        value: 'move',
                        child: Text('Move occurrence'),
                      ),
                      if (!canReinstate)
                        const PopupMenuItem(
                          value: 'skip',
                          child: Text('Skip occurrence'),
                        ),
                      if (!canReinstate)
                        const PopupMenuItem(
                          value: 'cancel',
                          child: Text('Cancel occurrence'),
                        ),
                      if (canReinstate)
                        const PopupMenuItem(
                          value: 'reinstate',
                          child: Text('Reinstate occurrence'),
                        ),
                    ],
                  ),
                  onTap: () {
                    _returnSelection(
                      editType: 'occurrence',
                      opportunityId: doc.id,
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SeriesHeader extends StatelessWidget {
  final int occurrenceCount;

  const _SeriesHeader({
    required this.occurrenceCount,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.event_repeat,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$occurrenceCount occurrences in this series',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntireSeriesCard extends StatelessWidget {
  final VoidCallback onTap;

  const _EntireSeriesCard({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Icon(
            Icons.edit_calendar,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
        title: const Text(
          'Entire Series',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: const Text(
          'Edit the recurring template',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}