import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AccountDeletionService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<void> reauthenticate(BuildContext context) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('You need to be signed in to delete your account.');
    }

    final providers = user.providerData.map((provider) => provider.providerId);

    if (providers.contains('password')) {
      final password = await _requestPassword(context);

      if (password == null || password.isEmpty) {
        throw Exception('Account deletion cancelled.');
      }

      final email = user.email;

      if (email == null || email.isEmpty) {
        throw Exception('No email address is available for re-authentication.');
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      await user.reauthenticateWithCredential(credential);
      return;
    }

    if (providers.contains('google.com')) {
      final googleUser = await GoogleSignIn().signIn();

      if (googleUser == null) {
        throw Exception('Google re-authentication was cancelled.');
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await user.reauthenticateWithCredential(credential);
      return;
    }

    if (providers.contains('apple.com')) {
      final provider = OAuthProvider('apple.com');
      await user.reauthenticateWithProvider(provider);
      return;
    }

    throw Exception(
      'Please sign out, sign back in, and try deleting your account again.',
    );
  }

  Future<void> deleteCurrentAccount() async {
    final callable = _functions.httpsCallable('deleteUserAccount');
    await callable.call();
  }

  Future<String?> _requestPassword(BuildContext context) async {
    final controller = TextEditingController();
    var obscurePassword = true;

    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Confirm your password'),
                content: TextField(
                  controller: controller,
                  obscureText: obscurePassword,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setDialogState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                      tooltip: obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        semanticLabel: obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: const Text('Continue'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }
}
