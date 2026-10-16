import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/admin_access_service.dart';
import '../services/uk_activity_periods.dart';
import '../theme/app_colors.dart';
import 'admin_reports_screen.dart';

class FounderDashboardScreen extends StatefulWidget {
  const FounderDashboardScreen({super.key});

  @override
  State<FounderDashboardScreen> createState() => _FounderDashboardScreenState();

  static Future<void> _openModeration(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminReportsScreen()),
    );
  }

  static int _number(Map<String, dynamic> data, String path) {
    if (data[path] is num) {
      return (data[path] as num).toInt();
    }

    dynamic value = data;

    for (final part in path.split('.')) {
      if (value is! Map<String, dynamic>) {
        return 0;
      }

      value = value[part];
    }

    if (value is num) {
      return value.toInt();
    }

    return 0;
  }

  static Future<int> _periodMetric(String period, String path) async {
    final doc = await FirebaseFirestore.instance
        .collection('analytics')
        .doc('summary')
        .collection(period)
        .doc(_periodId(period))
        .get();

    return _number(doc.data() ?? {}, path);
  }

  static String _periodId(String period) {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');

    if (period == 'month') {
      return '${now.year}-$month';
    }

    final firstDay = DateTime(now.year, 1, 1);
    final startOfToday = DateTime(now.year, now.month, now.day);
    final pastDays = startOfToday.difference(firstDay).inDays;
    final week = ((pastDays + firstDay.weekday) / 7).ceil().toString().padLeft(
      2,
      '0',
    );

    if (period == 'week') {
      return '${now.year}-W$week';
    }

    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }
}

