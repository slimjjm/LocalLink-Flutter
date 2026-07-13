import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/founder_dashboard_screen.dart';
import '../screens/admin_reports_screen.dart';
import '../services/account_deletion_service.dart';
import '../services/admin_access_service.dart';
import '../theme/app_colors.dart';
import 'settings_tile.dart';

import 'local_link_surface_card.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();

    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Permanently delete account?"),
        content: const Text(
          "This is permanent. Your personal information will be removed, your account will be anonymised, and you will not be able to log in again with this account.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      final deletionService = AccountDeletionService();

      await deletionService.reauthenticate(context);
      await deletionService.deleteCurrentAccount();

      if (context.mounted) {
        Navigator.pop(context);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Account deleted.")));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: LocalLinkSheetHandle()),
            const SizedBox(height: 22),
            const Text(
              'Settings',
              style: TextStyle(
                color: AppColors.charcoal,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Manage how LocalLink works for you.',
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 18),
            SettingsTile(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Manage your alerts',
              onTap: () {},
            ),
            SettingsTile(
              icon: Icons.location_on_outlined,
              title: 'Location',
              subtitle: 'Location permissions',
              onTap: () {},
            ),
            SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              subtitle: 'Read our privacy policy',
              onTap: () => _openUrl('https://locallinkapp.co.uk/privacy'),
            ),
            SettingsTile(
              icon: Icons.article_outlined,
              title: 'Terms',
              subtitle: 'Terms of service',
              onTap: () => _openUrl('https://locallinkapp.co.uk/terms'),
            ),
            SettingsTile(
              icon: Icons.support_agent_outlined,
              title: 'Support',
              subtitle: 'Contact LocalLink',
              onTap: () => _openUrl('mailto:support@locallinkapp.co.uk'),
            ),
            FutureBuilder<bool>(
              future: AdminAccessService().isCurrentUserAdmin(),
              builder: (context, snapshot) {
                if (snapshot.data != true) {
                  return const SizedBox.shrink();
                }

                return SettingsTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Moderation',
                  subtitle: 'Review reports and safety actions',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminReportsScreen(),
                      ),
                    );
                  },
                );
              },
            ),
            FutureBuilder<bool>(
              future: AdminAccessService().isCurrentUserAdmin(),
              builder: (context, snapshot) {
                if (snapshot.data != true) {
                  return const SizedBox.shrink();
                }

                return SettingsTile(
                  icon: Icons.analytics_outlined,
                  title: 'Founder Dashboard',
                  subtitle: 'Analytics, growth and community health',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FounderDashboardScreen(),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Log out'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: AppColors.charcoal,
                side: BorderSide(
                  color: AppColors.charcoal.withValues(alpha: 0.14),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: () => _logout(context),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete account'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: AppColors.error,
                side: BorderSide(
                  color: AppColors.error.withValues(alpha: 0.36),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: () => _deleteAccount(context),
            ),
          ],
        ),
      ),
    );
  }
}
