class BusinessOpeningHours {
  const BusinessOpeningHours._();

  static const weekdays = [
    _DaySpec('monday', 'Monday'),
    _DaySpec('tuesday', 'Tuesday'),
    _DaySpec('wednesday', 'Wednesday'),
    _DaySpec('thursday', 'Thursday'),
    _DaySpec('friday', 'Friday'),
    _DaySpec('saturday', 'Saturday'),
    _DaySpec('sunday', 'Sunday'),
  ];

  static Map<String, dynamic> defaultStructured() {
    return {
      for (final day in weekdays)
        day.key: {
          'isOpen': !['saturday', 'sunday'].contains(day.key),
          'open': '09:00',
          'close': '17:00',
          'is24Hours': false,
        },
    };
  }

  static Map<String, dynamic>? fromData(Map<String, dynamic> data) {
    final value = data['openingHoursStructured'];
    if (value is Map) {
      return {
        for (final day in weekdays) day.key: _normaliseDay(value[day.key]),
      };
    }
    return null;
  }

  static Map<String, dynamic> _normaliseDay(Object? value) {
    if (value is Map) {
      return {
        'isOpen': value['isOpen'] == true,
        'open': _normaliseTime(value['open'], fallback: '09:00'),
        'close': _normaliseTime(value['close'], fallback: '17:00'),
        'is24Hours': value['is24Hours'] == true,
      };
    }

    return {
      'isOpen': false,
      'open': '09:00',
      'close': '17:00',
      'is24Hours': false,
    };
  }

  static String _normaliseTime(Object? value, {required String fallback}) {
    final text = value?.toString().trim() ?? '';
    return RegExp(r'^\d{2}:\d{2}$').hasMatch(text) ? text : fallback;
  }

  static String displayText(Map<String, dynamic> businessData) {
    final structured = fromData(businessData);
    if (structured != null) {
      return summary(structured);
    }
    return businessData['openingHours']?.toString().trim() ?? '';
  }

  static String summary(Map<String, dynamic> structured) {
    final groups = <String, List<String>>{};

    for (final day in weekdays) {
      final data = _normaliseDay(structured[day.key]);
      final label = data['isOpen'] == true
          ? data['is24Hours'] == true
                ? 'Open 24 hours'
                : '${data['open']} - ${data['close']}'
          : 'Closed';
      groups.putIfAbsent(label, () => []).add(day.label);
    }

    return groups.entries
        .map((entry) => '${_dayRange(entry.value)}: ${entry.key}')
        .join('\n');
  }

  static String _dayRange(List<String> days) {
    if (days.length == 1) return days.first;

    final indexes = days
        .map((label) => weekdays.indexWhere((day) => day.label == label))
        .toList();
    var sequential = true;
    for (var i = 1; i < indexes.length; i++) {
      if (indexes[i] != indexes[i - 1] + 1) {
        sequential = false;
        break;
      }
    }

    if (sequential) return '${days.first} - ${days.last}';
    return days.join(', ');
  }
}

class _DaySpec {
  const _DaySpec(this.key, this.label);

  final String key;
  final String label;
}
