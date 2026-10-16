import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/organisation.dart';
import '../models/organisation_role.dart';
import '../services/business_access_service.dart';
import '../services/my_locallink_organisation_service.dart';
import '../services/organisation_service.dart';
import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../utils/helpers.dart';
import 'business_bookings_screen.dart';
import 'business_calendar_screen.dart';
import 'business_detail_screen.dart';
import 'business_onboarding_screen.dart';
import 'business_profile_screen.dart';
import 'business_service_requests_screen.dart';
import 'business_services_screen.dart';
import 'create_organisation_screen.dart';
import 'customer_bookings_screen.dart';
import 'customer_service_request_screen.dart';
import 'my_opportunities_screen.dart';
import 'organisation_management_screen.dart';
import 'post_availability_screen.dart';
import 'post_service_request_screen.dart';
import 'saved_opportunities_screen.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_image.dart';
import '../widgets/local_link_surface_card.dart';

class MyLocalLinkScreen extends StatefulWidget {
  const MyLocalLinkScreen({super.key});

  @override
  State<MyLocalLinkScreen> createState() => _MyLocalLinkScreenState();
}

class _MyLocalLinkScreenState extends State<MyLocalLinkScreen> {
  late Future<DocumentSnapshot<Map<String, dynamic>>?> _businessFuture;

  @override
  void initState() {
    super.initState();
    _businessFuture = BusinessAccessService.loadLinkedBusiness();
  }

  void _refreshBusiness() {
    setState(() {
      _businessFuture = BusinessAccessService.loadLinkedBusiness();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            const Text(
              'My LocalLink',
              style: TextStyle(
                color: AppColors.charcoal,
                fontSize: 30,
                height: 1.02,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Manage what you have joined, saved, posted and offered.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            const _SectionHeader('Your activity'),
            _ActivityQuickPanel(
              items: [
                _ActivityQuickItem(
                  icon: Icons.calendar_today_outlined,
                  title: 'Bookings',
                  subtitle: 'Upcoming and past bookings',
                  onTap: () => _push(context, const CustomerBookingsScreen()),
                ),
                _ActivityQuickItem(
                  icon: Icons.groups_2_outlined,
                  title: 'Activities',
                  subtitle: 'Joined and hosted activities',
                  onTap: () => _push(context, const MyOpportunitiesScreen()),
                ),
                _ActivityQuickItem(
                  icon: Icons.bookmark_border_rounded,
                  title: 'Saved',
                  subtitle: 'Saved pages',
                  onTap: () => _push(context, const SavedOpportunitiesScreen()),
                ),
                _ActivityQuickItem(
                  icon: Icons.volunteer_activism_outlined,
                  title: 'Community Help',
                  subtitle: 'Lost and found',
                  onTap: () => _push(context, const PostServiceRequestScreen()),
                ),
                _ActivityQuickItem(
                  icon: Icons.manage_search_outlined,
                  title: 'Service requests',
                  subtitle: 'Requests posted',
                  onTap: () => _push(context, const MyServiceRequestsScreen()),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (user != null) ...[
              const _SectionHeader('Your organisations'),
              _OrganisationSection(uid: user.uid),
              _ArchivedOrganisationEntry(uid: user.uid),
              const SizedBox(height: 20),
            ],
            const _SectionHeader('Your business'),
            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
              future: _businessFuture,
              builder: (context, snapshot) {
                final business = snapshot.data;

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _BusinessLoadingCard();
                }

                if (business == null || !business.exists) {
                  return _NoBusinessCard(onCreated: _refreshBusiness);
                }

                return _BusinessSection(business: business);
              },
            ),
          ],
        ),
      ),
    );
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _ActivityQuickItem {
  const _ActivityQuickItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _ActivityQuickPanel extends StatelessWidget {
  const _ActivityQuickPanel({required this.items});

  final List<_ActivityQuickItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: LocalLinkSpacing.xs),
            child: _ActivityDashboardTile(item: item),
          ),
      ],
    );
  }
}

class _ActivityDashboardTile extends StatelessWidget {
  const _ActivityDashboardTile({required this.item});

