import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/availability_detail_screen.dart';
import '../screens/business_detail_screen.dart';
import '../screens/opportunity_detail_screen.dart';
import '../screens/post_service_request_screen.dart';

class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService shared = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  LocalLinkDeepLinkTarget? _pendingTarget;
  Uri? _lastOpenedUri;
  DateTime? _lastOpenedAt;
  bool _started = false;

  Future<void> initialise(GlobalKey<NavigatorState> navigatorKey) async {
    if (_started) return;
    _started = true;

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        unawaited(_openUri(navigatorKey, initialUri));
      }
    } catch (_) {
      // A failed initial link should never block app launch.
    }

    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(_openUri(navigatorKey, uri)),
      onError: (_) {},
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }

  Future<void> _openUri(GlobalKey<NavigatorState> navigatorKey, Uri uri) async {
    if (_isDuplicate(uri)) return;

    final navigator = navigatorKey.currentState;
    final target = LocalLinkDeepLinkTarget.fromUri(uri);
    if (target == null) return;

    if (FirebaseAuth.instance.currentUser == null || navigator == null) {
      _pendingTarget = target;
      return;
    }

    await _openTarget(navigator, target);
  }

  bool _isDuplicate(Uri uri) {
    final now = DateTime.now();
    final previousUri = _lastOpenedUri;
    final previousOpenedAt = _lastOpenedAt;

    if (previousUri != null &&
        previousOpenedAt != null &&
        previousUri.toString() == uri.toString() &&
        now.difference(previousOpenedAt) < const Duration(seconds: 2)) {
      return true;
    }

    _lastOpenedUri = uri;
    _lastOpenedAt = now;
    return false;
  }

  Future<void> openPendingTarget(BuildContext context) async {
    final target = _pendingTarget;
    if (target == null) return;

    _pendingTarget = null;
    await _openTarget(Navigator.of(context), target);
  }

  Future<void> _openTarget(
    NavigatorState navigator,
    LocalLinkDeepLinkTarget target,
  ) async {
    switch (target.type) {
      case LocalLinkDeepLinkType.communityHelp:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => PostServiceRequestScreen(initialPostId: target.id),
          ),
        );
        return;
      case LocalLinkDeepLinkType.opportunity:
        await _openOpportunity(navigator, target.id);
        return;
      case LocalLinkDeepLinkType.availability:
        await _openAvailability(navigator, target.id);
        return;
      case LocalLinkDeepLinkType.business:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => BusinessDetailScreen(businessId: target.id),
          ),
        );
        return;
      case LocalLinkDeepLinkType.service:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => BusinessDetailScreen(
              businessId: target.parentId,
              initialServiceId: target.id,
            ),
          ),
        );
        return;
    }
  }

  Future<void> _openOpportunity(NavigatorState navigator, String id) async {
    final doc = await FirebaseFirestore.instance
        .collection('opportunities')
        .doc(id)
        .get();
    if (!doc.exists || doc.data() == null) {
      await _showMissing(navigator, 'This activity is no longer available.');
      return;
    }

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => OpportunityDetailScreen(
          opportunityId: id,
          opportunity: doc.data()!,
        ),
      ),
    );
  }

  Future<void> _openAvailability(NavigatorState navigator, String id) async {
    final doc = await FirebaseFirestore.instance
        .collection('availabilityPosts')
        .doc(id)
        .get();
    final data = doc.data();
    if (!doc.exists || data == null) {
      await _showMissing(navigator, 'This available time is no longer live.');
      return;
    }

    final businessId = data['businessId']?.toString().trim() ?? '';
    Map<String, dynamic> businessData = {};
    if (businessId.isNotEmpty) {
      final businessDoc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .get();
      businessData = businessDoc.data() ?? {};
    }

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => AvailabilityDetailScreen(
          postId: id,
          availabilityData: data,
          businessData: businessData,
        ),
      ),
    );
  }

  Future<void> _showMissing(NavigatorState navigator, String message) async {
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => _MissingSharedItemScreen(message: message),
      ),
    );
  }
}

enum LocalLinkDeepLinkType {
  communityHelp,
  opportunity,
  availability,
  business,
  service,
}

class LocalLinkDeepLinkTarget {
  const LocalLinkDeepLinkTarget({
    required this.type,
    required this.id,
    this.parentId = '',
  });

  final LocalLinkDeepLinkType type;
  final String id;
  final String parentId;

  static LocalLinkDeepLinkTarget? fromUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments
        .map(Uri.decodeComponent)
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();

    if (uri.scheme == 'locallink') {
      return _fromCustomScheme(host, segments, uri.queryParameters);
    }

    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        host == 'locallinkapp.co.uk') {
      return _fromPathSegments(segments);
    }

    return null;
  }

  static LocalLinkDeepLinkTarget? _fromCustomScheme(
    String host,
    List<String> segments,
    Map<String, String> queryParameters,
  ) {
    if (host == 'community-help' && segments.isNotEmpty) {
      return LocalLinkDeepLinkTarget(
        type: LocalLinkDeepLinkType.communityHelp,
        id: segments.first,
      );
    }
    if (host == 'opportunity' && segments.isNotEmpty) {
      return LocalLinkDeepLinkTarget(
        type: LocalLinkDeepLinkType.opportunity,
        id: segments.first,
      );
    }
    if (host == 'availability' && segments.isNotEmpty) {
      return LocalLinkDeepLinkTarget(
        type: LocalLinkDeepLinkType.availability,
        id: segments.first,
      );
    }
    if (host == 'business' && segments.isNotEmpty) {
      final serviceId = queryParameters['serviceId']?.trim();
      if (serviceId != null && serviceId.isNotEmpty) {
        return LocalLinkDeepLinkTarget(
          type: LocalLinkDeepLinkType.service,
          parentId: segments.first,
          id: serviceId,
        );
      }

      return LocalLinkDeepLinkTarget(
        type: LocalLinkDeepLinkType.business,
        id: segments.first,
      );
    }
    return null;
  }

  static LocalLinkDeepLinkTarget? _fromPathSegments(List<String> segments) {
    if (segments.length >= 2 && segments.first == 'community-help') {
      return LocalLinkDeepLinkTarget(
        type: LocalLinkDeepLinkType.communityHelp,
        id: segments[1],
      );
    }
    if (segments.length >= 2 && segments.first == 'opportunities') {
      return LocalLinkDeepLinkTarget(
        type: LocalLinkDeepLinkType.opportunity,
        id: segments[1],
      );
    }
    if (segments.length >= 2 && segments.first == 'availability') {
      return LocalLinkDeepLinkTarget(
        type: LocalLinkDeepLinkType.availability,
        id: segments[1],
      );
    }
    if (segments.length >= 2 && segments.first == 'businesses') {
      return LocalLinkDeepLinkTarget(
        type: LocalLinkDeepLinkType.business,
        id: segments[1],
      );
    }
    if (segments.length >= 3 && segments.first == 'services') {
      return LocalLinkDeepLinkTarget(
        type: LocalLinkDeepLinkType.service,
        parentId: segments[1],
        id: segments[2],
      );
    }
    return null;
  }
}

class _MissingSharedItemScreen extends StatelessWidget {
  const _MissingSharedItemScreen({required this.message});

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
