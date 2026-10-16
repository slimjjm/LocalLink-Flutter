import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/firestore_collections.dart';
import '../services/auth_required_action.dart';
import '../theme/app_colors.dart';
import 'customer_home_screen.dart';
import 'inbox_screen.dart';
import 'my_locallink_screen.dart';
import 'settings_tab_screen.dart';

class MainTabShellScreen extends StatefulWidget {
  const MainTabShellScreen({super.key});

  @override
  State<MainTabShellScreen> createState() => _MainTabShellScreenState();
}

class _MainTabShellScreenState extends State<MainTabShellScreen> {
  int _selectedIndex = 0;
  final ValueNotifier<int> _homeRootRequests = ValueNotifier<int>(0);

  @override
  void dispose() {
    _homeRootRequests.dispose();
    super.dispose();
  }

  Future<void> _selectTab(int index) async {
    final user = FirebaseAuth.instance.currentUser;
    final requiresAccount = index == 1 || index == 2;
    if (requiresAccount && (user == null || user.isAnonymous)) {
      await AuthRequiredAction.run(
        context,
        action: () async {
          if (!mounted) return;
          setState(() {
            _selectedIndex = index;
          });
        },
      );
      return;
    }

    if (index == 0) {
      _homeRootRequests.value += 1;
    }

    if (_selectedIndex == index) {
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          CustomerHomeScreen(rootRequests: _homeRootRequests),
          const InboxScreen(currentRole: 'all'),
          const MyLocalLinkScreen(),
          const SettingsTabScreen(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.78)),
            boxShadow: [
              BoxShadow(
                color: AppColors.charcoal.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              _DockDestination(
                label: 'Home',
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                selected: _selectedIndex == 0,
                onTap: () => _selectTab(0),
              ),
              _DockDestination(
                label: 'Inbox',
                icon: Icons.chat_bubble_outline_rounded,
                selectedIcon: Icons.chat_bubble_rounded,
                selected: _selectedIndex == 1,
                badge: const _InboxTabBadge(),
                onTap: () => _selectTab(1),
              ),
              _DockDestination(
                label: 'My LocalLink',
                icon: Icons.dashboard_outlined,
                selectedIcon: Icons.dashboard_rounded,
                selected: _selectedIndex == 2,
                onTap: () => _selectTab(2),
              ),
              _DockDestination(
                label: 'Settings',
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
                selected: _selectedIndex == 3,
                onTap: () => _selectTab(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockDestination extends StatelessWidget {
  const _DockDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textMuted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 170),
                      width: 30,
                      height: 28,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.13)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        selected ? selectedIcon : icon,
                        color: color,
                        size: selected ? 21 : 20,
                      ),
                    ),
                    if (badge != null)
                      Positioned(right: -2, top: -2, child: badge!),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? AppColors.charcoal : AppColors.textMuted,
                    fontSize: 11,
                    height: 1,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InboxTabBadge extends StatelessWidget {
  const _InboxTabBadge();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.isAnonymous) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreCollections.conversations)
          .where('customerId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, customerSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection(FirestoreCollections.conversations)
              .where('businessOwnerId', isEqualTo: user.uid)
              .snapshots(),
          builder: (context, businessSnapshot) {
            final hasUnread =
                _hasUnread(
                  customerSnapshot.data?.docs,
                  'customerUnreadCount',
                ) ||
                _hasUnread(businessSnapshot.data?.docs, 'businessUnreadCount');

            if (!hasUnread) return const SizedBox.shrink();

            return Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.card, width: 1.5),
              ),
            );
          },
        );
      },
    );
  }

  static bool _hasUnread(
    List<QueryDocumentSnapshot<Object?>>? docs,
    String field,
  ) {
    if (docs == null) return false;

    for (final doc in docs) {
      final data = doc.data();
      if (data is! Map<String, dynamic>) continue;
      final value = data[field] ?? data[_legacyUnreadField(field)];
      if (value is num && value > 0) {
        return true;
      }
    }

    return false;
  }

  static String _legacyUnreadField(String field) {
    return field == 'customerUnreadCount'
        ? 'unreadCustomerCount'
        : 'unreadBusinessCount';
  }
}
