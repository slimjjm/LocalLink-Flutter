import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'config/stripe_config.dart';
import 'core/auth_gate.dart';
import 'widgets/release_compatibility_gate.dart';
import 'firebase_options.dart';
import 'screens/public_shared_item_screen.dart';
import 'screens/public_explore_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/email_action_screen.dart';
import 'screens/stripe_connect_return_screen.dart';
import 'services/deep_link_service.dart';
import 'services/notification_service.dart';
import 'services/startup_timeline.dart';
import 'theme/local_link_theme.dart';

import 'screens/inbox_screen.dart';
import 'screens/customer_bookings_screen.dart';
import 'screens/customer_booking_detail_screen.dart';
import 'screens/business_booking_detail_screen.dart';
import 'screens/booking_conversation_screen.dart';
import 'screens/claim_business_screen.dart';

// =====================================================
// BACKGROUND NOTIFICATION HANDLER
// =====================================================

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

// =====================================================
// MAIN
// =====================================================

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      StartupTimeline.start();
      StartupTimeline.log('main entered');
      WidgetsFlutterBinding.ensureInitialized();
      StartupTimeline.log('widgets binding initialized');

      // =====================================================
      // FIREBASE
      // =====================================================

      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        StartupTimeline.log('Firebase initialized');
      } catch (error) {
        StartupTimeline.log('Firebase initialization failed: $error');
        runApp(_StartupFailureApp(error: error));
        return;
      }

      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
        StartupTimeline.log('notification background handler registered');
        _configureCrashReporting();
      }

      // =====================================================
      // RUN APP
      // =====================================================

      StartupTimeline.log('runApp');
      runApp(const MyApp());

      WidgetsBinding.instance.addPostFrameCallback((_) {
        StartupTimeline.log('first Flutter frame');
        if (!kIsWeb) {
          unawaited(_initialiseOptionalNativeServices());
        }
      });
    },
    (error, stack) {
      StartupTimeline.log('uncaught startup zone error: $error');
      if (!kIsWeb && Firebase.apps.isNotEmpty) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
    },
  );
}

void _configureCrashReporting() {
  try {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    StartupTimeline.log('Crashlytics configured');
  } catch (error) {
    StartupTimeline.log('Crashlytics configuration skipped: $error');
  }
}

Future<void> _initialiseOptionalNativeServices() async {
  await Future.wait([
    _initialiseNotificationsSafely(),
    _configureStripeSafely(),
  ]);
}

Future<void> _initialiseNotificationsSafely() async {
  try {
    await NotificationService.shared.initialise().timeout(
      const Duration(seconds: 8),
    );
    StartupTimeline.log('notifications ready');
  } catch (error, stack) {
    StartupTimeline.log('notifications initialization skipped: $error');
    if (!kIsWeb && Firebase.apps.isNotEmpty) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
    }
  }
}

