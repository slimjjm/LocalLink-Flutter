import 'package:flutter/material.dart';

import '../models/business_dashboard_model.dart';
import '../services/business_dashboard_service.dart';
import '../theme/app_colors.dart';
import 'business_bookings_screen.dart';
import 'business_calendar_screen.dart';
import 'business_profile_screen.dart';
import 'business_service_requests_screen.dart';
import 'business_services_screen.dart';
import 'inbox_screen.dart';
import 'post_availability_screen.dart';

class BusinessHomeScreen extends StatefulWidget {
  final String businessId;

  const BusinessHomeScreen({super.key, required this.businessId});

  @override
  State<BusinessHomeScreen> createState() => _BusinessHomeScreenState();
}

class _BusinessHomeScreenState extends State<BusinessHomeScreen> {
  late Future<BusinessDashboardModel> dashboardFuture;
  late Future<BusinessDashboardMessagingModel> messagingFuture;

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  void loadDashboard() {
    dashboardFuture = BusinessDashboardService.loadDashboard(widget.businessId);
    messagingFuture = BusinessDashboardService.loadMessagingSummary(
      widget.businessId,
    );
  }

  Future<void> _refresh() async {
    setState(loadDashboard);
    await Future.wait([dashboardFuture, messagingFuture]);
  }

