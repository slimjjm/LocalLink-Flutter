import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/notifications_screen.dart';
import '../screens/opportunity_detail_screen.dart';
import '../screens/post_service_request_screen.dart';
import '../screens/business_service_requests_screen.dart';
import '../screens/customer_service_request_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/business_detail_screen.dart';
import '../screens/business_services_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'business_activation_policy.dart';
import '../screens/moderator_populate_area_screen.dart';
import '../screens/organisation_detail_screen.dart';

enum NotificationRouteKind {
  bookingConversation,
  booking,
  opportunity,
  profile,
  communityHelpPost,
  business,
  businessServiceSetup,
  organisation,
  serviceRequest,
  businessServiceRequests,
  notifications,
  inbox,
  moderation,
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
      case 'business_service_setup':
        final id = _text(data['businessId']);
        if (id.isEmpty || id.contains('/')) {
          return const NotificationRouteTarget(
            NotificationRouteKind.notifications,
          );
        }
        return NotificationRouteTarget(
          NotificationRouteKind.businessServiceSetup,
          arguments: {'businessId': id},
        );

      case 'community_help_response':
      case 'community_help_sighting':
      case 'community_help_message':
      case 'booking_message':
      case 'service_enquiry':
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
              'viewerType': viewerType.isNotEmpty
                  ? viewerType
                  : (type == 'service_enquiry' ? 'business' : 'customer'),
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
            'businessId': _bookingBusinessIdForViewer(data),
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
      case 'opportunity_reminder_24h':
      case 'opportunity_reminder_1h':
      case 'opportunity_follow_request':
      case 'opportunity_follow_review':
      case 'opportunity_announcement':
        final opportunityId = _text(data['opportunityId']);
        if (opportunityId.isEmpty) {
          return const NotificationRouteTarget(
            NotificationRouteKind.notifications,
          );
        }
        final commentId = _text(data['commentId']);
        final entryId = _text(data['entryId']);
        return NotificationRouteTarget(
          NotificationRouteKind.opportunity,
          arguments: {
            'opportunityId': opportunityId,
            if (commentId.isNotEmpty) 'commentId': commentId,
            if (entryId.isNotEmpty) 'entryId': entryId,
          },
        );

      case 'organisation_announcement':
      case 'organisation_invitation_accepted':
        final organisationId = _text(data['organisationId']);
        if (organisationId.isEmpty) {
          return const NotificationRouteTarget(
            NotificationRouteKind.notifications,
          );
        }
        return NotificationRouteTarget(
          NotificationRouteKind.organisation,
          arguments: {'organisationId': organisationId},
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

      case 'community_alert_group':
        return const NotificationRouteTarget(
          NotificationRouteKind.communityHelpPost,
          arguments: {'section': 'nearby'},
        );

      case 'listing_claim':
        final listingType = _text(data['listingType']);
        final listingId = _text(data['listingId']);
        if (listingId.isEmpty) {
          return const NotificationRouteTarget(NotificationRouteKind.home);
        }
        if (listingType == 'business') {
          return NotificationRouteTarget(
            NotificationRouteKind.business,
            arguments: {'businessId': listingId},
          );
        }
        if (listingType == 'organisation') {
          return NotificationRouteTarget(
            NotificationRouteKind.organisation,
            arguments: {'organisationId': listingId},
          );
        }
        return NotificationRouteTarget(
          NotificationRouteKind.opportunity,
          arguments: {'opportunityId': listingId},
        );

      case 'service_request_match':
        final businessId = _text(data['businessId']);
        if (businessId.isEmpty) {
          return const NotificationRouteTarget(NotificationRouteKind.home);
        }
        return NotificationRouteTarget(
          NotificationRouteKind.businessServiceRequests,
          arguments: {
            'businessId': businessId,
            'serviceRequestId': _text(data['serviceRequestId']),
          },
        );

      case 'service_request_offer':
        final requestId = _text(data['serviceRequestId'] ?? data['requestId']);
        if (requestId.isEmpty) {
          return const NotificationRouteTarget(NotificationRouteKind.home);
        }
        return NotificationRouteTarget(
          NotificationRouteKind.serviceRequest,
          arguments: {'serviceRequestId': requestId},
        );

      case 'moderation_claim':
        return NotificationRouteTarget(
          NotificationRouteKind.moderation,
          arguments: {
            'listingClaimId': _text(data['listingClaimId']),
            'listingType': _text(data['listingType']),
            'listingId': _text(data['listingId']),
          },
        );

      case 'content_removed':
      case 'account_moderation':
        return const NotificationRouteTarget(
          NotificationRouteKind.notifications,
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
              initialFocusNearby: target.arguments['section'] == 'nearby',
            ),
          ),
        );
        return;
      case NotificationRouteKind.businessServiceSetup:
        final user = FirebaseAuth.instance.currentUser;
        final id = target.arguments['businessId']!;
        if (user == null || user.isAnonymous) {
          await navigator.pushNamed('/home');
          return;
        }
        try {
          final doc = await FirebaseFirestore.instance
              .collection('businesses')
              .doc(id)
              .get();
          final data = doc.data();
          if (data != null &&
              data['ownerId'] == user.uid &&
              BusinessActivationPolicy.hasClaimedOwner(data) &&
              BusinessActivationPolicy.listingLive(data)) {
            await navigator.push(
              MaterialPageRoute(
                builder: (_) => BusinessServicesScreen(businessId: id),
              ),
            );
            return;
          }
        } on FirebaseException {
          /* Safe fallback for lost access or deleted listing. */
        }
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => const _MissingDestinationScreen(
              message:
                  'This business setup is no longer available to this account.',
            ),
          ),
        );
        return;
      case NotificationRouteKind.business:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => BusinessDetailScreen(
              businessId: target.arguments['businessId'] ?? '',
            ),
          ),
        );
        return;
      case NotificationRouteKind.organisation:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => OrganisationDetailScreen(
              organisationId: target.arguments['organisationId'] ?? '',
            ),
          ),
        );
        return;
      case NotificationRouteKind.serviceRequest:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => CustomerServiceRequestDetailScreen(
              requestId: target.arguments['serviceRequestId'] ?? '',
            ),
          ),
        );
        return;
      case NotificationRouteKind.businessServiceRequests:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => BusinessServiceRequestsScreen(
              businessId: target.arguments['businessId'] ?? '',
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
      case NotificationRouteKind.moderation:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => const ModeratorPopulateAreaScreen(),
          ),
        );
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

  static String _bookingBusinessIdForViewer(Map<String, dynamic> data) {
    final viewerType = _text(data['viewerType']).toLowerCase();
    if (viewerType == 'customer') return '';
    return _text(data['businessId']);
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