  final _ActivityQuickItem item;

  @override
  Widget build(BuildContext context) {
    return LocalLinkSurfaceCard(
      onTap: item.onTap,
      elevated: false,
      radius: LocalLinkRadius.lg,
      color: AppColors.card,
      padding: const EdgeInsets.all(LocalLinkSpacing.sm),
      child: Row(
        children: [
          LocalLinkIconBadge(
            icon: item.icon,
            color: AppColors.primary,
            size: 40,
          ),
          const SizedBox(width: LocalLinkSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LocalLinkTextStyles.cardTitle.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: LocalLinkSpacing.xxs),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LocalLinkTextStyles.metadata.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: LocalLinkSpacing.xs),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chevron_right_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrganisationSection extends StatelessWidget {
  _OrganisationSection({required this.uid})
    : _service = MyLocalLinkOrganisationService();

  final String uid;
  final MyLocalLinkOrganisationService _service;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_ManagedOrganisationEntry>>(
      future: _loadOrganisations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _BusinessLoadingCard(label: 'Checking organisations...');
        }

        if (snapshot.hasError) {
          return const _OrganisationErrorCard();
        }

        final docs = snapshot.data ?? const [];
        if (docs.isEmpty) {
          return const _EmptyOrganisationCard();
        }

        return Column(
          children: [
            ...docs.map((entry) {
              final organisation = entry.organisation;
              return _ActionTile(
                icon: Icons.groups_2_outlined,
                title: organisation.name,
                subtitle: _organisationSubtitle(entry),
                color: AppColors.activityBlue,
                compact: true,
                trailing: const Text(
                  'Manage',
                  style: TextStyle(
                    color: AppColors.activityBlue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrganisationManagementScreen(
                      organisation: organisation,
                    ),
                  ),
                ),
              );
            }),
            _ActionTile(
              icon: Icons.add_rounded,
              title: 'Create another organisation',
              subtitle: 'Add another club, group or community organisation.',
              color: AppColors.activityBlue,
              compact: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CreateOrganisationScreen(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<List<_ManagedOrganisationEntry>> _loadOrganisations() async {
    final entries = await _service.loadManagedOrganisations(uid);
    return entries
        .map(
          (entry) => _ManagedOrganisationEntry(
            organisation: entry.organisation,
            role: entry.role,
            activityCount: entry.activityCount,
          ),
        )
        .toList();
  }

  static String _organisationSubtitle(_ManagedOrganisationEntry entry) {
    final organisation = entry.organisation;
    return [
      organisationRoleLabel(entry.role),
      if (organisation.category.isNotEmpty) organisation.category,
      if (organisation.publicLocation.isNotEmpty) organisation.publicLocation,
      if (entry.activityCount is num) '${entry.activityCount} activities',
    ].join(' · ');
  }
}

class _ArchivedOrganisationEntry extends StatelessWidget {
  _ArchivedOrganisationEntry({required this.uid})
    : _service = MyLocalLinkOrganisationService();

  final String uid;
  final MyLocalLinkOrganisationService _service;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ManagedOrganisationEntry>>(
      future: _service.loadArchivedOrganisations(uid),
      builder: (context, snapshot) {
        final archived = snapshot.data ?? const <ManagedOrganisationEntry>[];
        if (snapshot.connectionState == ConnectionState.waiting ||
            archived.isEmpty) {
          return const SizedBox.shrink();
        }
        return _ActionTile(
          icon: Icons.inventory_2_outlined,
          title: 'Archived organisations',
          subtitle: '${archived.length} hidden from LocalLink',
          color: AppColors.textMuted,
          compact: true,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ArchivedOrganisationsScreen(uid: uid),
            ),
          ),
        );
      },
    );
  }
}

class ArchivedOrganisationsScreen extends StatefulWidget {
  const ArchivedOrganisationsScreen({super.key, required this.uid});

  final String uid;

  @override
  State<ArchivedOrganisationsScreen> createState() =>
      _ArchivedOrganisationsScreenState();
}

class _ArchivedOrganisationsScreenState
    extends State<ArchivedOrganisationsScreen> {
  final _myLocalLinkService = MyLocalLinkOrganisationService();
  final _organisationService = OrganisationService();
  late Future<List<ManagedOrganisationEntry>> _future;
  String _restoringId = '';

  @override
  void initState() {
    super.initState();
    _future = _myLocalLinkService.loadArchivedOrganisations(widget.uid);
  }

  void _reload() {
    setState(() {
      _future = _myLocalLinkService.loadArchivedOrganisations(widget.uid);
    });
  }

  Future<void> _restore(Organisation organisation) async {
    setState(() => _restoringId = organisation.id);
    try {
      await _organisationService.restoreOrganisation(
        organisationId: organisation.id,
      );
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${organisation.name} is live again.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Organisation could not be restored.')),
      );
    } finally {
      if (mounted) setState(() => _restoringId = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Archived organisations'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: FutureBuilder<List<ManagedOrganisationEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text('Archived organisations could not be loaded.'),
            );
          }
          final entries = snapshot.data ?? const <ManagedOrganisationEntry>[];
          if (entries.isEmpty) {
            return const Center(child: Text('No archived organisations.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              for (final entry in entries)
                _ActionTile(
                  icon: Icons.inventory_2_outlined,
                  title: entry.organisation.name,
                  subtitle: 'Hidden from public LocalLink pages',
                  color: AppColors.textMuted,
                  compact: true,
                  trailing: Text(
                    _restoringId == entry.organisation.id
                        ? 'Restoring...'
                        : 'Restore',
                    style: const TextStyle(
                      color: AppColors.activityBlue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  onTap: _restoringId.isEmpty
                      ? () => _restore(entry.organisation)
                      : () {},
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ManagedOrganisationEntry {
  const _ManagedOrganisationEntry({
    required this.organisation,
    required this.role,
    this.activityCount,
  });

  final Organisation organisation;
  final String role;
  final Object? activityCount;
}

class _EmptyOrganisationCard extends StatelessWidget {
  const _EmptyOrganisationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Run a club, group or organisation?',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create it on LocalLink to manage activities, groups and people in one place.',
            style: TextStyle(
              color: AppColors.textMuted,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          LocalLinkButton(
            label: 'Create organisation',
            icon: Icons.add_rounded,
            expand: true,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CreateOrganisationScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrganisationErrorCard extends StatelessWidget {
  const _OrganisationErrorCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'Your organisations could not be loaded. Please try again in a moment.',
        style: TextStyle(
          color: AppColors.textMuted,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BusinessSection extends StatelessWidget {
  const _BusinessSection({required this.business});

  final DocumentSnapshot<Map<String, dynamic>> business;

  @override
  Widget build(BuildContext context) {
    final data = business.data() ?? {};
    final name = data['businessName']?.toString().trim();
    final category = data['category']?.toString().trim();
    final address = data['address']?.toString().trim();
    final logoUrl = data['logoUrl']?.toString().trim();
    final imageUrl = logoUrl?.isNotEmpty == true
        ? logoUrl!
        : businessCoverImageUrl(data);
    final isActive = data['isActive'] != false && data['status'] != 'inactive';
    final acceptingLeads = data['acceptingLeads'] != false;
    final businessId = business.id;

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.serviceGreen.withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.charcoal.withValues(alpha: 0.045),
                blurRadius: 18,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _BusinessImage(imageUrl: imageUrl),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name?.isNotEmpty == true ? name! : 'Your business',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.charcoal,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _businessSubtitle(
                            category: category,
                            address: address,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _BusinessStatusPill(
                    label: isActive ? 'Live page' : 'Not live',
                    color: isActive
                        ? AppColors.serviceGreen
                        : AppColors.warning,
                  ),
                  _BusinessStatusPill(
                    label: acceptingLeads ? 'Taking enquiries' : 'Paused',
                    color: acceptingLeads
                        ? AppColors.serviceGreen
                        : AppColors.textMuted,
                  ),
                  _BusinessHeaderAction(
                    onTap: () => _push(
                      context,
                      BusinessDetailScreen(businessId: businessId),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _ActionTile(
          icon: Icons.edit_note_rounded,
          title: 'Business profile',
          subtitle: 'Edit public details',
          color: AppColors.serviceGreen,
          compact: true,
          onTap: () =>
              _push(context, BusinessProfileScreen(businessId: businessId)),
        ),
        _ActionTile(
          icon: Icons.handshake_outlined,
          title: 'Services',
          subtitle: 'Manage bookable services',
          color: AppColors.serviceGreen,
          compact: true,
          onTap: () =>
              _push(context, BusinessServicesScreen(businessId: businessId)),
        ),
        _ActionTile(
          icon: Icons.event_available_outlined,
          title: 'Share time',
          subtitle: 'Publish a bookable opening',
          color: AppColors.serviceGreen,
          compact: true,
          onTap: () =>
              _push(context, PostAvailabilityScreen(businessId: businessId)),
        ),
        _ActionTile(
          icon: Icons.calendar_month_outlined,
          title: 'Diary',
          subtitle: 'See your business calendar',
          color: AppColors.serviceGreen,
          compact: true,
          onTap: () =>
              _push(context, BusinessCalendarScreen(businessId: businessId)),
        ),
        _ActionTile(
          icon: Icons.calendar_today_outlined,
          title: 'Business bookings',
          subtitle: 'Appointments and requests',
          color: AppColors.serviceGreen,
          compact: true,
          onTap: () =>
              _push(context, BusinessBookingsScreen(businessId: businessId)),
        ),
        _ActionTile(
          icon: Icons.campaign_outlined,
          title: 'Customer requests',
          subtitle: 'Nearby people looking for help',
          color: AppColors.serviceGreen,
          compact: true,
          onTap: () => _push(
            context,
            BusinessServiceRequestsScreen(businessId: businessId),
          ),
        ),
      ],
    );
  }

  static String _businessSubtitle({String? category, String? address}) {
    final parts = [
      if (category != null && category.isNotEmpty) category,
      if (address != null && address.isNotEmpty) address,
    ];
    return parts.isEmpty ? 'Your LocalLink business page' : parts.join(' · ');
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _BusinessHeaderAction extends StatelessWidget {
  const _BusinessHeaderAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.serviceGreen.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.open_in_new_rounded,
                size: 15,
                color: AppColors.serviceGreen,
              ),
              SizedBox(width: 5),
              Text(
                'View page',
                style: TextStyle(
                  color: AppColors.serviceGreen,
                  fontSize: 12,
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

class _BusinessImage extends StatelessWidget {
  const _BusinessImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 52,
        height: 52,
        color: AppColors.serviceGreen.withValues(alpha: 0.10),
        child: imageUrl.isEmpty
            ? const Icon(
                Icons.storefront_outlined,
                color: AppColors.serviceGreen,
              )
            : LocalLinkImage(
                imageUrl: imageUrl,
                aspectRatio: 1,
                fallbackIcon: Icons.storefront_outlined,
                accentColor: AppColors.serviceGreen,
                semanticLabel: 'Business image',
              ),
      ),
    );
  }
}

class _BusinessStatusPill extends StatelessWidget {
  const _BusinessStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _NoBusinessCard extends StatelessWidget {
  const _NoBusinessCard({required this.onCreated});

  final VoidCallback onCreated;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Offer services on LocalLink',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create a business presence when you are ready to take local enquiries or bookings.',
            style: TextStyle(
              color: AppColors.textMuted,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BusinessOnboardingScreen(),
                ),
              );
              onCreated();
            },
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Create business presence'),
          ),
        ],
      ),
    );
  }
}

class _BusinessLoadingCard extends StatelessWidget {
  const _BusinessLoadingCard({this.label = 'Checking business access...'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.charcoal,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.compact = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 38.0 : 42.0;

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 8 : 10),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.all(compact ? 12 : 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.16)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.charcoal.withValues(alpha: 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: compact ? 20 : 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.charcoal,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing ?? Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
