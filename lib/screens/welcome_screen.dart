import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _createAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
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
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                height: 40,
                                child: Image.asset(
                                  'assets/images/locallink_logo.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: _continue,
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.textMuted,
                                  minimumSize: const Size(64, 44),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                child: const Text(
                                  'Sign in',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 34),

                          SizedBox(
                            height: 132,
                            child: Image.asset(
                              'assets/images/locallink_logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),

                          const SizedBox(height: 34),

                          const Text(
                            'Discover what is happening nearby.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.charcoal,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              height: 1.08,
                            ),
                          ),

                          const SizedBox(height: 16),

                          const Text(
                            'Local activities, services, availability and Community Help in one trusted place.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                            ),
                          ),

                          const SizedBox(height: 28),

                          const _PublicSignals(),

                          const SizedBox(height: 34),

                          _PrimaryLandingAction(onPressed: _createAccount),

                          const SizedBox(height: 10),

                          TextButton(
                            onPressed: _continue,
                            child: const Text('I already have an account'),
                          ),

                          const SizedBox(height: 22),

                          const _PublicPageLinks(),
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

class _PrimaryLandingAction extends StatelessWidget {
  const _PrimaryLandingAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.buttonPrimary,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.buttonPrimary,
            foregroundColor: AppColors.buttonText,
            elevation: 0,
            shadowColor: AppColors.shadow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Create your account',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, size: 21),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicSignals extends StatelessWidget {
  const _PublicSignals();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        _SignalChip(icon: Icons.event_available_outlined, label: 'Activities'),
        _SignalChip(icon: Icons.handshake_outlined, label: 'Services'),
        _SignalChip(
          icon: Icons.volunteer_activism_outlined,
          label: 'Community Help',
        ),
      ],
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicPageLinks extends StatelessWidget {
  const _PublicPageLinks();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 8,
      children: [
        _FooterLink(label: 'Privacy', path: '/privacy'),
        _FooterLink(label: 'Terms', path: '/terms'),
        _FooterLink(label: 'Contact', path: '/contact'),
        _FooterLink(label: 'Delete account', path: '/delete-account'),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.path});

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        launchUrl(Uri(path: path), webOnlyWindowName: '_self');
      },
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textLight,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}
