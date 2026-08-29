import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/notifications_screen.dart';
import '../screens/opportunity_detail_screen.dart';
import '../screens/post_service_request_screen.dart';
import '../screens/profile_screen.dart';

enum NotificationRouteKind {
  bookingConversation,
  booking,
  opportunity,
  profile,
  communityHelpPost,
  notifications,
  inbox,
  home,
}

class NotificationRouteTarget {
  const NotificationRouteTarget(this.kind, {this.arguments = const {}});

  final NotificationRouteKind kind;
  final Map<String, String> arguments;
}

class NotificationRouter {
  const NotificationRouter._();

  static NotificationRouteTarget resolve(Map<String, dynamic> data) {
    final type = _text(data['type'] ?? data['notificationType']);

    switch (type) {
      case 'community_help_response':
      case 'community_help_sighting':
      case 'community_help_message':
      case 'booking_message':
        final conversationId = _text(data['conversationId']);
        final bookingId = _text(data['bookingId']);
        final viewerType = _text(data['viewerType']);
        if (conversationId.isNotEmpty || bookingId.isNotEmpty) {
          return NotificationRouteTarget(
            NotificationRouteKind.bookingConversation,
            arguments: {
              'conversationId': conversationId.isNotEmpty
                  ? conversationId
                  : bookingId,
              'bookingId': bookingId,
              'viewerType': viewerType.isNotEmpty ? viewerType : 'customer',
            },
          );
        }
        final postId = _communityHelpPostId(data);
        if (postId.isNotEmpty) {
          return NotificationRouteTarget(
            NotificationRouteKind.communityHelpPost,
            arguments: {'postId': postId},
          );
        }
        return const NotificationRouteTarget(NotificationRouteKind.inbox);

      case 'new_booking':
      case 'last_minute_request':
      case 'booking_confirmed':
      case 'booking_cancelled':
      case 'booking_declined':
      case 'booking_expired':
      case 'payment_failed':
        final bookingId = _text(data['bookingId']);
        if (bookingId.isEmpty) {
          return const NotificationRouteTarget(NotificationRouteKind.home);
        }
        return NotificationRouteTarget(
          NotificationRouteKind.booking,
          arguments: {
            'bookingId': bookingId,
            'businessId': _text(data['businessId']),
          },
        );

      case 'follow':
      case 'review':
        final userId = _text(data['followerId'] ?? data['reviewerId']);
        if (userId.isEmpty) {
          return const NotificationRouteTarget(NotificationRouteKind.home);
        }
        return NotificationRouteTarget(
          NotificationRouteKind.profile,
          arguments: {'userId': userId},
        );

      case 'opportunity_join':
      case 'opportunity_comment':
      case 'opportunity_reminder':
        final opportunityId = _text(data['opportunityId']);
        if (opportunityId.isEmpty) {
          return const NotificationRouteTarget(
            NotificationRouteKind.notifications,
          );
        }
        return NotificationRouteTarget(
          NotificationRouteKind.opportunity,
          arguments: {'opportunityId': opportunityId},
        );

      case 'community_alert':
      case 'community_help_match':
      case 'community_help_update':
      case 'community_help_resolved':
      case 'community_help_expiry':
      case 'community_help_lookout':
        final postId = _communityHelpPostId(data);
        if (postId.isEmpty) {
          return const NotificationRouteTarget(
            NotificationRouteKind.communityHelpPost,
          );
        }
        return NotificationRouteTarget(
          NotificationRouteKind.communityHelpPost,
          arguments: {'postId': postId},
        );

      default:
        return const NotificationRouteTarget(NotificationRouteKind.home);
    }
  }

  static Future<void> routeFromData(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    await _route(Navigator.of(context), resolve(data));
  }

  static Future<void> routeFromNavigator(
    NavigatorState navigator,
    Map<String, dynamic> data,
  ) async {
    await _route(navigator, resolve(data));
  }

  static Future<void> _route(
    NavigatorState navigator,
    NotificationRouteTarget target,
  ) async {
    switch (target.kind) {
      case NotificationRouteKind.bookingConversation:
        await navigator.pushNamed(
          '/booking-conversation',
          arguments: target.arguments,
        );
        return;
      case NotificationRouteKind.booking:
        await navigator.pushNamed('/booking', arguments: target.arguments);
        return;
      case NotificationRouteKind.opportunity:
        await _openOpportunity(navigator, target);
        return;
      case NotificationRouteKind.profile:
        await _openProfile(navigator, target);
        return;
      case NotificationRouteKind.communityHelpPost:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => PostServiceRequestScreen(
              initialPostId: target.arguments['postId'],
            ),
          ),
        );
        return;
      case NotificationRouteKind.notifications:
        await navigator.push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
        return;
      case NotificationRouteKind.inbox:
        await navigator.pushNamed('/inbox');
        return;
      case NotificationRouteKind.home:
        await navigator.pushNamed('/home');
        return;
    }
  }

  static Future<void> _openOpportunity(
    NavigatorState navigator,
    NotificationRouteTarget target,
  ) async {
    final opportunityId = target.arguments['opportunityId'];
    if (opportunityId == null || opportunityId.isEmpty) {
      await navigator.push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      );
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('opportunities')
        .doc(opportunityId)
        .get();

    if (!doc.exists || doc.data() == null) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => const _MissingDestinationScreen(
            message: 'This activity is no longer available.',
          ),
        ),
      );
      return;
    }

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => OpportunityDetailScreen(
          opportunityId: opportunityId,
          opportunity: doc.data()!,
        ),
      ),
    );
  }

  static Future<void> _openProfile(
    NavigatorState navigator,
    NotificationRouteTarget target,
  ) async {
    final userId = target.arguments['userId'];
    if (userId == null || userId.isEmpty) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();

    if (!doc.exists || doc.data() == null) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => const _MissingDestinationScreen(
            message: 'This profile is no longer available.',
          ),
        ),
      );
      return;
    }

    final userData = doc.data()!;
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userId: userId,
          userName: userData['userName'] ?? 'User',
          photoUrl: userData['photoUrl'],
        ),
      ),
    );
  }

  static String _communityHelpPostId(Map<String, dynamic> data) {
    return _text(
      data['communityHelpPostId'] ?? data['postId'] ?? data['communityPostId'],
    );
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';
}

class _MissingDestinationScreen extends StatelessWidget {
  const _MissingDestinationScreen({required this.message});

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
