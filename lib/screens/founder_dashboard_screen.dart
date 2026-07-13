import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/admin_access_service.dart';
import '../theme/app_colors.dart';
import 'admin_reports_screen.dart';

class FounderDashboardScreen extends StatelessWidget {
  const FounderDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AdminAccessService().isCurrentUserAdmin(),
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
          ),
          body: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('analytics')
                .doc('summary')
                .snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  const _DashboardIntro(),
                  const SizedBox(height: 16),
                  _MetricSection(
                    title: 'Users',
                    metrics: [
                      _Metric(
                        'Total ever',
                        _number(data, 'users.totalUsersCreated'),
                      ),
                      _Metric('Active', _number(data, 'users.activeUsers')),
                      _Metric('Deleted', _number(data, 'users.deletedUsers')),
                      _Metric.future(
                        'New today',
                        _periodMetric('day', 'users.newUsers'),
                      ),
                      _Metric.future(
                        'New this week',
                        _periodMetric('week', 'users.newUsers'),
                      ),
                      _Metric.future(
                        'New this month',
                        _periodMetric('month', 'users.newUsers'),
                      ),
                    ],
                  ),
                  _MetricSection(
                    title: 'Engagement',
                    metrics: [
                      _Metric.future(
                        'Opportunities today',
                        _periodMetric('day', 'engagement.opportunitiesCreated'),
                      ),
                      _Metric.future(
                        'Opportunities week',
                        _periodMetric(
                          'week',
                          'engagement.opportunitiesCreated',
                        ),
                      ),
                      _Metric.future(
                        'Opportunities month',
                        _periodMetric(
                          'month',
                          'engagement.opportunitiesCreated',
                        ),
                      ),
                      _Metric.future(
                        'Comments today',
                        _periodMetric('day', 'engagement.comments'),
                      ),
                      _Metric.future(
                        'Comments week',
                        _periodMetric('week', 'engagement.comments'),
                      ),
                      _Metric.future(
                        'Comments month',
                        _periodMetric('month', 'engagement.comments'),
                      ),
                      _Metric('Reviews', _number(data, 'engagement.reviews')),
                      _Metric('Saves', _number(data, 'engagement.saves')),
                      _Metric('Shares', _number(data, 'engagement.shares')),
                      _Metric(
                        'Reports',
                        _number(data, 'moderation.reportsSubmitted'),
                      ),
                    ],
                  ),
                  _MetricSection(
                    title: 'Activity',
                    metrics: [
                      _Metric(
                        'DAU',
                        _number(data, 'activity.dailyActiveUsers'),
                      ),
                      _Metric(
                        'WAU',
                        _number(data, 'activity.weeklyActiveUsers'),
                      ),
                      _Metric(
                        'MAU',
                        _number(data, 'activity.monthlyActiveUsers'),
                      ),
                    ],
                  ),
                  _MetricSection(
                    title: 'Moderation',
                    metrics: [
                      _Metric(
                        'Pending reports',
                        _number(data, 'moderation.pendingReports'),
                        onTap: () => _openModeration(context),
                      ),
                      _Metric(
                        'Resolved reports',
                        _number(data, 'moderation.reportsResolved'),
                        onTap: () => _openModeration(context),
                      ),
                      _Metric(
                        'Users reported',
                        _number(data, 'moderation.reportTypes.profile'),
                        onTap: () => _openModeration(context),
                      ),
                      _Metric(
                        'Opportunities reported',
                        _number(data, 'moderation.reportTypes.opportunity'),
                        onTap: () => _openModeration(context),
                      ),
                      _Metric(
                        'Comments reported',
                        _number(data, 'moderation.reportTypes.comment'),
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
        );
      },
    );
  }

  static void _openModeration(BuildContext context) {
    Navigator.push(
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
            child: _TopListCard(title: 'Active locations', items: locations),
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
        final docs = snapshot.data?.docs.reversed.toList() ?? [];

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
            _ChartCard(
              title: 'Daily registrations',
              docs: docs,
              path: 'users.newUsers',
            ),
            const SizedBox(height: 10),
            _ChartCard(
              title: 'Daily opportunities',
              docs: docs,
              path: 'engagement.opportunitiesCreated',
            ),
            const SizedBox(height: 10),
            _ChartCard(
              title: 'Daily comments',
              docs: docs,
              path: 'engagement.comments',
            ),
          ],
        );
      },
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final List<QueryDocumentSnapshot> docs;
  final String path;

  const _ChartCard({
    required this.title,
    required this.docs,
    required this.path,
  });

  @override
  Widget build(BuildContext context) {
    final values = docs
        .map(
          (doc) => FounderDashboardScreen._number(
            doc.data() as Map<String, dynamic>,
            path,
          ),
        )
        .toList();
    final maxValue = values.isEmpty
        ? 1
        : values.reduce((a, b) => a > b ? a : b);

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
          const SizedBox(height: 14),
          SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final value in values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FractionallySizedBox(
                        heightFactor: maxValue == 0 ? 0 : value / maxValue,
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.74),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
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

class _ReportsHistoryPanel extends StatelessWidget {
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
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.id,
                            style: const TextStyle(
                              color: AppColors.charcoal,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