  void _openPostAvailability() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostAvailabilityScreen(businessId: widget.businessId),
      ),
    );
  }

  void _openBookings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessBookingsScreen(businessId: widget.businessId),
      ),
    );
  }

  void _openMessages() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            InboxScreen(businessId: widget.businessId, currentRole: 'business'),
      ),
    );
  }

  void _openServices() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessServicesScreen(businessId: widget.businessId),
      ),
    );
  }

  void _openRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BusinessServiceRequestsScreen(businessId: widget.businessId),
      ),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessProfileScreen(businessId: widget.businessId),
      ),
    );
  }

  void _openDiary() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessCalendarScreen(businessId: widget.businessId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        title: const Text(
          'Your Page',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: FutureBuilder<BusinessDashboardModel>(
        future: dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _DashboardLoading();
          }

          if (snapshot.hasError) {
            return _DashboardMessage(
              icon: Icons.error_outline_rounded,
              title: 'We could not load your Page',
              message: 'Please check your connection and try again.',
              actionLabel: 'Retry',
              onAction: () => setState(loadDashboard),
            );
          }

          if (!snapshot.hasData) {
            return _DashboardMessage(
              icon: Icons.storefront_outlined,
              title: 'Your Page is getting ready',
              message:
                  'Bookings, messages and available time will appear here.',
              actionLabel: 'Refresh',
              onAction: () => setState(loadDashboard),
            );
          }

          final dashboard = snapshot.data!;

          return RefreshIndicator(
            color: AppColors.serviceGreen,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _DashboardHeader(dashboard: dashboard),
                const SizedBox(height: 18),
                _SetupAlerts(dashboard: dashboard),
                const SizedBox(height: 18),
                _SectionHeader(
                  title: 'Quick actions',
                  subtitle: 'Manage what you offer locally.',
                ),
                const SizedBox(height: 12),
                _ActionGrid(
                  actions: [
                    _BusinessAction(
                      title: 'Share time',
                      subtitle: 'Share available time',
                      icon: Icons.event_available_outlined,
                      color: AppColors.serviceGreen,
                      onTap: _openPostAvailability,
                    ),
                    _BusinessAction(
                      title: 'Diary',
                      subtitle: 'See today clearly',
                      icon: Icons.calendar_month_outlined,
                      color: AppColors.primary,
                      onTap: _openDiary,
                    ),
                    _BusinessAction(
                      title: 'Bookings',
                      subtitle: 'Manage appointments',
                      icon: Icons.calendar_today_outlined,
                      color: AppColors.primary,
                      onTap: _openBookings,
                    ),
                    _BusinessAction(
                      title: 'Messages',
                      subtitle: 'Reply to people',
                      icon: Icons.chat_bubble_outline,
                      color: AppColors.info,
                      onTap: _openMessages,
                    ),
                    _BusinessAction(
                      title: 'Services',
                      subtitle: 'Manage your offer',
                      icon: Icons.handshake_outlined,
                      color: AppColors.serviceGreen,
                      onTap: _openServices,
                    ),
                    _BusinessAction(
                      title: 'Requests',
                      subtitle: 'Find people nearby',
                      icon: Icons.campaign_outlined,
                      color: AppColors.warning,
                      onTap: _openRequests,
                    ),
                    _BusinessAction(
                      title: 'Page details',
                      subtitle: 'Update your page',
                      icon: Icons.storefront_outlined,
                      color: AppColors.charcoal,
                      onTap: _openProfile,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _AvailabilityStatusCard(
                  dashboard: dashboard,
                  onPostAvailability: _openPostAvailability,
                  onOpenBookings: _openBookings,
                ),
                const SizedBox(height: 22),
                _SectionHeader(
                  title: 'Today',
                  subtitle: 'A quick look at what needs attention.',
                ),
                const SizedBox(height: 12),
                _DashboardStats(
                  dashboard: dashboard,
                  messagingFuture: messagingFuture,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 14),
            Text(
              'Getting your Page ready...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _DashboardMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, height: 1.35),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  final BusinessDashboardModel dashboard;

  const _DashboardHeader({required this.dashboard});

  @override
  Widget build(BuildContext context) {
    final statusText = dashboard.isHealthy
        ? 'Ready for bookings'
        : dashboard.healthTitle;
    final statusColor = dashboard.isHealthy
        ? AppColors.success
        : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.serviceGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.storefront_outlined,
              color: AppColors.serviceGreen,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your local page',
                  style: TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Keep track of bookings, messages and the times you have shared.',
                  style: TextStyle(color: AppColors.textMuted, height: 1.35),
                ),
                const SizedBox(height: 12),
                _StatusPill(
                  label: statusText,
                  icon: dashboard.isHealthy
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  color: statusColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupAlerts extends StatelessWidget {
  final BusinessDashboardModel dashboard;

  const _SetupAlerts({required this.dashboard});

  @override
  Widget build(BuildContext context) {
    final alerts = <String>[
      if (!dashboard.hasServices)
        'Add a service before sharing when people can book you.',
      if (!dashboard.hasAvailability)
        'Share your first available time so nearby people can see you.',
      if (dashboard.restrictionMode)
        'A subscription step is needed before every Page tool is available.',
    ];

    if (alerts.isEmpty) {
      return const _TrustNotice(
        icon: Icons.check_circle_outline,
        text: 'Your Page is ready for local bookings.',
        color: AppColors.success,
      );
    }

    return Column(
      children: alerts
          .map(
            (alert) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TrustNotice(
                icon: Icons.info_outline,
                text: alert,
                color: AppColors.warning,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _TrustNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _TrustNotice({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.charcoal,
            fontSize: 20,
            fontWeight: FontWeight.w800,
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

class _ActionGrid extends StatelessWidget {
  final List<_BusinessAction> actions;

  const _ActionGrid({required this.actions});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 3 : 2;
        final spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: actions
              .map((action) => SizedBox(width: itemWidth, child: action))
              .toList(),
        );
      },
    );
  }
}

class _BusinessAction extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BusinessAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
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
          height: 128,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvailabilityStatusCard extends StatelessWidget {
  final BusinessDashboardModel dashboard;
  final VoidCallback onPostAvailability;
  final VoidCallback onOpenBookings;

  const _AvailabilityStatusCard({
    required this.dashboard,
    required this.onPostAvailability,
    required this.onOpenBookings,
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Available time',
                  style: TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onPostAvailability,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Share'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560 ? 4 : 2;
              final spacing = 10.0;
              final itemWidth =
                  (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _MetricTile(
                      label: 'Live',
                      value: dashboard.liveAvailability.toString(),
                      emptyText: 'Share your first time',
                      onTap: onPostAvailability,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _MetricTile(
                      label: 'Coming up',
                      value: dashboard.scheduledAvailability.toString(),
                      emptyText: 'Share more time',
                      onTap: onPostAvailability,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _MetricTile(
                      label: 'Needs reply',
                      value: dashboard.pendingApprovalBookings.toString(),
                      emptyText: 'Nothing waiting',
                      onTap: onOpenBookings,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _MetricTile(
                      label: 'Ended today',
                      value: dashboard.expiredAvailabilityToday.toString(),
                      emptyText: 'Nothing ended',
                      onTap: onPostAvailability,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DashboardStats extends StatelessWidget {
  final BusinessDashboardModel dashboard;
  final Future<BusinessDashboardMessagingModel> messagingFuture;

  const _DashboardStats({
    required this.dashboard,
    required this.messagingFuture,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        final spacing = 10.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: itemWidth,
              child: _MetricTile(
                label: 'Bookings',
                value: dashboard.upcomingBookings.toString(),
                emptyText: 'No bookings yet',
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: FutureBuilder<BusinessDashboardMessagingModel>(
                future: messagingFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _MetricTile(
                      label: 'Messages',
                      value: '...',
                      emptyText: 'Checking inbox',
                    );
                  }

                  final unread = snapshot.data?.unreadMessages ?? 0;
                  return _MetricTile(
                    label: 'Messages',
                    value: snapshot.hasError ? '-' : unread.toString(),
                    emptyText: snapshot.hasError
                        ? 'Could not check'
                        : 'No unread messages',
                  );
                },
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _MetricTile(
                label: 'Available time',
                value: dashboard.liveAvailability.toString(),
                emptyText: 'Share time',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String emptyText;
  final VoidCallback? onTap;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.emptyText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final count = int.tryParse(value) ?? 0;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: count == 0 ? AppColors.textMuted : AppColors.charcoal,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                count == 0 ? emptyText : 'Up to date',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StatusPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
