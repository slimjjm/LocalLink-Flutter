import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/email_action_route.dart';
import '../theme/app_colors.dart';

class EmailActionScreen extends StatefulWidget {
  const EmailActionScreen({super.key, required this.route});

  final EmailActionRoute route;

  static Widget? fromUri({required Uri uri}) {
    final route = EmailActionRoute.fromUri(uri);
    if (route == null) return null;
    return EmailActionScreen(route: route);
  }

  @override
  State<EmailActionScreen> createState() => _EmailActionScreenState();
}

class _EmailActionScreenState extends State<EmailActionScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _loading = true;
  bool _success = false;
  bool _submittingPassword = false;
  String _title = 'Verifying your email';
  String _message = 'Please wait while LocalLink confirms your email address.';
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    if (widget.route.isPasswordResetMode) {
      _verifyPasswordResetCode();
    } else {
      _applyActionCode();
    }
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _applyActionCode() async {
    if (!widget.route.isEmailVerification) {
      setState(() {
        _loading = false;
        _success = false;
        _title = 'Verification link problem';
        _message =
            'This email verification link is missing information. Please request a new verification email from LocalLink.';
      });
      return;
    }

    try {
      assert(() {
        debugPrint(
          '[Email verification] applying action code. mode=${widget.route.mode} hasCode=${widget.route.oobCode.isNotEmpty}',
        );
        return true;
      }());

      await FirebaseAuth.instance.applyActionCode(widget.route.oobCode);
      await FirebaseAuth.instance.currentUser?.reload();

      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
        _title = 'Email verified successfully';
        _message =
            'Your email address is verified. You can now return to LocalLink and continue.';
      });
    } on FirebaseAuthException catch (error, stackTrace) {
      assert(() {
        debugPrint(
          '[Email verification] FirebaseAuthException.code: ${error.code}',
        );
        debugPrint(
          '[Email verification] FirebaseAuthException.message: ${error.message}',
        );
        debugPrint('[Email verification] stack trace: $stackTrace');
        return true;
      }());

      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _title = _titleForAuthError(error.code);
        _message = _messageForAuthError(error.code);
      });
    } catch (error, stackTrace) {
      assert(() {
        debugPrint('[Email verification] failed: $error');
        debugPrint('[Email verification] stack trace: $stackTrace');
        return true;
      }());

      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _title = 'Email could not be verified';
        _message =
            'Something went wrong while checking this link. Please request a new verification email from LocalLink.';
      });
    }
  }

  String _titleForAuthError(String code) {
    switch (code) {
      case 'expired-action-code':
        return 'Verification link expired';
      case 'invalid-action-code':
        return 'Verification link already used or invalid';
      case 'user-disabled':
        return 'Account disabled';
      case 'user-not-found':
        return 'Account not found';
      default:
        return 'Email could not be verified';
    }
  }

  String _messageForAuthError(String code) {
    switch (code) {
      case 'expired-action-code':
        return 'This verification link has expired. Please return to LocalLink and request a new verification email.';
      case 'invalid-action-code':
        return 'This verification link is invalid or has already been used. If your app still asks you to verify, request a new email from LocalLink.';
      case 'user-disabled':
        return 'This LocalLink account is disabled. Please contact support if you think this is wrong.';
      case 'user-not-found':
        return 'We could not find the account for this verification link. Please check you used the latest email from LocalLink.';
      default:
        return 'Please return to LocalLink and request a new verification email.';
    }
  }

  Future<void> _verifyPasswordResetCode() async {
    if (!widget.route.isPasswordReset) {
      setState(() {
        _loading = false;
        _success = false;
        _title = 'Reset link problem';
        _message =
            'This password reset link is missing information. Please request a new password reset email from LocalLink.';
      });
      return;
    }

    try {
      await FirebaseAuth.instance.verifyPasswordResetCode(widget.route.oobCode);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _title = 'Choose a new password';
        _message = 'Enter a new password for your LocalLink account.';
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _title = _titleForResetError(error.code);
        _message = _messageForResetError(error.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _title = 'Reset link problem';
        _message =
            'Something went wrong while checking this link. Please request a new password reset email from LocalLink.';
      });
    }
  }

  Future<void> _confirmPasswordReset() async {
    final password = _newPasswordController.text;
    final confirmation = _confirmPasswordController.text;

    if (password.length < 6) {
      setState(() => _passwordError = 'Use at least 6 characters.');
      return;
    }

    if (password != confirmation) {
      setState(() => _passwordError = 'Passwords do not match.');
      return;
    }

    setState(() {
      _submittingPassword = true;
      _passwordError = null;
    });

    try {
      await FirebaseAuth.instance.confirmPasswordReset(
        code: widget.route.oobCode,
        newPassword: password,
      );
      if (!mounted) return;
      setState(() {
        _submittingPassword = false;
        _success = true;
        _title = 'Password changed successfully';
        _message = 'You can now return to LocalLink and log in normally.';
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _submittingPassword = false;
        _passwordError = _passwordMessageForSubmitError(error.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submittingPassword = false;
        _passwordError =
            'We could not change your password just now. Please check your connection and try again.';
      });
    }
  }

  String _titleForResetError(String code) {
    switch (code) {
      case 'expired-action-code':
        return 'Reset link expired';
      case 'invalid-action-code':
        return 'Reset link already used or invalid';
      default:
        return 'Reset link problem';
    }
  }

  String _messageForResetError(String code) {
    switch (code) {
      case 'expired-action-code':
        return 'This password reset link has expired. Please return to LocalLink and request a new one.';
      case 'invalid-action-code':
        return 'This password reset link is invalid or has already been used. Please request a new one from LocalLink.';
      default:
        return 'Please return to LocalLink and request a new password reset email.';
    }
  }

  String _passwordMessageForSubmitError(String code) {
    switch (code) {
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'expired-action-code':
        return 'This reset link has expired. Please request a new one.';
      case 'invalid-action-code':
        return 'This reset link is invalid or has already been used.';
      default:
        return 'We could not change your password just now. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    _loading
                        ? Icons.mark_email_unread_outlined
                        : _success
                        ? Icons.verified_outlined
                        : Icons.error_outline,
                    size: 52,
                    color: _success ? Colors.green.shade700 : AppColors.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.charcoal,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 16,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (!_loading &&
                      widget.route.isPasswordReset &&
                      !_success &&
                      _title == 'Choose a new password') ...[
                    const SizedBox(height: 24),
                    TextField(
                      controller: _newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      onSubmitted: (_) {
                        if (!_submittingPassword) _confirmPasswordReset();
                      },
                      decoration: InputDecoration(
                        labelText: 'Confirm password',
                        border: const OutlineInputBorder(),
                        errorText: _passwordError,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _submittingPassword
                          ? null
                          : _confirmPasswordReset,
                      child: _submittingPassword
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Change password'),
                    ),
                  ],
                  if (!_loading &&
                      (!widget.route.isPasswordReset ||
                          _success ||
                          _title != 'Choose a new password')) ...[
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/home',
                          (_) => false,
                        );
                      },
                      child: const Text('Continue to LocalLink'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
