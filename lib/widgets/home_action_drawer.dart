import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/business_home_screen.dart';
import '../screens/business_list_screen.dart';
import '../screens/create_choice_screen.dart';
import '../screens/inbox_screen.dart';
import '../screens/my_opportunities_screen.dart';
import '../screens/post_service_request_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/saved_opportunities_screen.dart';
import '../services/business_access_service.dart';
import '../theme/app_colors.dart';

class HomeActionDrawer extends StatefulWidget {
  final VoidCallback onSettingsTap;

  const HomeActionDrawer({super.key, required this.onSettingsTap});

  @override
  State<HomeActionDrawer> createState() => _HomeActionDrawerState();
}

class _HomeActionDrawerState extends State<HomeActionDrawer> {
  static const double _collapsedSize = 0.064;
  static const double _expandedSize = 0.58;

  final DraggableScrollableController _drawerController =
      DraggableScrollableController();

  late final Future<DocumentSnapshot<Map<String, dynamic>>?>
  _ownedBusinessFuture;

  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _ownedBusinessFuture = _loadOwnedBusiness();
  }

  @override
  void dispose() {
    _drawerController.dispose();
    super.dispose();
  }

  void _updateExpandedState(double extent) {
    final isExpanded = extent > 0.2;

    if (isExpanded == _isExpanded) {
      return;
    }

    setState(() {
      _isExpanded = isExpanded;
    });
  }

  void _toggleDrawer() {
    final targetSize = _isExpanded ? _collapsedSize : _expandedSize;

    _drawerController.animateTo(
      targetSize,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _loadOwnedBusiness() {
    return BusinessAccessService.loadLinkedBusiness();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        _updateExpandedState(notification.extent);
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _drawerController,
        initialChildSize: _collapsedSize,
        minChildSize: _collapsedSize,
        maxChildSize: _expandedSize,
        snap: true,
        snapSizes: const [_collapsedSize, _expandedSize],
        builder: (context, scrollController) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.78),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.charcoal.withValues(alpha: 0.10),
                  blurRadius: 28,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
              children: [
                const Center(child: _DrawerHandle()),
                const SizedBox(height: 34),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Your LocalLink',
                        style: TextStyle(
                          color: AppColors.charcoal,
                          fontSize: 20,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _toggleDrawer,
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: animation,
                              child: child,
                            ),
                          );
                        },
                        child: Icon(
                          _isExpanded
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_up_rounded,
                          key: ValueKey(_isExpanded),
                        ),
                      ),
                      color: AppColors.textMuted,
                      tooltip: _isExpanded ? 'Close' : 'Open',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                const Text(
                  'Find local help, share what you offer and keep track of everything here.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13.5,
                    height: 1.32,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                _DrawerAction(
                  icon: Icons.search_rounded,
                  title: 'Find a service',
                  subtitle: 'Book trusted local help',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const BusinessListScreen(useCurrentLocation: true),
                      ),
                    );
                  },
                ),
                _DrawerAction(
                  icon: Icons.add_circle_outline_rounded,
                  title: 'Create',
                  subtitle: 'Offer a service or host an activity',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreateChoiceScreen(),
                      ),
                    );
                  },
                ),
                _DrawerAction(
                  icon: Icons.volunteer_activism_outlined,
                  title: 'Community help',
                  subtitle: 'Lost, found and free items',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PostServiceRequestScreen(),
                      ),
                    );
                  },
                ),
                _DrawerAction(
                  icon: Icons.event_available_rounded,
                  title: 'Activities',
                  subtitle: 'Joined and hosted',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MyOpportunitiesScreen(),
                      ),
                    );
                  },
                ),
                _DrawerAction(
                  icon: Icons.bookmark_border_rounded,
                  title: 'Saved',
                  subtitle: 'Activities and services to revisit',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SavedOpportunitiesScreen(),
                      ),
                    );
                  },
                ),
                _DrawerAction(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Messages',
                  subtitle: 'Bookings, requests and chats',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const InboxScreen(currentRole: 'customer'),
                      ),
                    );
                  },
                ),
                FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
                  future: _ownedBusinessFuture,
                  builder: (context, snapshot) {
                    final business = snapshot.data;

                    if (business == null || !business.exists) {
                      return const SizedBox.shrink();
                    }

                    final businessId = business.id;

                    return _DrawerAction(
                      icon: Icons.storefront_outlined,
                      title: 'Your Page',
                      subtitle: 'Services, bookings and messages',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                BusinessHomeScreen(businessId: businessId),
                          ),
                        );
                      },
                    );
                  },
                ),
                _DrawerAction(
                  icon: Icons.person_outline_rounded,
                  title: 'Profile',
                  subtitle: 'Your identity and activity',
                  onTap: () {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) return;

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(
                          userId: user.uid,
                          userName: user.displayName ?? 'User',
                          photoUrl: user.photoURL,
                        ),
                      ),
                    );
                  },
                ),
                _DrawerAction(
                  icon: Icons.manage_accounts_outlined,
                  title: 'Help & settings',
                  subtitle: 'Notifications, support and sign out',
                  onTap: widget.onSettingsTap,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DrawerHandle extends StatelessWidget {
  const _DrawerHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 5,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _DrawerAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DrawerAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.74),
                    ),
                  ),
                  child: Icon(icon, color: AppColors.charcoal, size: 20),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.charcoal,
                          fontSize: 15,
                          height: 1.12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
