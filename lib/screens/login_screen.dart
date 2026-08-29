import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final authService = AuthService();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;

  String? error;

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

    _slide = Tween<Offset>(
      begin: const Offset(0, .025),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  Future<void> login() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });

      await authService.login(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (!mounted) return;

      Navigator.pushReplacementNamed(context, '/');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error =
            'We could not sign you in. Please check your details and try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      setState(() {
        error = null;
      });

      await authService.signInWithGoogle();

      if (!mounted) return;

      Navigator.pushReplacementNamed(context, '/');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Google sign-in could not be completed. Please try again.';
      });
    }
  }

  Future<void> signInWithApple() async {
    try {
      setState(() {
        error = null;
      });

      await authService.signInWithApple();

      if (!mounted) return;

      Navigator.pushReplacementNamed(context, '/');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Apple sign-in could not be completed. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 26),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),

                          const _LogoHero(),

                          const SizedBox(height: 24),

                          const Text(
                            'Welcome back',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.charcoal,
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.2,
                              height: 1.02,
                            ),
                          ),

                          const SizedBox(height: 10),

                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 18),
                            child: Text(
                              "Sign in to discover what's happening nearby.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                height: 1.42,
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          _LoginCard(
                            emailController: emailController,
                            passwordController: passwordController,
                            obscurePassword: obscurePassword,
                            isLoading: isLoading,
                            error: error,
                            onPasswordVisibilityChanged: () {
                              setState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                            onPasswordSubmitted: () {
                              if (!isLoading) login();
                            },
                            onSignIn: login,
                            onSignInWithApple: signInWithApple,
                            onSignInWithGoogle: signInWithGoogle,
                          ),

                          const SizedBox(height: 18),

                          _CreateAccountPrompt(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration _premiumInputDecoration({
  required String hint,
  required IconData icon,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      color: AppColors.textLight,
      fontSize: 15.5,
      fontWeight: FontWeight.w500,
    ),
    prefixIcon: Padding(
      padding: const EdgeInsets.only(left: 18, right: 12),
      child: Icon(icon, color: AppColors.textMuted, size: 21),
    ),
    prefixIconConstraints: const BoxConstraints(minWidth: 52, minHeight: 58),
    suffixIcon: suffix,
    filled: true,
    fillColor: AppColors.background,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.error, width: 1.2),
    ),
  );
}

class _LogoHero extends StatelessWidget {
  const _LogoHero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 218,
            height: 218,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withOpacity(.16),
                  AppColors.primary.withOpacity(.06),
                  AppColors.background.withOpacity(0),
                ],
                stops: const [.0, .42, 1],
              ),
            ),
          ),
          Container(
            width: 202,
            height: 202,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(.08),
                  blurRadius: 44,
                  offset: const Offset(0, 22),
                ),
              ],
            ),
            child: Image.asset(
              'assets/images/locallink_logo.png',
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool isLoading;
  final String? error;
  final VoidCallback onPasswordVisibilityChanged;
  final VoidCallback onPasswordSubmitted;
  final VoidCallback onSignIn;
  final VoidCallback onSignInWithApple;
  final VoidCallback onSignInWithGoogle;

  const _LoginCard({
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.isLoading,
    required this.error,
    required this.onPasswordVisibilityChanged,
    required this.onPasswordSubmitted,
    required this.onSignIn,
    required this.onSignInWithApple,
    required this.onSignInWithGoogle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(.82),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.card.withOpacity(.7)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withOpacity(.7),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: emailController,
            cursorColor: AppColors.primary,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: _premiumInputDecoration(
              hint: 'Email address',
              icon: Icons.mail_outline_rounded,
            ),
          ),

          const SizedBox(height: 14),

          TextField(
            controller: passwordController,
            cursorColor: AppColors.primary,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              onPasswordSubmitted();
            },
            decoration: _premiumInputDecoration(
              hint: 'Password',
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                onPressed: onPasswordVisibilityChanged,
                tooltip: obscurePassword ? 'Show password' : 'Hide password',
                color: AppColors.textMuted,
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  semanticLabel: obscurePassword
                      ? 'Show password'
                      : 'Hide password',
                  size: 21,
                ),
              ),
            ),
          ),

          if (error != null) ...[
            const SizedBox(height: 16),
            _ErrorBox(message: error!),
          ],

          const SizedBox(height: 20),

          _PrimaryButton(isLoading: isLoading, onPressed: onSignIn),

          const SizedBox(height: 22),

          const _DividerLabel(),

          const SizedBox(height: 18),

          _SocialButton(
            icon: Icons.apple,
            label: 'Continue with Apple',
            onPressed: onSignInWithApple,
          ),

          const SizedBox(height: 12),

          _SocialButton(
            icon: Icons.g_mobiledata_rounded,
            label: 'Continue with Google',
            iconSize: 34,
            onPressed: onSignInWithGoogle,
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const _PrimaryButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(isLoading ? 0 : .2),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.buttonText,
          disabledBackgroundColor: AppColors.disabled,
          disabledForegroundColor: AppColors.textMuted,
          elevation: 0,
          shadowColor: AppColors.shadow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                isLoading
                    ? AppColors.disabled
                    : AppColors.primary.withOpacity(.94),
                isLoading ? AppColors.disabled : AppColors.primary,
              ],
            ),
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.buttonText,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .1,
                          height: 1,
                        ),
                      ),
                      SizedBox(width: 9),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 21,
                        color: AppColors.buttonText,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: AppColors.divider)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.divider)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final double iconSize;
  final VoidCallback onPressed;

  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconSize = 26,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize, color: AppColors.charcoal),
        label: Text(
          label,
          style: const TextStyle(
            color: AppColors.charcoal,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          backgroundColor: AppColors.card,
          foregroundColor: AppColors.charcoal,
          side: const BorderSide(color: AppColors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(19),
          ),
        ),
      ),
    );
  }
}

class _CreateAccountPrompt extends StatelessWidget {
  final VoidCallback onPressed;

  const _CreateAccountPrompt({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        children: [
          const Text(
            'New here?',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              minimumSize: const Size(0, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Create your account',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withOpacity(.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
