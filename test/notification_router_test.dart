import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/notification_preferences.dart';
import 'package:locallink_flutter/services/notification_router.dart';

void main() {
  test('Community Help response routes to the private conversation', () {
    final target = NotificationRouter.resolve({
      'type': 'community_help_response',
      'conversationId': 'conversation-1',
      'communityHelpPostId': 'post-1',
      'viewerType': 'business',
    });

    expect(target.kind, NotificationRouteKind.bookingConversation);
    expect(target.arguments['conversationId'], 'conversation-1');
    expect(target.arguments['viewerType'], 'business');
  });

  test('sighting routes to the private conversation', () {
    final target = NotificationRouter.resolve({
      'type': 'community_help_sighting',
      'conversationId': 'sighting-1',
      'communityHelpPostId': 'post-1',
    });

    expect(target.kind, NotificationRouteKind.bookingConversation);
    expect(target.arguments['conversationId'], 'sighting-1');
  });

  test('public update routes to the exact Community Help post', () {
    final target = NotificationRouter.resolve({
      'type': 'community_help_update',
      'communityHelpPostId': 'post-42',
      'updateId': 'update-1',
    });

    expect(target.kind, NotificationRouteKind.communityHelpPost);
    expect(target.arguments['postId'], 'post-42');
  });

  test('expiry reminder routes to the exact Community Help post', () {
    final target = NotificationRouter.resolve({
      'type': 'community_help_expiry',
      'communityHelpPostId': 'post-expiring',
    });

    expect(target.kind, NotificationRouteKind.communityHelpPost);
    expect(target.arguments['postId'], 'post-expiring');
  });

  test('activity notification routes to the activity', () {
    final target = NotificationRouter.resolve({
      'type': 'opportunity_comment',
      'opportunityId': 'opp-1',
    });

    expect(target.kind, NotificationRouteKind.opportunity);
    expect(target.arguments['opportunityId'], 'opp-1');
  });

  test('booking notification routes to the booking', () {
    final target = NotificationRouter.resolve({
      'type': 'booking_confirmed',
      'bookingId': 'booking-1',
      'businessId': 'business-1',
    });

    expect(target.kind, NotificationRouteKind.booking);
    expect(target.arguments['bookingId'], 'booking-1');
    expect(target.arguments['businessId'], 'business-1');
  });

  test('missing destination data falls back safely', () {
    final target = NotificationRouter.resolve({'type': 'booking_confirmed'});

    expect(target.kind, NotificationRouteKind.home);
  });

  test('existing users without preferences get compatible defaults', () {
    final values = NotificationPreferences.fromData(null);

    expect(values[NotificationPreferences.communityResponses], isTrue);
    expect(values[NotificationPreferences.communityMessages], isTrue);
    expect(values[NotificationPreferences.nearbyCommunityAlerts], isTrue);
    expect(values[NotificationPreferences.localDiscovery], isFalse);
    expect(values[NotificationPreferences.communityAlertsNearby], isFalse);
  });

  test('stored preferences override defaults', () {
    final values = NotificationPreferences.fromData({
      NotificationPreferences.communityResponses: false,
      NotificationPreferences.reminders: false,
    });

    expect(values[NotificationPreferences.communityResponses], isFalse);
    expect(values[NotificationPreferences.reminders], isFalse);
    expect(values[NotificationPreferences.communityMessages], isTrue);
  });
}
