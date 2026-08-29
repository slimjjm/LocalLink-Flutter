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
  });
}
