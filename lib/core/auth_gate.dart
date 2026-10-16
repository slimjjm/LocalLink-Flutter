import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../screens/banned_account_screen.dart';
import '../screens/email_verification_screen.dart';
import '../screens/main_tab_shell_screen.dart';
import '../services/analytics_service.dart';
import '../services/deep_link_service.dart';
import '../services/startup_timeline.dart';
import '../services/uk_activity_periods.dart';

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
        LocalLinkAnalytics.instance.updateUserProperties(user: user);

        if (user != null) {
          return _AuthenticatedUserGate(user: user);
        }

        StartupTimeline.log('starting guest home session');
        return const _GuestHomeGate();
      },
    );
  }
}

class _GuestHomeGate extends StatefulWidget {
  const _GuestHomeGate();

  @override
  State<_GuestHomeGate> createState() => _GuestHomeGateState();
}

class _GuestHomeGateState extends State<_GuestHomeGate> {
  late final Future<void> _guestSignIn = _startGuestSession();

  Future<void> _startGuestSession() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return;
    await auth.signInAnonymously();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _guestSignIn,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'LocalLink could not start guest browsing. Please try again.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
    if (!widget.user.isAnonymous) {
      _recordActivity().catchError((_) {});
    }
  }

  Future<void> _recordActivity() async {
    final ids = UkActivityPeriods.periodIds();
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

  @override
  Widget build(BuildContext context) {
    if (widget.user.isAnonymous) {
      if (!_loggedHomeShown) {
        _loggedHomeShown = true;
        StartupTimeline.log('showing guest home');
      }
      return const MainTabShellScreen();
    }

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

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.user.uid)
              .collection('private')
              .doc('access')
              .snapshots(),
          builder: (context, accountSnapshot) {
            if (accountSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final accountData = accountSnapshot.data?.data();
            final isBanned = accountSnapshot.data?.exists == true
                ? (accountData?['isBanned'] == true)
                : (userData?['isBanned'] == true);
            if (isBanned) {
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
