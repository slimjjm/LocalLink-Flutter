import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../screens/banned_account_screen.dart';
import '../screens/customer_home_screen.dart';
import '../screens/welcome_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user != null) {
          return _AuthenticatedUserGate(user: user);
        }

        return const WelcomeScreen();
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
  @override
  void initState() {
    super.initState();
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
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;

        if (userData?['isBanned'] == true) {
          return const BannedAccountScreen();
        }

        return const CustomerHomeScreen();
      },
    );
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
