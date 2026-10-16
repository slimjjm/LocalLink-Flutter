import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/deep_link_service.dart';
import 'package:locallink_flutter/services/local_link_share_service.dart';

void main() {
  test('activity share text uses public location and exact item link', () {
    final text = LocalLinkShareService.buildShareText(
      const LocalLinkShareItem(
        type: LocalLinkShareItemType.activity,
        id: 'activity-1',
        data: {
          'title': 'Football tonight',
          'location': 'Burntwood',
          'distanceMiles': 0.8,
        },
      ),
    );

    expect(text, contains('Football tonight in Burntwood'));
    expect(text, contains('0.8 miles away'));
    expect(
      text,
      contains('https://locallinkapp.co.uk/opportunities/activity-1'),
    );
  });

  test('service and availability links identify exact public items', () {
    expect(
      LocalLinkShareService.urlFor(
        const LocalLinkShareItem(
          type: LocalLinkShareItemType.service,
          parentId: 'business-1',
          id: 'service-1',
          data: {},
        ),
      ),
      'https://locallinkapp.co.uk/services/business-1/service-1',
    );

    expect(
      LocalLinkShareService.urlFor(
        const LocalLinkShareItem(
          type: LocalLinkShareItemType.availability,
          id: 'slot-1',
          data: {},
        ),
      ),
      'https://locallinkapp.co.uk/availability/slot-1',
    );
  });

  test('service request link identifies the exact request', () {
    expect(
      LocalLinkShareService.urlFor(
        const LocalLinkShareItem(
          type: LocalLinkShareItemType.serviceRequest,
          id: 'request-1',
          data: {},
        ),
      ),
      'https://locallinkapp.co.uk/service-requests/request-1',
    );
  });

  test('business share link identifies the exact listing', () {
    final item = const LocalLinkShareItem(
      type: LocalLinkShareItemType.business,
      id: 'teds-bakery-van',
      data: {
        'businessName': 'Tedsbakeryvan',
        'category': 'Specialist Services',
        'publicLocation': 'Lichfield',
      },
    );

    expect(
      LocalLinkShareService.urlFor(item),
      'https://locallinkapp.co.uk/businesses/teds-bakery-van',
    );

    final text = LocalLinkShareService.buildShareText(item);
    expect(text, contains('Tedsbakeryvan'));
    expect(text, contains('Specialist Services'));
    expect(
      text,
      contains('https://locallinkapp.co.uk/businesses/teds-bakery-van'),
    );
  });

  test('share text does not expose coordinates', () {
    final text = LocalLinkShareService.buildShareText(
      const LocalLinkShareItem(
        type: LocalLinkShareItemType.activity,
        id: 'privacy-1',
        data: {
          'title': 'Coffee morning',
          'location': 'Lichfield',
          'latitude': 52.6812,
          'longitude': -1.8319,
          'createdBy': 'private-user',
        },
      ),
    );

    expect(text, contains('Lichfield'));
    expect(text, isNot(contains('52.6812')));
    expect(text, isNot(contains('-1.8319')));
    expect(text, isNot(contains('private-user')));
  });

  test('service request share text is concise and private', () {
    final text = LocalLinkShareService.buildShareText(
      const LocalLinkShareItem(
        type: LocalLinkShareItemType.serviceRequest,
        id: 'request-1',
        data: {
          'category': 'Handyman',
          'title': 'Door to be fixed',
          'description': "Lock isn't working",
          'scheduleText': 'ASAP',
          'publicLocation': 'Burntwood',
          'approxLatitude': 52.681,
          'approxLongitude': -1.831,
          'customerId': 'user-secret',
          'customerEmail': 'customer@example.com',
          'imageUrls': ['https://firebasestorage.example/private.jpg'],
          'status': 'open',
          'isActive': true,
        },
      ),
    );

    expect(text, contains('local Handyman'));
    expect(text, contains('Burntwood'));
    expect(text, contains('Door to be fixed'));
    expect(text, contains("Lock isn't working"));
    expect(
      text,
      contains('https://locallinkapp.co.uk/service-requests/request-1'),
    );
    expect(text, isNot(contains('52.681')));
    expect(text, isNot(contains('-1.831')));
    expect(text, isNot(contains('user-secret')));
    expect(text, isNot(contains('customer@example.com')));
    expect(text, isNot(contains('firebasestorage')));
  });

  test('closed service request share text is not advertised as looking', () {
    final text = LocalLinkShareService.buildShareText(
      const LocalLinkShareItem(
        type: LocalLinkShareItemType.serviceRequest,
        id: 'request-closed',
        data: {
          'category': 'Cleaner',
          'title': 'Cleaning help',
          'publicLocation': 'Burntwood',
          'status': 'closed',
          'isActive': false,
        },
      ),
    );

    expect(text, startsWith('View this LocalLink service request.'));
    expect(text, isNot(contains("I'm looking")));
  });

  test('public LocalLink URLs parse to exact app destinations', () {
    final community = LocalLinkDeepLinkTarget.fromUri(
      Uri.parse('https://locallinkapp.co.uk/community-help/post-1'),
    );
    expect(community?.type, LocalLinkDeepLinkType.communityHelp);
    expect(community?.id, 'post-1');

    final activity = LocalLinkDeepLinkTarget.fromUri(
      Uri.parse('https://locallinkapp.co.uk/opportunities/opp-1'),
    );
    expect(activity?.type, LocalLinkDeepLinkType.opportunity);
    expect(activity?.id, 'opp-1');

    final availability = LocalLinkDeepLinkTarget.fromUri(
      Uri.parse('https://locallinkapp.co.uk/availability/availability-1'),
    );
    expect(availability?.type, LocalLinkDeepLinkType.availability);
    expect(availability?.id, 'availability-1');

    final business = LocalLinkDeepLinkTarget.fromUri(
      Uri.parse('https://locallinkapp.co.uk/businesses/business-1'),
    );
    expect(business?.type, LocalLinkDeepLinkType.business);
    expect(business?.id, 'business-1');

    final service = LocalLinkDeepLinkTarget.fromUri(
      Uri.parse('https://locallinkapp.co.uk/services/business-1/service-1'),
    );
    expect(service?.type, LocalLinkDeepLinkType.service);
    expect(service?.parentId, 'business-1');
    expect(service?.id, 'service-1');

    final invitation = LocalLinkDeepLinkTarget.fromUri(
      Uri.parse('https://locallinkapp.co.uk/invitations/organisation/token-1'),
    );
    expect(invitation?.type, LocalLinkDeepLinkType.organisationInvitation);
    expect(invitation?.id, 'token-1');

    final serviceRequest = LocalLinkDeepLinkTarget.fromUri(
      Uri.parse('https://locallinkapp.co.uk/service-requests/request-1'),
    );
    expect(serviceRequest?.type, LocalLinkDeepLinkType.serviceRequest);
    expect(serviceRequest?.id, 'request-1');
  });

  test('Stripe Connect return URLs parse to app-owned return destinations', () {
    final stripeReturn = LocalLinkDeepLinkTarget.fromUri(
      Uri.parse(
        'https://locallinkapp.co.uk/stripe-return?businessId=business-1',
      ),
    );
    expect(stripeReturn?.type, LocalLinkDeepLinkType.stripeReturn);
    expect(stripeReturn?.id, 'business-1');

    final stripeRefresh = LocalLinkDeepLinkTarget.fromUri(
      Uri.parse(
        'https://locallinkapp.co.uk/stripe-refresh?businessId=business-1',
      ),
    );
    expect(stripeRefresh?.type, LocalLinkDeepLinkType.stripeRefresh);
    expect(stripeRefresh?.id, 'business-1');
  });

  test('public LocalLink URL parser ignores unsupported routes', () {
    expect(
      LocalLinkDeepLinkTarget.fromUri(
        Uri.parse('https://locallinkapp.co.uk/privacy'),
      ),
      isNull,
    );
    expect(
      LocalLinkDeepLinkTarget.fromUri(
        Uri.parse('https://example.com/opportunities/opp-1'),
      ),
      isNull,
    );
    expect(
      LocalLinkDeepLinkTarget.fromUri(
        Uri.parse('https://locallinkapp.co.uk/stripe-return'),
      ),
      isNull,
    );
    expect(
      LocalLinkDeepLinkTarget.fromUri(
        Uri.parse('https://locallinkapp.co.uk/service-requests'),
      ),
      isNull,
    );
  });

  test('public LocalLink URL parser tolerates trailing path segments', () {
    final activity = LocalLinkDeepLinkTarget.fromUri(
      Uri.parse('https://locallinkapp.co.uk/opportunities/opp-1/comments/c-1'),
    );

    expect(activity?.type, LocalLinkDeepLinkType.opportunity);
    expect(activity?.id, 'opp-1');
  });

  test('custom app URLs parse service targets through business handoff', () {
    final service = LocalLinkDeepLinkTarget.fromUri(
      Uri.parse('locallink://business/business-1?serviceId=service-1'),
    );

    expect(service?.type, LocalLinkDeepLinkType.service);
    expect(service?.parentId, 'business-1');
    expect(service?.id, 'service-1');

    final invitation = LocalLinkDeepLinkTarget.fromUri(
      Uri.parse('locallink://organisation-invitation/token-1'),
    );
    expect(invitation?.type, LocalLinkDeepLinkType.organisationInvitation);
    expect(invitation?.id, 'token-1');

    final serviceRequest = LocalLinkDeepLinkTarget.fromUri(
      Uri.parse('locallink://service-request/request-1'),
    );
    expect(serviceRequest?.type, LocalLinkDeepLinkType.serviceRequest);
    expect(serviceRequest?.id, 'request-1');
  });
}