Future<void> _configureStripeSafely() async {
  try {
    final config = await configureStripeForApp();
    StartupTimeline.log(
      'Stripe configuration mode: ${config?.mode.name.toUpperCase() ?? 'MISSING'}',
    );
  } catch (error, stack) {
    StartupTimeline.log('Stripe configuration skipped: $error');
    if (!kIsWeb && Firebase.apps.isNotEmpty) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
    }
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline, size: 44),
                const SizedBox(height: 16),
                const Text(
                  'LocalLink could not start',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Please check your connection and try again.',
                  textAlign: TextAlign.center,
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 20),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================
// APP
// =====================================================

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        StartupTimeline.log('DeepLinkService initialise requested');
        DeepLinkService.shared.initialise(navigatorKey);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) =>
          ReleaseCompatibilityGate(child: child ?? const SizedBox.shrink()),

      debugShowCheckedModeBanner: false,
      theme: LocalLinkTheme.light,

      home: kIsWeb
          ? EmailActionScreen.fromUri(uri: Uri.base) ??
                StripeConnectReturnScreen.fromUri(uri: Uri.base) ??
                PublicSharedItemScreen.fromUri(uri: Uri.base) ??
                PublicExploreScreen.fromUri(uri: Uri.base) ??
                PublicCategoryLandingScreen.fromUri(uri: Uri.base) ??
                const AuthGate()
          : const AuthGate(),

      routes: {
        '/home': (_) => const AuthGate(),
        '/explore': (_) => const PublicExploreScreen(),

        '/claim-business': (_) => const ClaimBusinessScreen(),

        // =====================================================
        // INBOX
        // =====================================================
        '/inbox': (_) => const InboxScreen(currentRole: 'all'),

        // =====================================================
        // BOOKINGS
        // =====================================================
        '/bookings': (_) => const CustomerBookingsScreen(),

        '/booking-conversation': (context) {
          final rawArgs = ModalRoute.of(context)?.settings.arguments;

          if (rawArgs is! Map) {
            return const _RouteFallbackScreen(
              message: 'We could not open this conversation.',
            );
          }

          final conversationId = rawArgs['conversationId']?.toString().trim();
          final bookingId = rawArgs['bookingId']?.toString().trim();
          final viewerType = rawArgs['viewerType']?.toString().trim();
          final resolvedConversationId = conversationId?.isNotEmpty == true
              ? conversationId
              : bookingId;

          if (resolvedConversationId == null ||
              resolvedConversationId.isEmpty) {
            return const _RouteFallbackScreen(
              message: 'We could not open this conversation.',
            );
          }

          return BookingConversationScreen(
            conversationId: resolvedConversationId,
            bookingId: bookingId?.isNotEmpty == true ? bookingId : null,
            viewerType: viewerType?.isNotEmpty == true
                ? viewerType!
                : 'customer',
          );
        },

        // =====================================================
        // BOOKING DETAIL
        // =====================================================
        '/booking': (context) {
          final rawArgs = ModalRoute.of(context)?.settings.arguments;

          if (rawArgs is! Map) {
            return const _RouteFallbackScreen(
              message: 'We could not open this booking.',
            );
          }

          final bookingId = rawArgs['bookingId']?.toString().trim();

          if (bookingId == null || bookingId.isEmpty) {
            return const _RouteFallbackScreen(
              message: 'We could not open this booking.',
            );
          }

          final businessId = rawArgs['businessId']?.toString().trim();

          // If businessId exists,
          // assume business-side detail screen

          if (businessId?.isNotEmpty == true) {
            return BusinessBookingDetailScreen(bookingId: bookingId);
          }

          // Otherwise customer detail screen

          return CustomerBookingDetailScreen(bookingId: bookingId);
        },
      },
      onGenerateRoute: generateLocalLinkRoute,
      onUnknownRoute: unknownLocalLinkRoute,
    );
  }
}

@visibleForTesting
Uri? localLinkUriFromRouteName(String? routeName) {
  final name = routeName?.trim();
  if (name == null || name.isEmpty || name == Navigator.defaultRouteName) {
    return null;
  }

  final parsed = Uri.tryParse(name);
  if (parsed == null) return null;

  if (parsed.hasScheme) {
    return parsed;
  }

  if (!name.startsWith('/')) {
    return null;
  }

  return Uri.tryParse('https://locallinkapp.co.uk$name');
}

Route<dynamic>? generateLocalLinkRoute(RouteSettings settings) {
  final uri = localLinkUriFromRouteName(settings.name);
  if (uri == null) return null;

  final target = LocalLinkDeepLinkTarget.fromUri(uri);
  if (target == null) return null;

  return MaterialPageRoute(
    settings: settings,
    builder: (_) => kIsWeb
        ? EmailActionScreen.fromUri(uri: uri) ??
              StripeConnectReturnScreen.fromUri(uri: uri) ??
              PublicSharedItemScreen(target: target)
        : _DeepLinkStartupScreen(uri: uri, target: target),
  );
}

Route<dynamic> unknownLocalLinkRoute(RouteSettings settings) {
  return MaterialPageRoute(
    settings: settings,
    builder: (_) => const _RouteFallbackScreen(
      message: 'We could not open this LocalLink link.',
    ),
  );
}

class _DeepLinkStartupScreen extends StatefulWidget {
  const _DeepLinkStartupScreen({required this.uri, required this.target});

  final Uri uri;
  final LocalLinkDeepLinkTarget target;

  @override
  State<_DeepLinkStartupScreen> createState() => _DeepLinkStartupScreenState();
}

class _DeepLinkStartupScreenState extends State<_DeepLinkStartupScreen> {
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) return;

    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        DeepLinkService.shared.openRouteTargetOrQueue(
          context,
          widget.uri,
          widget.target,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const AuthGate();
  }
}

class _RouteFallbackScreen extends StatelessWidget {
  const _RouteFallbackScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
