import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../screens/banned_account_screen.dart';
import '../screens/email_verification_screen.dart';
import '../screens/login_screen.dart';
import '../screens/main_tab_shell_screen.dart';
import '../screens/welcome_screen.dart';
import '../services/deep_link_service.dart';
import '../services/startup_timeline.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    StartupTimeline.log('AuthGate started');
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          StartupTimeline.log('auth user waiting');
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        StartupTimeline.log(
          'auth user resolved: ${user == null ? 'signed_out' : 'signed_in'}',
        );

        if (user != null) {
          return _AuthenticatedUserGate(user: user);
        }

        StartupTimeline.log(
          kIsWeb ? 'showing public welcome' : 'showing login',
        );
        return kIsWeb ? const WelcomeScreen() : const LoginScreen();
      },
    );
  }
}

class _AuthenticatedUserGate extends StatefulWidget {
  final User user;

  const _AuthenticatedUserGate({required this.user});

  @override
  State<_AuthenticatedUserGate> createState() => _AuthenticatedUserGateState();
}

class _AuthenticatedUserGateState extends State<_AuthenticatedUserGate> {
  bool _openedPendingDeepLink = false;
  bool _loggedProfileResolved = false;
  bool _loggedHomeShown = false;

  @override
  void initState() {
    super.initState();
    StartupTimeline.log('AuthenticatedUserGate started');
    _recordActivity().catchError((_) {});
  }

  Future<void> _recordActivity() async {
    final ids = _periodIds();
    final firestore = FirebaseFirestore.instance;
    final payload = {
      'uid': widget.user.uid,
      'recordedAt': FieldValue.serverTimestamp(),
    };

    await Future.wait([
      firestore
          .collection('activityDaily')
          .doc(ids.day)
          .collection('users')
          .doc(widget.user.uid)
          .set(payload, SetOptions(merge: true)),
      firestore
          .collection('activityWeekly')
          .doc(ids.week)
          .collection('users')
          .doc(widget.user.uid)
          .set(payload, SetOptions(merge: true)),
      firestore
          .collection('activityMonthly')
          .doc(ids.month)
          .collection('users')
          .doc(widget.user.uid)
          .set(payload, SetOptions(merge: true)),
    ]);
  }

  _PeriodIds _periodIds() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final firstDay = DateTime(now.year, 1, 1);
    final today = DateTime(now.year, now.month, now.day);
    final pastDays = today.difference(firstDay).inDays;
    final week = ((pastDays + firstDay.weekday) / 7).ceil().toString().padLeft(
      2,
      '0',
    );

    return _PeriodIds(
      day: '${now.year}-$month-$day',
      week: '${now.year}-W$week',
      month: '${now.year}-$month',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_requiresEmailVerification(widget.user)) {
      StartupTimeline.log('showing email verification');
      return EmailVerificationScreen(user: widget.user);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          StartupTimeline.log('profile waiting');
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        if (_loggedProfileResolved) {
          StartupTimeline.log('profile updated');
        } else {
          _loggedProfileResolved = true;
          StartupTimeline.log('profile resolved');
        }

        if (userData?['isBanned'] == true) {
          StartupTimeline.log('showing banned account');
          return const BannedAccountScreen();
        }

        _openPendingDeepLinkAfterGate();

        if (!_loggedHomeShown) {
          _loggedHomeShown = true;
          StartupTimeline.log('showing home');
        }
        return const MainTabShellScreen();
      },
    );
  }

  void _openPendingDeepLinkAfterGate() {
    if (_openedPendingDeepLink) return;

    _openedPendingDeepLink = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        DeepLinkService.shared.openPendingTarget(context);
      }
    });
  }

  bool _requiresEmailVerification(User user) {
    if (user.isAnonymous || user.emailVerified) {
      return false;
    }

    final providerIds = user.providerData
        .map((provider) => provider.providerId)
        .toSet();

    return providerIds.contains('password') &&
        !providerIds.contains('google.com') &&
        !providerIds.contains('apple.com');
  }
}

class _PeriodIds {
  final String day;
  final String week;
  final String month;

  const _PeriodIds({
    required this.day,
    required this.week,
    required this.month,
  });
}
