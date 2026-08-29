import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key, required this.user});

  final User user;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _checking = false;
  bool _resending = false;
  String? _message;

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _message = null;
    });

    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _message = 'Verification email sent. Please check your inbox.';
      });
    } catch (error) {
      assert(() {
        debugPrint('Email verification resend failed: $error');
        return true;
      }());
      if (!mounted) return;
      setState(() {
        _message =
            'We could not send another email just now. Please try again soon.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _resending = false;
        });
      }
    }
  }

  Future<void> _checkAgain() async {
    setState(() {
      _checking = true;
      _message = null;
    });

    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final verified = FirebaseAuth.instance.currentUser?.emailVerified == true;

      if (!mounted) return;

      if (verified) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
        return;
      }

      setState(() {
        _message = 'Still waiting for verification. Tap the email link first.';
      });
    } catch (error) {
      assert(() {
        debugPrint('Email verification refresh failed: $error');
        return true;
      }());
      if (!mounted) return;
      setState(() {
        _message = 'We could not check that just now. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? widget.user.email;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Check your email',
                style: TextStyle(
                  color: AppColors.charcoal,
                  fontSize: 30,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                email == null || email.isEmpty
                    ? 'Please verify your email address to continue using LocalLink.'
                    : 'Please verify $email to continue using LocalLink.',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 16,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'This keeps local posts, bookings and messages tied to a real reachable account.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 18),
                Text(
                  _message!,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _checking ? null : _checkAgain,
                  child: Text(_checking ? 'Checking...' : 'I have verified'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _resending ? null : _resend,
                  child: Text(
                    _resending ? 'Sending...' : 'Resend verification email',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _signOut,
                  child: const Text('Sign out or use a different email'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
