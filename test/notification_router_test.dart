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

  test('activity entry notification carries comment destination data', () {
    final target = NotificationRouter.resolve({
      'type': 'opportunity_comment',
      'opportunityId': 'opp-1',
      'commentId': 'comment-1',
      'entryId': 'entrant-1',
    });

    expect(target.kind, NotificationRouteKind.opportunity);
    expect(target.arguments['opportunityId'], 'opp-1');
    expect(target.arguments['commentId'], 'comment-1');
    expect(target.arguments['entryId'], 'entrant-1');
  });

  test('group announcement notification routes to the activity', () {
    final target = NotificationRouter.resolve({
      'type': 'opportunity_announcement',
      'opportunityId': 'group-1',
      'announcementId': 'announcement-1',
    });

    expect(target.kind, NotificationRouteKind.opportunity);
    expect(target.arguments['opportunityId'], 'group-1');
  });

  test('organisation announcement notification routes to the organisation', () {
    final target = NotificationRouter.resolve({
      'type': 'organisation_announcement',
      'organisationId': 'org-1',
      'announcementId': 'announcement-1',
    });

    expect(target.kind, NotificationRouteKind.organisation);
    expect(target.arguments['organisationId'], 'org-1');
  });

  test(
    'organisation invitation accepted notification routes to the organisation',
    () {
      final target = NotificationRouter.resolve({
        'type': 'organisation_invitation_accepted',
        'organisationId': 'org-1',
      });

      expect(target.kind, NotificationRouteKind.organisation);
      expect(target.arguments['organisationId'], 'org-1');
    },
  );

  test('booking notification routes to the booking', () {
    final target = NotificationRouter.resolve({
      'type': 'booking_confirmed',
      'bookingId': 'booking-1',
      'businessId': 'business-1',
      'viewerType': 'business',
    });

    expect(target.kind, NotificationRouteKind.booking);
    expect(target.arguments['bookingId'], 'booking-1');
    expect(target.arguments['businessId'], 'business-1');
  });

  test('customer booking notification opens customer booking detail', () {
    final target = NotificationRouter.resolve({
      'type': 'booking_confirmed',
      'bookingId': 'booking-1',
      'businessId': 'business-1',
      'viewerType': 'customer',
    });

    expect(target.kind, NotificationRouteKind.booking);
    expect(target.arguments['bookingId'], 'booking-1');
    expect(target.arguments['businessId'], isEmpty);
  });

  test('nearby service request notification routes to business requests', () {
    final target = NotificationRouter.resolve({
      'type': 'service_request_match',
      'serviceRequestId': 'request-1',
      'businessId': 'business-1',
    });

    expect(target.kind, NotificationRouteKind.businessServiceRequests);
    expect(target.arguments['serviceRequestId'], 'request-1');
    expect(target.arguments['businessId'], 'business-1');
  });

  test('service request offer notification routes to customer request', () {
    final target = NotificationRouter.resolve({
      'type': 'service_request_offer',
      'serviceRequestId': 'request-1',
      'businessId': 'business-1',
    });

    expect(target.kind, NotificationRouteKind.serviceRequest);
    expect(target.arguments['serviceRequestId'], 'request-1');
  });

  test('listing claim notification routes to a business listing', () {
    final target = NotificationRouter.resolve({
      'type': 'listing_claim',
      'listingType': 'business',
      'listingId': 'business-claim-1',
    });

    expect(target.kind, NotificationRouteKind.business);
    expect(target.arguments['businessId'], 'business-claim-1');
  });

  test('listing claim notification routes to an event listing', () {
    final target = NotificationRouter.resolve({
      'type': 'listing_claim',
      'listingType': 'opportunity',
      'listingId': 'event-claim-1',
    });

    expect(target.kind, NotificationRouteKind.opportunity);
    expect(target.arguments['opportunityId'], 'event-claim-1');
  });

  test('listing claim notification routes to an organisation listing', () {
    final target = NotificationRouter.resolve({
      'type': 'listing_claim',
      'listingType': 'organisation',
      'listingId': 'organisation-claim-1',
    });

    expect(target.kind, NotificationRouteKind.organisation);
    expect(target.arguments['organisationId'], 'organisation-claim-1');
  });

  test('moderation claim notification routes to moderation review', () {
    final target = NotificationRouter.resolve({
      'type': 'moderation_claim',
      'listingClaimId': 'claim-1',
      'listingType': 'business',
      'listingId': 'business-claim-1',
    });

    expect(target.kind, NotificationRouteKind.moderation);
    expect(target.arguments['listingClaimId'], 'claim-1');
    expect(target.arguments['listingId'], 'business-claim-1');
  });

  test('removed-content notifications stay on notifications safely', () {
    final target = NotificationRouter.resolve({
      'type': 'content_removed',
      'contentType': 'opportunity',
      'contentId': 'removed-event-1',
    });

    expect(target.kind, NotificationRouteKind.notifications);
  });

  test('account moderation notifications stay on notifications safely', () {
    final target = NotificationRouter.resolve({
      'type': 'account_moderation',
      'contentType': 'account',
    });

    expect(target.kind, NotificationRouteKind.notifications);
  });

  test('missing destination data falls back safely', () {
    final target = NotificationRouter.resolve({'type': 'booking_confirmed'});

    expect(target.kind, NotificationRouteKind.home);
  });

  test('grouped nearby pet alert opens Community Help without a report id', () {
    final target = NotificationRouter.resolve({
      'type': 'community_alert_group',
    });

    expect(target.kind, NotificationRouteKind.communityHelpPost);
    expect(target.arguments, {'section': 'nearby'});
  });

  test('single nearby pet alert opens the exact report', () {
    final target = NotificationRouter.resolve({
      'type': 'community_alert',
      'communityHelpPostId': 'missing-pet-42',
    });

    expect(target.kind, NotificationRouteKind.communityHelpPost);
    expect(target.arguments, {'postId': 'missing-pet-42'});
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
  test(
    'service enquiry opens the owner conversation and missing IDs use inbox',
    () {
      final target = NotificationRouter.resolve({
        'type': 'service_enquiry',
        'conversationId': 'enquiry-1',
      });
      expect(target.kind, NotificationRouteKind.bookingConversation);
      expect(target.arguments['viewerType'], 'business');
      expect(
        NotificationRouter.resolve({'type': 'service_enquiry'}).kind,
        NotificationRouteKind.inbox,
      );
    },
  );

  test('timed activity reminders open their activity', () {
    for (final type in [
      'opportunity_reminder_24h',
      'opportunity_reminder_1h',
    ]) {
      final target = NotificationRouter.resolve({
        'type': type,
        'opportunityId': 'activity-1',
      });
      expect(target.kind, NotificationRouteKind.opportunity);
      expect(target.arguments['opportunityId'], 'activity-1');
    }
  });
}
