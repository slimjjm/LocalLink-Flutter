class UkActivityPeriodIds {
  final String day;
  final String week;
  final String month;

  const UkActivityPeriodIds({
    required this.day,
    required this.week,
    required this.month,
  });
}

class UkActivityPeriods {
  const UkActivityPeriods._();

  static UkActivityPeriodIds periodIds({DateTime? now}) {
    final ukDate = ukLocalDate(now ?? DateTime.now());

    return UkActivityPeriodIds(
      day: dayId(ukDate),
      week: weekId(ukDate),
      month: monthId(ukDate),
    );
  }

  static List<String> rollingDayIds({
    required DateTime now,
    required int days,
  }) {
    final today = ukLocalDate(now);

    return List.generate(days, (index) {
      final date = today.subtract(Duration(days: index));
      return dayId(date);
    });
  }

  static DateTime ukLocalDate(DateTime instant) {
    final ukDateTime = ukLocalDateTime(instant);
    return DateTime(ukDateTime.year, ukDateTime.month, ukDateTime.day);
  }

  static DateTime ukLocalDateTime(DateTime instant) {
    final utc = instant.toUtc();
    return utc.add(Duration(hours: _isBritishSummerTime(utc) ? 1 : 0));
  }

  static String dayId(DateTime ukDate) {
    final month = ukDate.month.toString().padLeft(2, '0');
    final day = ukDate.day.toString().padLeft(2, '0');
    return '${ukDate.year}-$month-$day';
  }

  static String monthId(DateTime ukDate) {
    final month = ukDate.month.toString().padLeft(2, '0');
    return '${ukDate.year}-$month';
  }

  static String weekId(DateTime ukDate) {
    final thursday = ukDate.add(
      Duration(days: DateTime.thursday - ukDate.weekday),
    );
    final weekYear = thursday.year;
    final firstThursday = DateTime(weekYear, 1, 4);
    final firstWeekStart = firstThursday.subtract(
      Duration(days: firstThursday.weekday - DateTime.monday),
    );
    final week = thursday.difference(firstWeekStart).inDays ~/ 7 + 1;

    return '$weekYear-W${week.toString().padLeft(2, '0')}';
  }

  static bool _isBritishSummerTime(DateTime utc) {
    final start = _lastSundayAtOneUtc(utc.year, DateTime.march);
    final end = _lastSundayAtOneUtc(utc.year, DateTime.october);
    return !utc.isBefore(start) && utc.isBefore(end);
  }

  static DateTime _lastSundayAtOneUtc(int year, int month) {
    final lastDay = DateTime.utc(year, month + 1, 0, 1);
    final daysSinceSunday = lastDay.weekday % DateTime.sunday;
    return lastDay.subtract(Duration(days: daysSinceSunday));
  }
}
