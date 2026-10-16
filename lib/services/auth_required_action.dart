import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/login_screen.dart';

typedef AuthenticatedAction = Future<void> Function();

class AuthRequiredAction {
  const AuthRequiredAction._();

  static Future<bool> run(
    BuildContext context, {
    required AuthenticatedAction action,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      await action();
      return true;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          onAuthenticated: () async {
            await action();
          },
        ),
      ),
    );
    return false;
  }
}
