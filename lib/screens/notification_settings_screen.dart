import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/notification_preferences.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import 'community_alert_settings_screen.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _isSaving = false;
  NotificationSettings? _systemSettings;

  DocumentReference<Map<String, dynamic>>? get _preferencesRef {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('preferences')
        .doc('notifications');
  }

  @override
  void initState() {
    super.initState();
    _loadSystemSettings();
  }

  Future<void> _loadSystemSettings() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (!mounted) return;
    setState(() => _systemSettings = settings);
  }

  Future<void> _requestPermission() async {
    final current = await FirebaseMessaging.instance.getNotificationSettings();
    if (current.authorizationStatus == AuthorizationStatus.denied) {
      await _openDeviceSettings();
      return;
    }

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await NotificationService.shared.saveFcmTokenForCurrentUser();
    await _loadSystemSettings();
  }

  Future<void> _openDeviceSettings() async {
    final uri = Uri.parse(Platform.isIOS ? 'app-settings:' : 'package:');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open device Settings for LocalLink.')),
      );
    }
  }

  Future<void> _setPreference(String key, bool value) async {
    final ref = _preferencesRef;
    if (ref == null) return;

    setState(() => _isSaving = true);
    try {
      await ref.set({
        key: value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = _preferencesRef;
    if (ref == null) {
      return const Scaffold(body: Center(child: Text('Please sign in.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      backgroundColor: AppColors.background,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snapshot) {
          final values = NotificationPreferences.fromData(
            snapshot.data?.data(),
          );
          final status = _systemSettings?.authorizationStatus;
          final enabled =
              status == AuthorizationStatus.authorized ||
              status == AuthorizationStatus.provisional;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              _StatusCard(
                enabled: enabled,
                statusKnown: _systemSettings != null,
                denied: status == AuthorizationStatus.denied,
                onEnable: _requestPermission,
                onOpenSettings: _openDeviceSettings,
              ),
              const SizedBox(height: 18),
              _Section(
                title: 'Community Help',
                children: [
                  _PreferenceTile(
                    title: 'Responses to my posts',
                    subtitle:
                        'Replies and possible sightings on your Community Help posts.',
                    value: values[NotificationPreferences.communityResponses]!,
                    enabled: !_isSaving,
                    onChanged: (value) => _setPreference(
                      NotificationPreferences.communityResponses,
                      value,
                    ),
                  ),
                  _PreferenceTile(
                    title: 'Messages',
                    subtitle: 'Private messages about Community Help posts.',
                    value: values[NotificationPreferences.communityMessages]!,
                    enabled: !_isSaving,
                    onChanged: (value) => _setPreference(
                      NotificationPreferences.communityMessages,
                      value,
                    ),
                  ),
                  _PreferenceTile(
                    title: "Posts I'm keeping a lookout for",
                    subtitle: 'Important updates and resolution notices.',
                    value: values[NotificationPreferences.communityFollowing]!,
                    enabled: !_isSaving,
                    onChanged: (value) => _setPreference(
                      NotificationPreferences.communityFollowing,
                      value,
                    ),
                  ),
                  _PreferenceTile(
                    title: 'Nearby missing & found alerts',
                    subtitle:
                        'Missing pets and lost/found items near your alert area.',
                    value:
                        values[NotificationPreferences.nearbyCommunityAlerts]!,
                    enabled: !_isSaving,
                    onChanged: (value) => _setPreference(
                      NotificationPreferences.nearbyCommunityAlerts,
                      value,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.crisis_alert_outlined),
                    title: const Text('Community alert area'),
                    subtitle: const Text(
                      'Choose where missing and found alerts should reach you.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CommunityAlertSettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              _Section(
                title: 'Activities & Services',
                children: [
                  _PreferenceTile(
                    title: 'Activity updates',
                    subtitle:
                        "Updates about activities you've joined or posted.",
                    value: values[NotificationPreferences.activityUpdates]!,
                    enabled: !_isSaving,
                    onChanged: (value) => _setPreference(
                      NotificationPreferences.activityUpdates,
                      value,
                    ),
                  ),
                  _PreferenceTile(
                    title: 'Service & booking updates',
                    subtitle:
                        'Responses, confirmations and changes to your services/bookings.',
                    value:
                        values[NotificationPreferences.serviceBookingUpdates]!,
                    enabled: !_isSaving,
                    onChanged: (value) => _setPreference(
                      NotificationPreferences.serviceBookingUpdates,
                      value,
                    ),
                  ),
                ],
              ),
              _Section(
                title: 'Reminders',
                children: [
                  _PreferenceTile(
                    title: 'Reminders',
                    subtitle:
                        'Useful reminders about activities, bookings and expiring posts.',
                    value: values[NotificationPreferences.reminders]!,
                    enabled: !_isSaving,
                    onChanged: (value) => _setPreference(
                      NotificationPreferences.reminders,
                      value,
                    ),
                  ),
                ],
              ),
              _Section(
                title: 'Local discovery',
                children: [
                  _PreferenceTile(
                    title: 'Things happening nearby',
                    subtitle:
                        'Occasional suggestions about relevant activities and services.',
                    value: values[NotificationPreferences.localDiscovery]!,
                    enabled: !_isSaving,
                    onChanged: (value) => _setPreference(
                      NotificationPreferences.localDiscovery,
                      value,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.enabled,
    required this.statusKnown,
    required this.denied,
    required this.onEnable,
    required this.onOpenSettings,
  });

  final bool enabled;
  final bool statusKnown;
  final bool denied;
  final VoidCallback onEnable;
  final VoidCallback onOpenSettings;

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
          const Text(
            'Push notifications',
            style: TextStyle(
              color: AppColors.charcoal,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            !statusKnown
                ? 'Checking notification status...'
                : enabled
                ? 'Notifications are enabled for this device.'
                : 'Notifications are turned off for LocalLink on this device.',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: enabled || denied ? onOpenSettings : onEnable,
            icon: Icon(
              enabled || denied ? Icons.settings_outlined : Icons.notifications,
            ),
            label: Text(
              enabled
                  ? 'Device settings'
                  : denied
                  ? 'Open device settings'
                  : 'Enable alerts',
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.charcoal,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: enabled ? onChanged : null,
      title: Text(title),
      subtitle: Text(subtitle),
      activeThumbColor: AppColors.primary,
    );
  }
}
