import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/local_link_design_tokens.dart';
import '../widgets/local_link_button.dart';
import '../widgets/local_link_states.dart';
import '../widgets/local_link_surface_card.dart';
import 'business_profile_screen.dart';
import 'login_screen.dart';

class StripeConnectReturnScreen extends StatefulWidget {
  const StripeConnectReturnScreen({
    super.key,
    required this.businessId,
    required this.isRefresh,
  });

  final String businessId;
  final bool isRefresh;

  static Widget? fromUri({required Uri uri}) {
    if (uri.host.isNotEmpty && uri.host != 'locallinkapp.co.uk') return null;

    final segments = uri.pathSegments
        .map(Uri.decodeComponent)
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();

    if (segments.length != 1 ||
        (segments.first != 'stripe-return' &&
            segments.first != 'stripe-refresh')) {
      return null;
    }

    final businessId = uri.queryParameters['businessId']?.trim() ?? '';
    if (businessId.isEmpty) return null;

    return StripeConnectReturnScreen(
      businessId: businessId,
      isRefresh: segments.first == 'stripe-refresh',
    );
  }

  @override
  State<StripeConnectReturnScreen> createState() =>
      _StripeConnectReturnScreenState();
}

class _StripeConnectReturnScreenState extends State<StripeConnectReturnScreen> {
  late final Future<_StripeRefreshResult> _refreshFuture = _refreshStatus();

  Future<_StripeRefreshResult> _refreshStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return const _StripeRefreshResult.signedOut();
    }

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('refreshStripeConnectionStatus')
          .call({'businessId': widget.businessId});
      final data = Map<String, dynamic>.from(result.data as Map);
      final connected = data['connected'] == true;
      final fullyEnabled = data['fullyEnabled'] == true;
      return _StripeRefreshResult(
        state: connected
            ? _StripeRefreshState.connected
            : _StripeRefreshState.incomplete,
        fullyEnabled: fullyEnabled,
      );
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('Stripe status refresh failed after return: $error');
        debugPrintStack(stackTrace: stack);
      }
      return const _StripeRefreshResult.failed();
    }
  }

  void _openBusinessPage() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessProfileScreen(businessId: widget.businessId),
      ),
    );
  }

  void _openSignIn() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _openNativeApp() async {
    final uri = Uri.parse(
      'https://locallinkapp.co.uk/stripe-return?businessId=${Uri.encodeQueryComponent(widget.businessId)}',
    );
    await launchUrl(uri, webOnlyWindowName: '_self');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Card payments'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(LocalLinkSpacing.lg),
              child: FutureBuilder<_StripeRefreshResult>(
                future: _refreshFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LocalLinkSurfaceCard(
                      child: LocalLinkLoadingState(
                        label: 'Checking your card payment setup...',
                      ),
                    );
                  }

                  final result =
                      snapshot.data ?? const _StripeRefreshResult.failed();

                  return LocalLinkSurfaceCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(result.icon, color: result.accent, size: 42),
                        const SizedBox(height: LocalLinkSpacing.md),
                        Text(
                          result.title,
                          style: LocalLinkTextStyles.sectionTitle,
                        ),
                        const SizedBox(height: LocalLinkSpacing.xs),
                        Text(
                          result.message,
                          style: LocalLinkTextStyles.secondary,
                        ),
                        const SizedBox(height: LocalLinkSpacing.lg),
                        if (kIsWeb &&
                            result.state == _StripeRefreshState.signedOut)
                          LocalLinkButton(
                            label: 'Open LocalLink app',
                            icon: Icons.phone_iphone_rounded,
                            onPressed: _openNativeApp,
                            expand: true,
                          )
                        else if (result.state == _StripeRefreshState.signedOut)
                          LocalLinkButton(
                            label: 'Sign in',
                            icon: Icons.login_rounded,
                            onPressed: _openSignIn,
                            expand: true,
                          )
                        else
                          LocalLinkButton(
                            label: 'Back to your Page',
                            icon: Icons.storefront_outlined,
                            onPressed: _openBusinessPage,
                            expand: true,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _StripeRefreshState { connected, incomplete, signedOut, failed }

class _StripeRefreshResult {
  const _StripeRefreshResult({required this.state, this.fullyEnabled = false});

  const _StripeRefreshResult.signedOut()
    : state = _StripeRefreshState.signedOut,
      fullyEnabled = false;

  const _StripeRefreshResult.failed()
    : state = _StripeRefreshState.failed,
      fullyEnabled = false;

  final _StripeRefreshState state;
  final bool fullyEnabled;

  IconData get icon {
    switch (state) {
      case _StripeRefreshState.connected:
        return Icons.check_circle_outline_rounded;
      case _StripeRefreshState.incomplete:
        return Icons.info_outline_rounded;
      case _StripeRefreshState.signedOut:
        return Icons.phone_iphone_rounded;
      case _StripeRefreshState.failed:
        return Icons.error_outline_rounded;
    }
  }

  Color get accent {
    switch (state) {
      case _StripeRefreshState.connected:
        return AppColors.serviceGreen;
      case _StripeRefreshState.incomplete:
      case _StripeRefreshState.signedOut:
        return AppColors.primary;
      case _StripeRefreshState.failed:
        return AppColors.error;
    }
  }

  String get title {
    switch (state) {
      case _StripeRefreshState.connected:
        return fullyEnabled
            ? 'Card payments are ready'
            : 'Stripe setup received';
      case _StripeRefreshState.incomplete:
        return 'Stripe setup is not finished';
      case _StripeRefreshState.signedOut:
        return 'Return to LocalLink';
      case _StripeRefreshState.failed:
        return 'We could not check Stripe yet';
    }
  }

  String get message {
    switch (state) {
      case _StripeRefreshState.connected:
        return fullyEnabled
            ? 'Stripe has confirmed that your Page can accept card payments.'
            : 'Stripe has received your details. LocalLink will show card payments as fully enabled once Stripe confirms your account can charge and pay out.';
      case _StripeRefreshState.incomplete:
        return 'Stripe has not confirmed your onboarding as complete yet. Open your Page to continue setup or check the latest status.';
      case _StripeRefreshState.signedOut:
        return 'Stripe has returned you to LocalLink. Open the app or sign in to refresh your Page status securely.';
      case _StripeRefreshState.failed:
        return 'Your Page has not been changed from this return link. Open your Page and try refreshing card payment setup again.';
    }
  }
}
