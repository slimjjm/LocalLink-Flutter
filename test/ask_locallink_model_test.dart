import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/models/ask_locallink.dart';
import 'package:locallink_flutter/services/ask_locallink_service.dart';

void main() {
  group('AskLocalLinkResponse', () {
    test('parses typed intent and genuine result identity', () {
      final response = AskLocalLinkResponse.fromMap({
        'status': 'ok',
        'intent': {
          'intent': 'find_availability',
          'searchText': 'dog groomer',
          'category': 'Pets',
          'serviceType': 'dog grooming',
          'dateRange': {'start': '2026-09-16', 'end': '2026-09-16'},
          'timeRange': {'start': '09:00', 'end': '12:00'},
          'location': {
            'text': 'Burntwood',
            'latitude': 52.68,
            'longitude': -1.93,
            'radiusMiles': 5,
          },
          'requiresAvailability': true,
          'audience': '',
          'age': null,
          'sort': 'soonest',
          'confidence': 0.91,
        },
        'results': [
          {
            'type': 'availability',
            'id': 'availability-1',
            'parentId': 'business-1',
            'title': 'Dog grooming',
            'subtitle': 'Burntwood Pets · Wed 16 Sep',
            'distanceMiles': 1.4,
            'dateTime': '2026-09-16T09:00:00.000Z',
            'route': '/availability/availability-1',
            'metadata': {'businessId': 'business-1', 'serviceId': 'service-1'},
          },
        ],
      });

      expect(response.status, 'ok');
      expect(response.intent.intent, 'find_availability');
      expect(response.intent.dateRange?.start, '2026-09-16');
      expect(response.intent.timeRange?.end, '12:00');
      expect(response.intent.location?.radiusMiles, 5);
      expect(response.results.single.type, 'availability');
      expect(response.results.single.id, 'availability-1');
      expect(response.results.single.parentId, 'business-1');
      expect(response.results.single.route, '/availability/availability-1');
      expect(response.results.single.metadata['serviceId'], 'service-1');
    });

    test('handles unknown or empty responses safely', () {
      final response = AskLocalLinkResponse.fromMap({
        'status': 'unknown',
        'intent': {'intent': 'unknown'},
        'results': const [],
      });

      expect(response.isUnknown, isTrue);
      expect(response.hasResults, isFalse);
      expect(response.intent.searchText, '');
    });

    test('parses action results safely', () {
      final response = AskLocalLinkResponse.fromMap({
        'status': 'ok',
        'intent': {'intent': 'report_found_item'},
        'results': [
          {
            'type': 'action',
            'id': 'report_found_item',
            'title': 'Report found item',
            'subtitle': 'You can report it as found.',
            'route': '/actions/report_found_item',
            'metadata': {
              'actionIntent': 'report_found_item',
              'communityHelpType': 'lost_found',
              'mode': 'found',
              'itemCategory': 'Keys',
            },
          },
        ],
      });

      final result = response.results.single;

      expect(result.isAction, isTrue);
      expect(result.actionIntent, 'report_found_item');
      expect(result.metadata['itemCategory'], 'Keys');
    });
  });

  group('AskLocalLinkQueryContext', () {
    test('only sends coarse context values that are present', () {
      const context = AskLocalLinkQueryContext(
        locationText: 'Burntwood',
        radiusMiles: 5,
      );

      expect(context.hasValues, isTrue);
      expect(context.toMap(), {'locationText': 'Burntwood', 'radiusMiles': 5});
    });
  });
}
