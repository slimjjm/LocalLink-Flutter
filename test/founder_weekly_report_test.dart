import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/screens/founder_dashboard_screen.dart';
import 'package:locallink_flutter/services/uk_activity_periods.dart';

void main() {
  const reportData = {
    'periodId': '2026-W37',
    'summary': {
      'activity.dailyActiveUsers': 87,
      'activity.weeklyActiveUsers': 37,
      'activity.monthlyActiveUsers': 23,
      'users.activeUsers': 42,
    },
    'week': {
      'users.newUsers': 9,
      'activity.weeklyActiveUsers': 52,
      'engagement.opportunitiesCreated': 7,
      'communityHelp.postsCreated': 3,
      'serviceRequests.created': 2,
      'bookings.started': 4,
      'bookings.confirmed': 2,
      'notifications.opened': 11,
      'community': {
        'topCategories': {'Beauty': 5, 'Pets': 2},
        'activeLocations': {'Lichfield': 4, 'Burntwood': 3},
      },
    },
  };

  test('active user counts are unique across rolling windows', () async {
    final buckets = {
      '2026-09-14': ['today-user', 'shared-user', 'shared-user'],
      '2026-09-13': ['wau-only-user', 'shared-user'],
      '2026-09-08': ['six-day-user'],
      '2026-09-07': ['mau-only-user'],
      '2026-08-16': ['mau-edge-user'],
      '2026-08-15': ['old-user'],
    };

    final counts = await activeUserCountsFromDailyBuckets(
      now: DateTime(2026, 9, 14, 15, 30),
      loadUsersForDay: (dayId) async => buckets[dayId] ?? const [],
    );

    expect(counts.dau, 2);
    expect(counts.wau, 4);
    expect(counts.mau, 6);
    expect(counts.dau <= counts.wau, isTrue);
    expect(counts.wau <= counts.mau, isTrue);
  });

  test(
    'active user day ids use deterministic UK current and previous days',
    () {
      expect(activeUserDayIds(DateTime.utc(2026, 9, 14, 22, 59), 3), [
        '2026-09-14',
        '2026-09-13',
        '2026-09-12',
      ]);
    },
  );

  test('UK activity buckets use GMT dates in winter', () {
    final ids = UkActivityPeriods.periodIds(
      now: DateTime.utc(2026, 1, 15, 23, 30),
    );

    expect(ids.day, '2026-01-15');
    expect(ids.month, '2026-01');
    expect(ids.week, '2026-W03');
  });

  test('UK activity buckets use BST dates in summer', () {
    final ids = UkActivityPeriods.periodIds(
      now: DateTime.utc(2026, 7, 1, 23, 30),
    );

    expect(ids.day, '2026-07-02');
    expect(ids.month, '2026-07');
    expect(ids.week, '2026-W27');
  });

  test('UK activity buckets handle the midnight boundary', () {
    expect(
      UkActivityPeriods.periodIds(now: DateTime.utc(2026, 7, 1, 22, 59)).day,
      '2026-07-01',
    );
    expect(
      UkActivityPeriods.periodIds(now: DateTime.utc(2026, 7, 1, 23)).day,
      '2026-07-02',
    );
  });

  test('UK activity buckets handle daylight-saving transitions', () {
    expect(
      UkActivityPeriods.ukLocalDateTime(DateTime.utc(2026, 3, 29, 0, 59)).hour,
      0,
    );
    expect(
      UkActivityPeriods.ukLocalDateTime(DateTime.utc(2026, 3, 29, 1)).hour,
      2,
    );
    expect(
      UkActivityPeriods.ukLocalDateTime(DateTime.utc(2026, 10, 25, 0, 59)).hour,
      1,
    );
    expect(
      UkActivityPeriods.ukLocalDateTime(DateTime.utc(2026, 10, 25, 1)).hour,
      1,
    );
  });

  testWidgets('dashboard activity fields map to active user counts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              FounderActivityMetricsSection(
                countsFuture: Future.value(
                  const ActiveUserCounts(dau: 2, wau: 4, mau: 6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Active today'), findsOneWidget);
    expect(find.text('Active last 7 days'), findsOneWidget);
    expect(find.text('Active last 30 days'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('90'), findsNothing);
    expect(find.text('38'), findsNothing);
    expect(find.text('23'), findsNothing);
  });

  testWidgets('refreshing activity metrics displays a fresh fetch result', (
    tester,
  ) async {
    var value = 1;
    late Future<ActiveUserCounts> countsFuture;

    Future<ActiveUserCounts> fetchCounts() async {
      final next = value;
      value += 1;
      return ActiveUserCounts(dau: next, wau: next + 10, mau: next + 20);
    }

    countsFuture = fetchCounts();

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              appBar: AppBar(
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () {
                      setState(() {
                        countsFuture = fetchCounts();
                      });
                    },
                  ),
                ],
              ),
              body: ListView(
                children: [
                  FounderActivityMetricsSection(countsFuture: countsFuture),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();
    await tester.pump();

    expect(find.text('2'), findsWidgets);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
  });

  test('growth chart points include zero days and readable date labels', () {
    final points = growthChartPointsFromDailyData(
      {
        '2026-09-12': {'users.newUsers': 4},
        '2026-09-14': {'users.newUsers': 2},
      },
      'users.newUsers',
      now: DateTime.utc(2026, 9, 14, 10),
    );

    expect(points.length, 14);
    expect(points.first.dayId, '2026-09-01');
    expect(points.last.dayId, '2026-09-14');
    expect(points.first.dateLabel, '1 Sep');
    expect(points.last.dateLabel, '14 Sep');
    expect(points.first.value, 0);
    expect(points[11].value, 4);
    expect(points.last.value, 2);
  });

  test('growth chart summary compares latest 7 days with previous 7 days', () {
    final points = List.generate(
      14,
      (index) => GrowthChartPoint(
        dayId: 'day-$index',
        dateLabel: 'Day $index',
        value: index < 7 ? 12 : 18,
        showAxisLabel: index.isEven,
      ),
    );

    final summary = growthChartSummary(points);

    expect(summary.previous7DaysTotal, 84);
    expect(summary.last7DaysTotal, 126);
    expect(summary.changePercent, 50);
    expect(summary.comparisonLabel, '↑ 50% vs previous 7 days');
  });

  testWidgets('growth chart shows empty state and zero clearly', (
    tester,
  ) async {
    final points = List.generate(
      14,
      (index) => GrowthChartPoint(
        dayId: '2026-09-${(index + 1).toString().padLeft(2, '0')}',
        dateLabel: '${index + 1} Sep',
        value: 0,
        showAxisLabel: index.isEven,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              GrowthChartCard.fromPoints(
                title: 'Comments',
                valueLabel: 'comments',
                points: points,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Comments'), findsOneWidget);
    expect(find.text('0 last 7 days'), findsOneWidget);
    expect(find.text('No comments in this period'), findsOneWidget);
  });

  testWidgets('growth chart shows tapped day value', (tester) async {
    final points = List.generate(
      14,
      (index) => GrowthChartPoint(
        dayId: '2026-09-${(index + 1).toString().padLeft(2, '0')}',
        dateLabel: '${index + 1} Sep',
        value: index == 11 ? 4 : 0,
        showAxisLabel: index.isEven,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              GrowthChartCard.fromPoints(
                title: 'New users',
                valueLabel: 'new users',
                points: points,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('12 Sep, 4'));
    await tester.pump();

    expect(find.text('12 Sep · 4 new users'), findsOneWidget);
  });

  testWidgets('weekly report item renders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FounderWeeklyReportCard(
            reportId: '2026-W37',
            data: reportData,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('2026-W37'), findsOneWidget);
    expect(
      find.text('52 active users · 9 new users · 7 new opportunities'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('weekly report is tappable and opens the selected week', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FounderWeeklyReportCard(
                reportId: '2026-W37',
                data: reportData,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WeeklyReportDetailScreen(
                        reportId: '2026-W37',
                        data: reportData,
                        activityCountsFuture: Future.value(
                          const ActiveUserCounts(dau: 2, wau: 10, mau: 17),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('2026-W37'));
    await tester.pumpAndSettle();

    expect(find.text('Weekly report'), findsOneWidget);
    expect(find.text('2026-W37'), findsOneWidget);
    expect(find.text('07/09/2026 - 13/09/2026'), findsOneWidget);
  });

  test('weekly report activity uses the report period end date', () {
    expect(activeUserDayIds(weekEndDateForTesting('2026-W37')!, 3), [
      '2026-09-13',
      '2026-09-12',
      '2026-09-11',
    ]);
  });

  testWidgets('weekly report detail displays captured weekly data', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyReportDetailScreen(
          reportId: '2026-W37',
          data: reportData,
          activityCountsFuture: Future.value(
            const ActiveUserCounts(dau: 2, wau: 10, mau: 17),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Active on final day'), findsOneWidget);
    expect(find.text('Active during report week'), findsOneWidget);
    expect(find.text('Active 30 days to week end'), findsOneWidget);
    expect(find.text('Current accounts then'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('87'), findsNothing);
    expect(find.text('37'), findsNothing);
    expect(find.text('23'), findsNothing);
    expect(find.text('New users/sign-ups'), findsOneWidget);
    expect(find.text('Opportunities/activities created'), findsOneWidget);
    expect(find.text('Community Help posts'), findsNothing);
    expect(find.text('Service requests'), findsNothing);
    expect(find.text('Bookings started'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Other captured analytics'),
      350,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Other captured analytics'), findsOneWidget);
    expect(find.text('Notifications / opened'), findsOneWidget);
    expect(find.text('Top categories'), findsOneWidget);
    expect(find.text('Opportunity locations'), findsOneWidget);
    expect(find.text('Beauty'), findsOneWidget);
    expect(find.text('Lichfield'), findsOneWidget);
  });

  testWidgets('missing optional weekly metrics do not crash detail screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeeklyReportDetailScreen(
          reportId: '2026-W38',
          data: {'periodId': '2026-W38', 'summary': {}, 'week': {}},
          activityCountsFuture: Future.value(ActiveUserCounts.empty),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Weekly report'), findsOneWidget);
    expect(
      find.text('No weekly metrics were captured for this report.'),
      findsOneWidget,
    );
  });
}
