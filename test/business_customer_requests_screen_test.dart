import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/screens/business_service_requests_screen.dart';
import 'package:locallink_flutter/services/service_request_marketplace.dart';

void main() {
  BusinessCustomerRequestContext contextFor({
    bool enabled = true,
    bool active = true,
    bool claimed = true,
    double? latitude = 52.681,
    double? longitude = -1.927,
  }) {
    final businessData = {
      'businessName': 'Helpful Hands',
      'isActive': active,
      'isClaimed': claimed,
      'acceptingLeads': enabled,
    };
    if (latitude != null) businessData['latitude'] = latitude;
    if (longitude != null) businessData['longitude'] = longitude;

    return BusinessCustomerRequestContext(
      businessId: 'business-1',
      businessExists: true,
      businessData: businessData,
      services: const [
        BusinessCustomerRequestService(
          id: 'service-1',
          data: {
            'isActive': true,
            'category': 'Handyman',
            'name': 'Handyman help',
            'details': 'Odd jobs, shelves and small repairs',
          },
        ),
      ],
    );
  }

  BusinessCustomerRequestItem request({
    String title = 'Shelves need putting up',
    String category = 'Handyman',
    List<String> imageUrls = const [],
  }) {
    return BusinessCustomerRequestItem(
      id: 'request-1',
      data: {
        'title': title,
        'category': category,
        'description': 'Two shelves and a curtain rail.',
        'publicLocation': 'Burntwood',
        'scheduleText': 'This week',
        'status': ServiceRequestMarketplace.statusOpen,
        'isActive': true,
        'expiresAt': DateTime.now().add(const Duration(days: 1)),
        'approxLatitude': 52.682,
        'approxLongitude': -1.928,
        if (imageUrls.isNotEmpty) 'imageUrls': imageUrls,
      },
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required Future<BusinessCustomerRequestContext> Function(String)
    contextLoader,
    required Stream<List<BusinessCustomerRequestItem>> Function()
    requestsStreamFactory,
    Future<void> Function(String, bool)? settingUpdater,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessServiceRequestsScreen(
          businessId: 'business-1',
          contextLoader: contextLoader,
          requestsStreamFactory: requestsStreamFactory,
          settingUpdater: settingUpdater,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('customer requests off shows paused state and visible toggle', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      contextLoader: (_) async => contextFor(enabled: false),
      requestsStreamFactory: () => Stream.value(const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customer requests'), findsOneWidget);
    expect(find.text('Customer requests are paused'), findsOneWidget);
    expect(find.text('Leads are paused'), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets(
    'turning customer requests on updates setting and loads requests',
    (tester) async {
      var enabled = false;
      final requests = StreamController<List<BusinessCustomerRequestItem>>();

      await pumpScreen(
        tester,
        contextLoader: (_) async => contextFor(enabled: enabled),
        requestsStreamFactory: () => requests.stream,
        settingUpdater: (_, value) async {
          enabled = value;
        },
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pump();
      requests.add([request()]);
      await tester.pumpAndSettle();

      expect(enabled, isTrue);
      expect(find.text('Matching requests'), findsOneWidget);
      expect(find.text('Shelves need putting up'), findsOneWidget);
    },
  );

  testWidgets('on with zero matches shows normal empty state', (tester) async {
    await pumpScreen(
      tester,
      contextLoader: (_) async => contextFor(),
      requestsStreamFactory: () => Stream.value(const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('Matching requests'), findsOneWidget);
    expect(find.text('No matching requests right now'), findsOneWidget);
    expect(find.text('Leads are paused'), findsNothing);
  });

  testWidgets('on with matches displays matching request card', (tester) async {
    await pumpScreen(
      tester,
      contextLoader: (_) async => contextFor(),
      requestsStreamFactory: () => Stream.value([request()]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Matching requests'), findsOneWidget);
    expect(find.text('Shelves need putting up'), findsOneWidget);
    expect(find.textContaining('Burntwood'), findsOneWidget);
    expect(find.text('Offer my service'), findsOneWidget);
  });

  testWidgets('request card shows first attached photo preview', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      contextLoader: (_) async => contextFor(),
      requestsStreamFactory: () => Stream.value([
        request(imageUrls: const ['https://example.com/request.jpg']),
      ]),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('service-request-photo-preview')),
      findsOneWidget,
    );
  });

  testWidgets('setting update failure rolls toggle back and shows error', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      contextLoader: (_) async => contextFor(enabled: false),
      requestsStreamFactory: () => Stream.value(const []),
      settingUpdater: (_, _) async {
        throw StateError('write failed');
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.value, isFalse);
    expect(
      find.text('Customer requests could not be updated. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('location unavailable shows location state, not no matches', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      contextLoader: (_) async => contextFor(latitude: null, longitude: null),
      requestsStreamFactory: () => Stream.value(const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('Business location needed'), findsOneWidget);
    expect(find.text('No matching requests right now'), findsNothing);
  });
}
