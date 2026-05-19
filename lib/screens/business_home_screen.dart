import 'package:flutter/material.dart';

import '../models/business_dashboard_model.dart';
import '../services/business_dashboard_service.dart';

import 'business_bookings_screen.dart';
import 'business_services_screen.dart';
import 'business_staff_screen.dart';
import 'business_calendar_screen.dart';
import 'business_subscription_screen.dart';
import 'inbox_screen.dart';

class BusinessHomeScreen extends StatefulWidget {

  final String businessId;

  const BusinessHomeScreen({
    super.key,
    required this.businessId,
  });

  @override
  State<BusinessHomeScreen> createState() =>
      _BusinessHomeScreenState();
}

class _BusinessHomeScreenState
    extends State<BusinessHomeScreen> {

  late Future<BusinessDashboardModel>
      dashboardFuture;

  @override
  void initState() {
    super.initState();

    loadDashboard();
  }

  void loadDashboard() {

    dashboardFuture =
        BusinessDashboardService
            .loadDashboard(
      widget.businessId,
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor:
          const Color(0xFFF9F6F2),

      appBar: AppBar(

        elevation: 0,

        backgroundColor:
            const Color(0xFFF9F6F2),

        foregroundColor:
            const Color(0xFF1E1E1E),

        title: const Text(

          'Business Dashboard',

          style: TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),

      body: FutureBuilder<
          BusinessDashboardModel>(

        future: dashboardFuture,

        builder: (context, snapshot) {

          // =====================================
          // LOADING
          // =====================================

          if (snapshot.connectionState ==
              ConnectionState.waiting) {

            return const Center(
              child:
                  CircularProgressIndicator(),
            );
          }

          // =====================================
          // ERROR
          // =====================================

          if (snapshot.hasError) {

            return Center(

              child: Padding(

                padding:
                    const EdgeInsets.all(
                  24,
                ),

                child: Column(

                  mainAxisAlignment:
                      MainAxisAlignment.center,

                  children: [

                    const Icon(
                      Icons.error_outline,
                      size: 60,
                      color: Colors.red,
                    ),

                    const SizedBox(height: 20),

                    const Text(

                      'Dashboard failed to load',

                      style: TextStyle(
                        fontSize: 22,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      snapshot.error
                          .toString(),
                      textAlign:
                          TextAlign.center,
                    ),

                    const SizedBox(height: 30),

                    ElevatedButton(

                      onPressed: () {

                        setState(() {
                          loadDashboard();
                        });
                      },

                      child:
                          const Text(
                        'Retry',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // =====================================
          // EMPTY
          // =====================================

          if (!snapshot.hasData) {

            return const Center(
              child:
                  Text('No dashboard data'),
            );
          }

          final dashboard =
              snapshot.data!;

          return RefreshIndicator(

            onRefresh: () async {

              setState(() {
                loadDashboard();
              });
            },

            child: ListView(

              padding:
                  const EdgeInsets.all(
                20,
              ),

              children: [

                // =====================================
                // HERO HEADER
                // =====================================

                Container(

                  padding:
                      const EdgeInsets.all(
                    24,
                  ),

                  decoration: BoxDecoration(

                    gradient:
                        const LinearGradient(

                      colors: [
                        Color(0xFFF26A2E),
                        Color(0xFFE65100),
                      ],

                      begin:
                          Alignment.topLeft,

                      end:
                          Alignment.bottomRight,
                    ),

                    borderRadius:
                        BorderRadius.circular(
                      28,
                    ),
                  ),

                  child: Column(

                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,

                    children: [

                      const Text(

                        'LocalLink Business',

                        style: TextStyle(
                          color:
                              Colors.white70,
                          fontSize: 16,
                        ),
                      ),

                      const SizedBox(
                        height: 10,
                      ),

                      const Text(

                        'Dashboard Overview',

                        style: TextStyle(
                          color:
                              Colors.white,
                          fontSize: 32,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      Text(

                        DateTime.now()
                            .toString()
                            .split(' ')
                            .first,

                        style: const TextStyle(
                          color:
                              Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // =====================================
                // STATS
                // =====================================

                Row(

                  children: [

                    Expanded(
                      child: _StatCard(
                        title:
                            'Bookings',
                        value: dashboard
                            .todayBookings
                            .toString(),
                        icon:
                            Icons.event,
                      ),
                    ),

                    const SizedBox(
                      width: 12,
                    ),

                    Expanded(
                      child: _StatCard(
                        title:
                            'Revenue',
                        value:
                            '£${(dashboard.todayRevenue / 100).toStringAsFixed(2)}',
                        icon:
                            Icons.currency_pound,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(

                  children: [

                    Expanded(
                      child: _StatCard(
                        title:
                            'Active Staff',
                        value: dashboard
                            .activeStaff
                            .toString(),
                        icon:
                            Icons.people,
                      ),
                    ),

                    const SizedBox(
                      width: 12,
                    ),
Expanded(
  child: _StatCard(
    title: 'Business Health',

    value:
        dashboard.healthTitle,

    icon:
        dashboard.isHealthy
            ? Icons.check_circle
            : Icons.warning_amber_rounded,
  ),
),
                  ],
                ),

                const SizedBox(height: 28),
const SizedBox(height: 28),

                // =====================================
                // WARNINGS
                // =====================================

                if (!dashboard
                    .stripeConnected)
                  const _WarningCard(
                    text:
                        'Stripe account not connected.',
                  ),

                if (!dashboard
                    .hasServices)
                  const _WarningCard(
                    text:
                        'No services created yet.',
                  ),

                if (!dashboard
                    .hasAvailability)
                  const _WarningCard(
                    text:
                        'No availability generated yet.',
                  ),

                if (dashboard
                    .restrictionMode)
                  const _WarningCard(
                    text:
                        'Restriction mode is active.',
                  ),

                const SizedBox(height: 30),
const Text(

  'Management',

  style: TextStyle(
    fontSize: 24,
    fontWeight:
        FontWeight.bold,
    color:
        Color(0xFF1E1E1E),
  ),
),

const SizedBox(height: 20),

_StatusRow(

  title: 'Services',

  subtitle:
      dashboard.hasServices
          ? 'Pricing live'
          : 'Add your first service',

  icon: Icons.cut,

  color:
      dashboard.hasServices
          ? Colors.green
          : Colors.red,

  onTap: () {

    Navigator.push(

      context,

      MaterialPageRoute(
        builder: (_) =>
            BusinessServicesScreen(
          businessId:
              widget.businessId,
        ),
      ),
    );
  },
),

const SizedBox(height: 12),

const SizedBox(height: 12),

_StatusRow(

  title: 'Staff',

  subtitle:
      dashboard.activeStaff >=
              dashboard.allowedStaff
          ? 'Staff limit reached'
          : dashboard.hasStaff
              ? '${dashboard.activeStaff}/${dashboard.allowedStaff} staff used'
              : 'Add team members',

  icon: Icons.people_alt,

  color:
      dashboard.activeStaff >=
              dashboard.allowedStaff
          ? Colors.orange
          : dashboard.hasStaff
              ? Colors.green
              : Colors.red,

  onTap: () {

    Navigator.push(

      context,

      MaterialPageRoute(
        builder: (_) =>
            BusinessStaffScreen(
          businessId:
              widget.businessId,
        ),
      ),
    );
  },
),
const SizedBox(height: 12),

_StatusRow(

  title: 'Availability',

  subtitle:
      dashboard.hasAvailability
          ? 'Ready for bookings'
          : 'Generate slots',

  icon: Icons.schedule,

  color:
      dashboard.hasAvailability
          ? Colors.green
          : Colors.orange,

  onTap: () {

    Navigator.push(

      context,

      MaterialPageRoute(
        builder: (_) =>
            BusinessCalendarScreen(
          businessId:
              widget.businessId,
        ),
      ),
    );
  },
),

const SizedBox(height: 12),

_StatusRow(

  title: 'Stripe',

  subtitle:
      dashboard.stripeConnected
          ? 'Billing active'
          : 'Setup incomplete',

  icon: Icons.credit_card,

  color:
      dashboard.stripeConnected
          ? Colors.green
          : Colors.orange,

  onTap: () {

    Navigator.push(

      context,

      MaterialPageRoute(
        builder: (_) =>
            BusinessSubscriptionScreen(
          businessId:
              widget.businessId,
        ),
      ),
    );
  },
),
                // =====================================
                // QUICK ACTIONS
                // =====================================

                const Text(

                  'Quick Actions',

                  style: TextStyle(
                    fontSize: 24,
                    fontWeight:
                        FontWeight.bold,
                    color:
                        Color(0xFF1E1E1E),
                  ),
                ),

                const SizedBox(height: 20),

                GridView.count(

                  crossAxisCount: 2,

                  shrinkWrap: true,

                  physics:
                      const NeverScrollableScrollPhysics(),

                  crossAxisSpacing: 14,

                  mainAxisSpacing: 14,

                  childAspectRatio: 1.15,

                  children: [

                    _ActionCard(

                      title:
                          'Bookings',

                      icon:
                          Icons.calendar_today,

                      onTap: () {

                        Navigator.push(

                          context,

                          MaterialPageRoute(
                            builder: (_) =>
                                BusinessBookingsScreen(
                              businessId:
                                  widget
                                      .businessId,
                            ),
                          ),
                        );
                      },
                    ),

                    _ActionCard(

                      title:
                          'Calendar',

                      icon:
                          Icons.schedule,

                      onTap: () {

                        Navigator.push(

                          context,

                          MaterialPageRoute(
                            builder: (_) =>
                                BusinessCalendarScreen(
                              businessId:
                                  widget
                                      .businessId,
                            ),
                          ),
                        );
                      },
                    ),

                    _ActionCard(

                      title:
                          'Staff',

                      icon:
                          Icons.people_alt,

                      onTap: () {

                        Navigator.push(

                          context,

                          MaterialPageRoute(
                            builder: (_) =>
                                BusinessStaffScreen(
                              businessId:
                                  widget
                                      .businessId,
                            ),
                          ),
                        );
                      },
                    ),
_ActionCard(

  title: 'Inbox',

  icon: Icons.chat_bubble_outline,

  onTap: () {

    Navigator.push(

      context,

      MaterialPageRoute(
        builder: (_) => InboxScreen(
          businessId: widget.businessId,
          currentRole: 'business',
        ),
      ),
    );
  },
),
                    _ActionCard(

                      title:
                          'Services',

                      icon: Icons.cut,

                      onTap: () {

                        Navigator.push(

                          context,

                          MaterialPageRoute(
                            builder: (_) =>
                                BusinessServicesScreen(
                              businessId:
                                  widget
                                      .businessId,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =====================================
// STAT CARD
// =====================================

class _StatCard extends StatelessWidget {

  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {

    return Container(

      padding:
          const EdgeInsets.all(20),

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius:
            BorderRadius.circular(24),

        boxShadow: [

          BoxShadow(

            color:
                Colors.black.withOpacity(
              0.05,
            ),

            blurRadius: 10,

            offset:
                const Offset(0, 4),
          ),
        ],
      ),

      child: Column(

        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          Icon(
            icon,
            size: 28,
            color:
                const Color(0xFFF26A2E),
          ),

          const SizedBox(height: 20),

          Text(

            value,

            style: const TextStyle(
              fontSize: 28,
              fontWeight:
                  FontWeight.bold,
              color:
                  Color(0xFF1E1E1E),
            ),
          ),

          const SizedBox(height: 6),

          Text(
            title,
            style: const TextStyle(
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================
// WARNING CARD
// =====================================

class _WarningCard extends StatelessWidget {

  final String text;

  const _WarningCard({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {

    return Container(

      margin:
          const EdgeInsets.only(
        bottom: 14,
      ),

      padding:
          const EdgeInsets.all(18),

      decoration: BoxDecoration(

        color:
            const Color(0xFFFFF3E0),

        borderRadius:
            BorderRadius.circular(18),
      ),

      child: Row(

        children: [

          const Icon(
            Icons.warning_amber_rounded,
            color:
                Color(0xFFE65100),
          ),

          const SizedBox(width: 14),

          Expanded(

            child: Text(

              text,

              style: const TextStyle(
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _StatusRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {

    return Material(

      color: Colors.white,

      borderRadius:
          BorderRadius.circular(22),

      child: InkWell(

        borderRadius:
            BorderRadius.circular(22),

        onTap: onTap,

        child: Container(

          padding:
              const EdgeInsets.all(18),

          decoration: BoxDecoration(

            borderRadius:
                BorderRadius.circular(22),

            boxShadow: [

              BoxShadow(

                color:
                    Colors.black.withOpacity(
                  0.05,
                ),

                blurRadius: 10,

                offset:
                    const Offset(0, 4),
              ),
            ],
          ),

          child: Row(

            children: [

              Container(

                padding:
                    const EdgeInsets.all(12),

                decoration:
                    BoxDecoration(

                  color:
                      color.withOpacity(0.12),

                  borderRadius:
                      BorderRadius.circular(16),
                ),

                child: Icon(
                  icon,
                  color: color,
                ),
              ),

              const SizedBox(width: 16),

              Expanded(

                child: Column(

                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    Text(

                      title,

                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(

                      subtitle,

                      style:
                          const TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              Icon(
                Icons.chevron_right,
                color:
                    Colors.grey.shade400,
              ),

              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
// =====================================
// ACTION CARD
// =====================================

class _ActionCard extends StatelessWidget {

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {

    return Material(

      color: Colors.white,

      borderRadius:
          BorderRadius.circular(24),

      child: InkWell(

        borderRadius:
            BorderRadius.circular(
          24,
        ),

        onTap: onTap,

        child: Container(

          padding:
              const EdgeInsets.all(
            20,
          ),

          decoration: BoxDecoration(

            borderRadius:
                BorderRadius.circular(
              24,
            ),

            boxShadow: [

              BoxShadow(

                color:
                    Colors.black.withOpacity(
                  0.04,
                ),

                blurRadius: 10,

                offset:
                    const Offset(
                  0,
                  4,
                ),
              ),
            ],
          ),

          child: Column(

            mainAxisAlignment:
                MainAxisAlignment.center,

            children: [

              Container(

                padding:
                    const EdgeInsets.all(
                  14,
                ),

                decoration:
                    BoxDecoration(

                  color:
                      const Color(
                    0xFFF26A2E,
                  ).withOpacity(0.12),

                  borderRadius:
                      BorderRadius.circular(
                    18,
                  ),
                ),

                child: Icon(

                  icon,

                  size: 34,

                  color:
                      const Color(
                    0xFFF26A2E,
                  ),
                ),
              ),

              const SizedBox(
                height: 18,
              ),

              Text(

                title,

                style: const TextStyle(
                  fontSize: 16,
                  fontWeight:
                      FontWeight.bold,
                  color:
                      Color(0xFF1E1E1E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class _MiniStat extends StatelessWidget {

  final String label;
  final String value;

  const _MiniStat({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {

    return Column(

      children: [

        Text(

          value,

          style: const TextStyle(
            fontSize: 22,
            fontWeight:
                FontWeight.bold,
            color:
                Color(0xFF1E1E1E),
          ),
        ),

        const SizedBox(height: 4),

        Text(

          label,

          style: const TextStyle(
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}