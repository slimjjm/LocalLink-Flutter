import 'package:flutter/material.dart';

import '../models/business_opening_hours.dart';
import '../theme/app_colors.dart';

class BusinessOpeningHoursEditor extends StatefulWidget {
  const BusinessOpeningHoursEditor({
    super.key,
    required this.initialHours,
    required this.onChanged,
  });

  final Map<String, dynamic> initialHours;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<BusinessOpeningHoursEditor> createState() =>
      _BusinessOpeningHoursEditorState();
}

class _BusinessOpeningHoursEditorState
    extends State<BusinessOpeningHoursEditor> {
  late Map<String, dynamic> _hours;

  @override
  void initState() {
    super.initState();
    _hours = {
      ...BusinessOpeningHours.defaultStructured(),
      ...widget.initialHours,
    };
  }

  void _update(String day, Map<String, dynamic> value) {
    setState(() {
      _hours = {..._hours, day: value};
    });
    widget.onChanged(_hours);
  }

  void _copyMondayToWeekdays() {
    final monday = Map<String, dynamic>.from(_hours['monday'] as Map);
    setState(() {
      for (final day in const ['tuesday', 'wednesday', 'thursday', 'friday']) {
        _hours[day] = {...monday};
      }
    });
    widget.onChanged(_hours);
  }

  Future<void> _pickTime(String day, String field) async {
    final current = _parseTime((_hours[day] as Map)[field]);
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null) return;
    _update(day, {
      ...Map<String, dynamic>.from(_hours[day] as Map),
      field:
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    });
  }

  TimeOfDay _parseTime(Object? value) {
    final parts = value?.toString().split(':') ?? const [];
    if (parts.length != 2) return const TimeOfDay(hour: 9, minute: 0);
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Opening hours',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            TextButton(
              onPressed: _copyMondayToWeekdays,
              child: const Text('Copy Monday'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...BusinessOpeningHours.weekdays.map((day) {
          final data = Map<String, dynamic>.from(_hours[day.key] as Map);
          final isOpen = data['isOpen'] == true;
          final is24Hours = data['is24Hours'] == true;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          day.label,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Switch.adaptive(
                        value: isOpen,
                        onChanged: (value) =>
                            _update(day.key, {...data, 'isOpen': value}),
                      ),
                    ],
                  ),
                  if (isOpen) ...[
                    Row(
                      children: [
                        FilterChip(
                          label: const Text('24 hours'),
                          selected: is24Hours,
                          onSelected: (value) =>
                              _update(day.key, {...data, 'is24Hours': value}),
                        ),
                        if (!is24Hours) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _pickTime(day.key, 'open'),
                              child: Text(data['open']?.toString() ?? '09:00'),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Text('-'),
                          ),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _pickTime(day.key, 'close'),
                              child: Text(data['close']?.toString() ?? '17:00'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
