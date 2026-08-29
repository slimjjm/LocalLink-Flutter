import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/firestore_collections.dart';
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

  void _selectTab(int index) {
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
        children: const [
          CustomerHomeScreen(),
          InboxScreen(currentRole: 'all'),
          MyLocalLinkScreen(),
          SettingsTabScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        backgroundColor: AppColors.card,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: _InboxTabIcon(selected: false),
            selectedIcon: _InboxTabIcon(selected: true),
            label: 'Inbox',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border_rounded),
            selectedIcon: Icon(Icons.bookmark_rounded),
            label: 'My LocalLink',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _InboxTabIcon extends StatelessWidget {
  const _InboxTabIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final icon = Icon(
      selected ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
    );

    if (user == null) return icon;

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

            if (!hasUnread) return icon;

            return Badge(
              smallSize: 8,
              backgroundColor: AppColors.primary,
              child: icon,
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