class _FounderDashboardScreenState extends State<FounderDashboardScreen>
    with WidgetsBindingObserver {
  late Future<bool> _adminAccessFuture;
  late Future<ActiveUserCounts> _activityCountsFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _adminAccessFuture = AdminAccessService().isCurrentUserAdmin();
    _activityCountsFuture = FounderActiveUserAnalytics().fetchCounts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshFounderData();
    }
  }

  Future<void> _refreshFounderData() async {
    final activityFuture = FounderActiveUserAnalytics().fetchCounts();

    setState(() {
      _activityCountsFuture = activityFuture;
    });

    try {
      await activityFuture;
    } catch (_) {
      // The FutureBuilder keeps the current fallback display; the refresh
      // gesture should still complete cleanly if Firestore is temporarily down.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _adminAccessFuture,
      builder: (context, accessSnapshot) {
        if (!accessSnapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (accessSnapshot.data != true) {
          return const Scaffold(
            body: Center(child: Text('You do not have access to this area.')),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Founder Dashboard'),
            backgroundColor: AppColors.background,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refreshFounderData,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refreshFounderData,
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('analytics')
                  .doc('summary')
                  .snapshots(),
              builder: (context, snapshot) {
                final data =
                    snapshot.data?.data() as Map<String, dynamic>? ?? {};

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    const _DashboardIntro(),
                    const SizedBox(height: 16),
                    _MetricSection(
                      title: 'Registered users',
                      metrics: [
                        _Metric(
                          'Total ever',
                          FounderDashboardScreen._number(
                            data,
                            'users.totalUsersCreated',
                          ),
                        ),
                        _Metric(
                          'Current accounts',
                          FounderDashboardScreen._number(
                            data,
                            'users.activeUsers',
                          ),
                        ),
                        _Metric.future(
                          'New this week',
                          FounderDashboardScreen._periodMetric(
                            'week',
                            'users.newUsers',
                          ),
                        ),
                        _Metric.future(
                          'New this month',
                          FounderDashboardScreen._periodMetric(
                            'month',
                            'users.newUsers',
                          ),
                        ),
                      ],
                    ),
                    FounderActivityMetricsSection(
                      countsFuture: _activityCountsFuture,
                    ),
                    _MetricSection(
                      title: 'Account details',
                      metrics: [
                        _Metric.future(
                          'New today',
                          FounderDashboardScreen._periodMetric(
                            'day',
                            'users.newUsers',
                          ),
                        ),
                        _Metric(
                          'Deleted',
                          FounderDashboardScreen._number(
                            data,
                            'users.deletedUsers',
                          ),
                        ),
                      ],
                    ),
                    _MetricSection(
                      title: 'Engagement',
                      metrics: [
                        _Metric.future(
                          'Opportunities today',
                          FounderDashboardScreen._periodMetric(
                            'day',
                            'engagement.opportunitiesCreated',
                          ),
                        ),
                        _Metric.future(
                          'Opportunities week',
                          FounderDashboardScreen._periodMetric(
                            'week',
                            'engagement.opportunitiesCreated',
                          ),
                        ),
                        _Metric.future(
                          'Opportunities month',
                          FounderDashboardScreen._periodMetric(
                            'month',
                            'engagement.opportunitiesCreated',
                          ),
                        ),
                        _Metric.future(
                          'Comments today',
                          FounderDashboardScreen._periodMetric(
                            'day',
                            'engagement.comments',
                          ),
                        ),
                        _Metric.future(
                          'Comments week',
                          FounderDashboardScreen._periodMetric(
                            'week',
                            'engagement.comments',
                          ),
                        ),
                        _Metric.future(
                          'Comments month',
                          FounderDashboardScreen._periodMetric(
                            'month',
                            'engagement.comments',
                          ),
                        ),
                        _Metric(
                          'Reviews',
                          FounderDashboardScreen._number(
                            data,
                            'engagement.reviews',
                          ),
                        ),
                        _Metric(
                          'Saves',
                          FounderDashboardScreen._number(
                            data,
                            'engagement.saves',
                          ),
                        ),
                        _Metric(
                          'Shares',
                          FounderDashboardScreen._number(
                            data,
                            'engagement.shares',
                          ),
                        ),
                        _Metric(
                          'Reports',
                          FounderDashboardScreen._number(
                            data,
                            'moderation.reportsSubmitted',
                          ),
                        ),
                      ],
                    ),
                    _MetricSection(
                      title: 'Moderation',
                      metrics: [
                        _Metric(
                          'Pending reports',
                          FounderDashboardScreen._number(
                            data,
                            'moderation.pendingReports',
                          ),
                          onTap: () => _openModeration(context),
                        ),
                        _Metric(
                          'Resolved reports',
                          FounderDashboardScreen._number(
                            data,
                            'moderation.reportsResolved',
                          ),
                          onTap: () => _openModeration(context),
                        ),
                        _Metric(
                          'Users reported',
                          FounderDashboardScreen._number(
                            data,
                            'moderation.reportTypes.profile',
                          ),
                          onTap: () => _openModeration(context),
                        ),
                        _Metric(
                          'Opportunities reported',
                          FounderDashboardScreen._number(
                            data,
                            'moderation.reportTypes.opportunity',
                          ),
                          onTap: () => _openModeration(context),
                        ),
                        _Metric(
                          'Comments reported',
                          FounderDashboardScreen._number(
                            data,
                            'moderation.reportTypes.comment',
                          ),
                          onTap: () => _openModeration(context),
                        ),
                      ],
                    ),
                    _TopLists(data: data),
                    const SizedBox(height: 16),
                    _ChartsPanel(),
                    const SizedBox(height: 16),
                    _ReportsHistoryPanel(),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openModeration(BuildContext context) async {
    await FounderDashboardScreen._openModeration(context);
    if (mounted) {
      await _refreshFounderData();
    }
  }
}

class _DashboardIntro extends StatelessWidget {
  const _DashboardIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LocalLink health',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'Precomputed founder analytics for growth, engagement and safety.',
            style: TextStyle(
              color: Colors.white70,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricSection extends StatelessWidget {
  final String title;
  final List<_Metric> metrics;

  const _MetricSection({required this.title, required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 9),
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: metrics.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
            ),
            itemBuilder: (context, index) {
              return _MetricCard(metric: metrics[index]);
            },
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final _Metric metric;

  const _MetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    if (metric.futureValue != null) {
      return FutureBuilder<int>(
        future: metric.futureValue,
        builder: (context, snapshot) {
          return _MetricCardBody(
            label: metric.label,
            value: snapshot.data ?? 0,
            onTap: metric.onTap,
          );
        },
      );
    }

    return _MetricCardBody(
      label: metric.label,
      value: metric.value,
      onTap: metric.onTap,
    );
  }
}

class _MetricCardBody extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback? onTap;

  const _MetricCardBody({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.72)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textMuted,
                      size: 18,
                    ),
                ],
              ),
              Text(
                value.toString(),
                style: const TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 28,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric {
  final String label;
  final int value;
  final Future<int>? futureValue;
  final VoidCallback? onTap;

  const _Metric(this.label, this.value, {this.onTap}) : futureValue = null;

  const _Metric.future(this.label, this.futureValue) : value = 0, onTap = null;
}

class FounderActivityMetricsSection extends StatelessWidget {
  final Future<ActiveUserCounts> countsFuture;
  final String title;

  const FounderActivityMetricsSection({
    super.key,
    required this.countsFuture,
    this.title = 'Actual usage',
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ActiveUserCounts>(
      future: countsFuture,
      builder: (context, snapshot) {
        final counts = snapshot.data ?? ActiveUserCounts.empty;

        return _MetricSection(
          title: title,
          metrics: [
            _Metric('Active today', counts.dau),
            _Metric('Active last 7 days', counts.wau),
            _Metric('Active last 30 days', counts.mau),
          ],
        );
      },
    );
  }
}

class ActiveUserCounts {
  final int dau;
  final int wau;
  final int mau;

  static const empty = ActiveUserCounts(dau: 0, wau: 0, mau: 0);

  const ActiveUserCounts({
    required this.dau,
    required this.wau,
    required this.mau,
  });
}

typedef ActiveUserBucketLoader =
    Future<Iterable<String>> Function(String dayId);

class FounderActiveUserAnalytics {
  final FirebaseFirestore firestore;

  FounderActiveUserAnalytics({FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  Future<ActiveUserCounts> fetchCounts({DateTime? now}) {
    return activeUserCountsFromDailyBuckets(
      now: now ?? DateTime.now(),
      loadUsersForDay: (dayId) async {
        final snapshot = await firestore
            .collection('activityDaily')
            .doc(dayId)
            .collection('users')
            .get();

        return snapshot.docs.map((doc) => doc.id);
      },
    );
  }
}

Future<ActiveUserCounts> activeUserCountsFromDailyBuckets({
  required DateTime now,
  required ActiveUserBucketLoader loadUsersForDay,
}) async {
  final dayIds = activeUserDayIds(now, 30);
  final bucketUsers = await Future.wait(dayIds.map(loadUsersForDay));
  final dauUsers = <String>{};
  final wauUsers = <String>{};
  final mauUsers = <String>{};

  for (var index = 0; index < bucketUsers.length; index += 1) {
    final users = bucketUsers[index].where((uid) => uid.trim().isNotEmpty);

    if (index == 0) {
      dauUsers.addAll(users);
    }

    if (index < 7) {
      wauUsers.addAll(users);
    }

    mauUsers.addAll(users);
  }

  return ActiveUserCounts(
    dau: dauUsers.length,
    wau: wauUsers.length,
    mau: mauUsers.length,
  );
}

List<String> activeUserDayIds(DateTime now, int days) {
  return UkActivityPeriods.rollingDayIds(now: now, days: days);
}

class _TopLists extends StatelessWidget {
  final Map<String, dynamic> data;

  const _TopLists({required this.data});

  @override
  Widget build(BuildContext context) {
    final categories = _sortedMap(data, 'community.topCategories');
    final locations = _sortedMap(data, 'community.activeLocations');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _TopListCard(title: 'Top categories', items: categories),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _TopListCard(
              title: 'Opportunity locations',
              items: locations,
            ),
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, int>> _sortedMap(
    Map<String, dynamic> data,
    String path,
  ) {
    if (data[path] is Map<String, dynamic>) {
      return _sortedEntries(data[path] as Map<String, dynamic>);
    }

    final prefixEntries = <String, int>{};
    final prefix = '$path.';

    for (final entry in data.entries) {
      if (entry.key.startsWith(prefix) && entry.value is num) {
        prefixEntries[entry.key.substring(prefix.length)] = (entry.value as num)
            .toInt();
      }
    }

    if (prefixEntries.isNotEmpty) {
      return _sortedEntries(prefixEntries);
    }

    dynamic value = data;

    for (final part in path.split('.')) {
      if (value is! Map<String, dynamic>) {
        return [];
      }

      value = value[part];
    }

    if (value is! Map<String, dynamic>) {
      return [];
    }

    return _sortedEntries(value);
  }

  List<MapEntry<String, int>> _sortedEntries(Map<String, dynamic> value) {
    final entries = value.entries
        .where((entry) => entry.value is num)
        .map((entry) => MapEntry(entry.key, (entry.value as num).toInt()))
        .toList();

    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(5).toList();
  }
}

class _TopListCard extends StatelessWidget {
  final String title;
  final List<MapEntry<String, int>> items;

  const _TopListCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.charcoal,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text(
              'No data yet',
              style: TextStyle(color: AppColors.textMuted),
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      item.value.toString(),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _ChartsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('analytics')
          .doc('summary')
          .collection('day')
          .orderBy('periodId', descending: true)
          .limit(30)
          .get(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 9),
              child: Text(
                'Growth',
                style: TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            GrowthChartCard(
              title: 'New users',
              valueLabel: 'new users',
              docs: docs,
              path: 'users.newUsers',
            ),
            const SizedBox(height: 10),
            GrowthChartCard(
              title: 'New opportunities',
              valueLabel: 'new opportunities',
              docs: docs,
              path: 'engagement.opportunitiesCreated',
            ),
            const SizedBox(height: 10),
            GrowthChartCard(
              title: 'Comments',
              valueLabel: 'comments',
              docs: docs,
              path: 'engagement.comments',
            ),
          ],
        );
      },
    );
  }
}

class GrowthChartCard extends StatefulWidget {
  final String title;
  final String valueLabel;
  final List<QueryDocumentSnapshot> docs;
  final List<GrowthChartPoint>? points;
  final String path;

  const GrowthChartCard({
    super.key,
    required this.title,
    required this.valueLabel,
    required this.docs,
    required this.path,
  }) : points = null;

  const GrowthChartCard.fromPoints({
    super.key,
    required this.title,
    required this.valueLabel,
    required List<GrowthChartPoint> this.points,
  }) : docs = const [],
       path = '';

  @override
  State<GrowthChartCard> createState() => _GrowthChartCardState();
}

class _GrowthChartCardState extends State<GrowthChartCard> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final points =
        widget.points ??
        growthChartPointsFromDocs(
          widget.docs,
          widget.path,
          now: DateTime.now(),
        );
    final summary = growthChartSummary(points);
    final selectedPoint = _selectedIndex == null
        ? null
        : points[_selectedIndex!];
    final maxValue = points.isEmpty
        ? 1
        : points.map((point) => point.value).reduce((a, b) => a > b ? a : b);
    final chartMax = maxValue <= 0 ? 1 : maxValue;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: AppColors.charcoal,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${summary.last7DaysTotal} last 7 days',
                      style: const TextStyle(
                        color: AppColors.charcoal,
                        fontSize: 22,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      summary.comparisonLabel,
                      style: TextStyle(
                        color: summary.changePercent == null
                            ? AppColors.textMuted
                            : summary.changePercent! >= 0
                            ? AppColors.success
                            : AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.elevatedSurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '14 days',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (selectedPoint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '${selectedPoint.dateLabel} · ${selectedPoint.value} ${widget.valueLabel}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          else if (summary.last14DaysTotal == 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'No ${widget.valueLabel} in this period',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          SizedBox(
            height: 148,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 28,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              chartMax.toString(),
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Text(
                              '0',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (
                              var index = 0;
                              index < points.length;
                              index += 1
                            )
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: _GrowthBar(
                                    point: points[index],
                                    maxValue: chartMax,
                                    selected: _selectedIndex == index,
                                    onTap: () {
                                      setState(() {
                                        _selectedIndex = index;
                                      });
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: Row(
                    children: [
                      for (var index = 0; index < points.length; index += 1)
                        Expanded(
                          child: Text(
                            points[index].showAxisLabel
                                ? points[index].dateLabel
                                : '',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GrowthBar extends StatelessWidget {
  final GrowthChartPoint point;
  final int maxValue;
  final bool selected;
  final VoidCallback onTap;

  const _GrowthBar({
    required this.point,
    required this.maxValue,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final heightFactor = maxValue == 0 ? 0.0 : point.value / maxValue;

    return Semantics(
      button: true,
      label: '${point.dateLabel}, ${point.value}',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: heightFactor == 0 ? 0.04 : heightFactor,
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                color: point.value == 0
                    ? AppColors.border.withValues(alpha: 0.85)
                    : selected
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GrowthChartPoint {
  final String dayId;
  final String dateLabel;
  final int value;
  final bool showAxisLabel;

  const GrowthChartPoint({
    required this.dayId,
    required this.dateLabel,
    required this.value,
    required this.showAxisLabel,
  });
}

class GrowthChartSummary {
  final int last7DaysTotal;
  final int previous7DaysTotal;
  final int last14DaysTotal;
  final int? changePercent;

  const GrowthChartSummary({
    required this.last7DaysTotal,
    required this.previous7DaysTotal,
    required this.last14DaysTotal,
    required this.changePercent,
  });

  String get comparisonLabel {
    if (previous7DaysTotal == 0) {
      return last7DaysTotal == 0
          ? 'No activity in the previous 7 days'
          : 'No previous 7-day activity';
    }

    if (changePercent == 0) {
      return 'No change vs previous 7 days';
    }

    final direction = changePercent! > 0 ? '↑' : '↓';
    return '$direction ${changePercent!.abs()}% vs previous 7 days';
  }
}

List<GrowthChartPoint> growthChartPointsFromDocs(
  List<QueryDocumentSnapshot> docs,
  String path, {
  required DateTime now,
}) {
  final dataByDay = <String, Map<String, dynamic>>{};

  for (final doc in docs) {
    final data = doc.data() as Map<String, dynamic>;
    final dayId = _stringValue(data['periodId']) ?? doc.id;
    dataByDay[dayId] = data;
  }

  return growthChartPointsFromDailyData(dataByDay, path, now: now);
}

List<GrowthChartPoint> growthChartPointsFromDailyData(
  Map<String, Map<String, dynamic>> dataByDay,
  String path, {
  required DateTime now,
}) {
  final dayIds = UkActivityPeriods.rollingDayIds(now: now, days: 14).reversed;
  final points = <GrowthChartPoint>[];

  for (final dayId in dayIds) {
    final value = FounderDashboardScreen._number(dataByDay[dayId] ?? {}, path);
    final index = points.length;
    points.add(
      GrowthChartPoint(
        dayId: dayId,
        dateLabel: _shortDateLabel(dayId),
        value: value,
        showAxisLabel: index.isEven || index == 13,
      ),
    );
  }

  return points;
}

GrowthChartSummary growthChartSummary(List<GrowthChartPoint> points) {
  final previous7 = points
      .take(7)
      .fold<int>(0, (total, point) => total + point.value);
  final last7 = points
      .skip(points.length > 7 ? points.length - 7 : 0)
      .fold<int>(0, (total, point) => total + point.value);
  final last14 = points.fold<int>(0, (total, point) => total + point.value);
  final changePercent = previous7 == 0
      ? null
      : (((last7 - previous7) / previous7) * 100).round();

  return GrowthChartSummary(
    last7DaysTotal: last7,
    previous7DaysTotal: previous7,
    last14DaysTotal: last14,
    changePercent: changePercent,
  );
}

String _shortDateLabel(String dayId) {
  final parts = dayId.split('-');
  if (parts.length != 3) return dayId;

  final day = int.tryParse(parts[2]);
  final month = int.tryParse(parts[1]);
  if (day == null || month == null || month < 1 || month > 12) return dayId;

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  return '$day ${months[month - 1]}';
}

class _ReportsHistoryPanel extends StatelessWidget {
  const _ReportsHistoryPanel();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('founderReports')
          .orderBy('generatedAt', descending: true)
          .limit(8)
          .snapshots(),
      builder: (context, snapshot) {
        final reports = snapshot.data?.docs ?? [];

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.72)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Weekly reports',
                style: TextStyle(
                  color: AppColors.charcoal,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              if (reports.isEmpty)
                const Text(
                  'No weekly reports yet',
                  style: TextStyle(color: AppColors.textMuted),
                )
              else
                for (final report in reports)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FounderWeeklyReportCard(
                      reportId: report.id,
                      data: report.data() as Map<String, dynamic>,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WeeklyReportDetailScreen(
                              reportId: report.id,
                              data: report.data() as Map<String, dynamic>,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class FounderWeeklyReportCard extends StatelessWidget {
  final String reportId;
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const FounderWeeklyReportCard({
    super.key,
    required this.reportId,
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final periodId = _stringValue(data['periodId']) ?? reportId;
    final summary = weeklyReportCardSummary(data);

    return Material(
      color: AppColors.elevatedSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.72)),
          ),
          child: Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: AppColors.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      periodId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.charcoal,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WeeklyReportDetailScreen extends StatelessWidget {
  final String reportId;
  final Map<String, dynamic> data;
  final Future<ActiveUserCounts>? activityCountsFuture;

  const WeeklyReportDetailScreen({
    super.key,
    required this.reportId,
    required this.data,
    this.activityCountsFuture,
  });

  @override
  Widget build(BuildContext context) {
    final periodId = _stringValue(data['periodId']) ?? reportId;
    final generatedAt = _dateTimeValue(data['generatedAt']);
    final metrics = weeklyReportMetricsWithoutActiveUsers(data);
    final otherMetrics = weeklyReportOtherMetrics(data);
    final topCategories = weeklyReportTopList(data, 'community.topCategories');
    final activeLocations = weeklyReportTopList(
      data,
      'community.activeLocations',
    );
    final hasTopLists = topCategories.isNotEmpty || activeLocations.isNotEmpty;
    final totalUsers = weeklyReportTotalUsers(data);
    final reportEndDate = _weekEndDate(periodId);
    final activeCountsFuture =
        activityCountsFuture ??
        (reportEndDate == null
            ? null
            : FounderActiveUserAnalytics().fetchCounts(now: reportEndDate));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(periodId),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.charcoal,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Weekly report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _weekRangeLabel(periodId),
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (generatedAt != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Generated ${_formatDate(generatedAt)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (activeCountsFuture == null)
            _WeeklyReportActivityUnavailable(totalUsers: totalUsers)
          else
            FutureBuilder<ActiveUserCounts>(
              future: activeCountsFuture,
              builder: (context, snapshot) {
                final counts = snapshot.data ?? ActiveUserCounts.empty;
                final activeMetrics = [
                  WeeklyReportMetric('Active on final day', counts.dau),
                  WeeklyReportMetric('Active during report week', counts.wau),
                  WeeklyReportMetric('Active 30 days to week end', counts.mau),
                  if (totalUsers != null)
                    WeeklyReportMetric('Current accounts then', totalUsers),
                ];

                return _WeeklyReportMetricSection(
                  title: 'User activity',
                  metrics: activeMetrics,
                );
              },
            ),
          if (metrics.isEmpty && otherMetrics.isEmpty && !hasTopLists)
            const _WeeklyReportEmptyState()
          else ...[
            if (metrics.isNotEmpty)
              _WeeklyReportMetricSection(
                title: 'Captured figures',
                metrics: metrics,
              ),
            if (hasTopLists) ...[
              const SizedBox(height: 16),
              _WeeklyReportLists(
                topCategories: topCategories,
                activeLocations: activeLocations,
              ),
            ],
            if (otherMetrics.isNotEmpty) ...[
              const SizedBox(height: 16),
              _WeeklyReportMetricSection(
                title: 'Other captured analytics',
                metrics: otherMetrics,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _WeeklyReportMetricSection extends StatelessWidget {
  final String title;
  final List<WeeklyReportMetric> metrics;

  const _WeeklyReportMetricSection({
    required this.title,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 9),
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.charcoal,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth >= 760 ? 3 : 2;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: metrics.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: constraints.maxWidth >= 760 ? 2.15 : 1.45,
              ),
              itemBuilder: (context, index) {
                final metric = metrics[index];

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.72),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        metric.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        metric.value.toString(),
                        style: const TextStyle(
                          color: AppColors.charcoal,
                          fontSize: 26,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _WeeklyReportActivityUnavailable extends StatelessWidget {
  final int? totalUsers;

  const _WeeklyReportActivityUnavailable({required this.totalUsers});

  @override
  Widget build(BuildContext context) {
    final metrics = [
      if (totalUsers != null)
        WeeklyReportMetric('Current accounts then', totalUsers!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (metrics.isNotEmpty) ...[
          _WeeklyReportMetricSection(title: 'User activity', metrics: metrics),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.72)),
          ),
          child: const Text(
            'Historical activity is unavailable for this report period.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _WeeklyReportLists extends StatelessWidget {
  final List<MapEntry<String, int>> topCategories;
  final List<MapEntry<String, int>> activeLocations;

  const _WeeklyReportLists({
    required this.topCategories,
    required this.activeLocations,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final children = [
          Expanded(
            child: _TopListCard(title: 'Top categories', items: topCategories),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _TopListCard(
              title: 'Opportunity locations',
              items: activeLocations,
            ),
          ),
        ];

        if (constraints.maxWidth < 620) {
          return Column(
            children: [
              _TopListCard(title: 'Top categories', items: topCategories),
              const SizedBox(height: 10),
              _TopListCard(
                title: 'Opportunity locations',
                items: activeLocations,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      },
    );
  }
}

class _WeeklyReportEmptyState extends StatelessWidget {
  const _WeeklyReportEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.72)),
      ),
      child: const Text(
        'No weekly metrics were captured for this report.',
        style: TextStyle(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class WeeklyReportMetric {
  final String label;
  final int value;

  const WeeklyReportMetric(this.label, this.value);
}

List<WeeklyReportMetric> weeklyReportMetricsWithoutActiveUsers(
  Map<String, dynamic> data,
) {
  final week = _mapValue(data['week']);
  final metrics = <WeeklyReportMetric>[];

  void add(String label, Map<String, dynamic> source, String path) {
    final value = _optionalNumber(source, path);
    if (value != null) {
      metrics.add(WeeklyReportMetric(label, value));
    }
  }

  add('New users/sign-ups', week, 'users.newUsers');
  add(
    'Opportunities/activities created',
    week,
    'engagement.opportunitiesCreated',
  );
  add('Bookings started', week, 'bookings.started');
  add('Bookings confirmed', week, 'bookings.confirmed');
  add('Bookings completed', week, 'bookings.completed');
  add('Bookings cancelled', week, 'bookings.cancelled');
  add('Pending booking approvals', week, 'bookings.pendingBusinessApproval');

  return metrics;
}

int? weeklyReportTotalUsers(Map<String, dynamic> data) {
  final summary = _mapValue(data['summary']);
  return _optionalNumber(summary, 'users.activeUsers') ??
      _optionalNumber(summary, 'users.totalUsersCreated');
}

String weeklyReportCardSummary(Map<String, dynamic> data) {
  final week = _mapValue(data['week']);
  final parts = <String>[];

  void add(String label, String path) {
    final value = _optionalNumber(week, path);
    if (value != null) {
      parts.add('$value $label');
    }
  }

  add('active users', 'activity.weeklyActiveUsers');
  add('new users', 'users.newUsers');
  add('new opportunities', 'engagement.opportunitiesCreated');
  add('comments', 'engagement.comments');

  if (parts.isNotEmpty) {
    return parts.take(3).join(' · ');
  }

  final metricCount =
      weeklyReportMetricsWithoutActiveUsers(data).length +
      (weeklyReportTotalUsers(data) == null ? 0 : 1);
  return metricCount == 1
      ? '1 captured metric'
      : '$metricCount captured metrics';
}

List<WeeklyReportMetric> weeklyReportOtherMetrics(Map<String, dynamic> data) {
  final shownPaths = {
    'activity.dailyActiveUsers',
    'activity.weeklyActiveUsers',
    'activity.monthlyActiveUsers',
    'users.newUsers',
    'engagement.opportunitiesCreated',
    'communityHelp.postsCreated',
    'serviceRequests.created',
    'businesses.active',
    'bookings.started',
    'bookings.confirmed',
    'bookings.completed',
    'bookings.cancelled',
    'bookings.pendingBusinessApproval',
    'community.topCategories',
    'community.activeLocations',
  };
  final flattened = _flattenNumeric(_mapValue(data['week']));
  final metrics = flattened.entries
      .where((entry) => !shownPaths.any((path) => entry.key.startsWith(path)))
      .map((entry) => WeeklyReportMetric(_metricLabel(entry.key), entry.value))
      .toList();

  metrics.sort((a, b) => a.label.compareTo(b.label));
  return metrics;
}

List<MapEntry<String, int>> weeklyReportTopList(
  Map<String, dynamic> data,
  String path,
) {
  final week = _mapValue(data['week']);
  final value = _valueAtPath(week, path);
  if (value is! Map) return [];

  final entries = value.entries
      .where((entry) => entry.value is num)
      .map(
        (entry) => MapEntry(entry.key.toString(), (entry.value as num).toInt()),
      )
      .toList();

  entries.sort((a, b) => b.value.compareTo(a.value));
  return entries.take(5).toList();
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return {};
}

int? _optionalNumber(Map<String, dynamic> data, String path) {
  final value = _valueAtPath(data, path);
  if (value is num) return value.toInt();
  return null;
}

Object? _valueAtPath(Map<String, dynamic> data, String path) {
  if (data[path] != null) return data[path];

  dynamic value = data;
  for (final part in path.split('.')) {
    if (value is! Map) return null;
    value = value[part];
  }
  return value;
}

Map<String, int> _flattenNumeric(
  Map<String, dynamic> data, [
  String prefix = '',
]) {
  final values = <String, int>{};

  data.forEach((key, value) {
    final path = prefix.isEmpty ? key : '$prefix.$key';
    if (value is num) {
      values[path] = value.toInt();
    } else if (value is Map) {
      values.addAll(_flattenNumeric(_mapValue(value), path));
    }
  });

  return values;
}

String _metricLabel(String path) {
  return path
      .split('.')
      .map(
        (part) => part
            .replaceAllMapped(
              RegExp(r'([a-z])([A-Z])'),
              (match) => '${match[1]} ${match[2]}',
            )
            .replaceAll('-', ' '),
      )
      .join(' / ')
      .replaceFirstMapped(
        RegExp(r'^[a-z]'),
        (match) => match[0]!.toUpperCase(),
      );
}

String _weekRangeLabel(String periodId) {
  final dates = _weekStartAndEnd(periodId);
  if (dates == null) return periodId;

  return '${_formatDate(dates.start)} - ${_formatDate(dates.end)}';
}

({DateTime start, DateTime end})? _weekStartAndEnd(String periodId) {
  final match = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(periodId);
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final week = int.parse(match.group(2)!);
  final fourthOfJanuary = DateTime(year, 1, 4);
  final firstWeekMonday = fourthOfJanuary.subtract(
    Duration(days: fourthOfJanuary.weekday - DateTime.monday),
  );
  final start = firstWeekMonday.add(Duration(days: (week - 1) * 7));
  final end = start.add(const Duration(days: 6));

  return (start: start, end: end);
}

DateTime? _weekEndDate(String periodId) {
  final dates = _weekStartAndEnd(periodId);
  if (dates == null) return null;
  return DateTime(dates.end.year, dates.end.month, dates.end.day, 12);
}

@visibleForTesting
DateTime? weekEndDateForTesting(String periodId) => _weekEndDate(periodId);

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

String? _stringValue(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

DateTime? _dateTimeValue(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
