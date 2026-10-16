import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/models/ask_locallink.dart';
import 'package:locallink_flutter/screens/customer_home_screen.dart';
import 'package:locallink_flutter/services/ask_locallink_service.dart';
import 'package:locallink_flutter/theme/local_link_theme.dart';

void main() {
  testWidgets(
    'Ask LocalLink shows loading and prevents duplicate submissions',
    (tester) async {
      final completer = Completer<AskLocalLinkResponse>();
      var calls = 0;

      await tester.pumpWidget(
        _host(
          search: (_, {context = const AskLocalLinkQueryContext()}) {
            calls += 1;
            return completer.future;
          },
        ),
      );

      await _submitAsk(tester, 'dog groomer tomorrow');
      await tester.pump();

      expect(calls, 1);
      expect(find.text('Searching LocalLink...'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(calls, 1);

      completer.complete(_response(results: [_result('service')]));
      await tester.pumpAndSettle();

      expect(find.text('Paws & Co'), findsOneWidget);
    },
  );

  testWidgets('Ask LocalLink focus does not submit a search', (tester) async {
    var calls = 0;

    await tester.pumpWidget(
      _host(
        search: (_, {context = const AskLocalLinkQueryContext()}) async {
          calls += 1;
          return _response();
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ask-locallink-search-field')));
    await tester.pump();

    expect(calls, 0);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('Ask LocalLink renders result types and opens tapped result', (
    tester,
  ) async {
    final results = [
      _result('service', title: 'Paws & Co', parentId: 'business-1'),
      _result('business', title: 'Burntwood Beauty'),
      _result('availability', title: 'Same-day plumber'),
      _result('activity', title: 'Junior football'),
      _result('organisation', title: 'Litter Pickers'),
      _result('communityHelp', title: 'Lost keys near park'),
      _result(
        'action',
        title: 'Report found item',
        metadata: {'actionIntent': 'report_found_item'},
      ),
    ];
    final opened = <AskLocalLinkResult>[];

    await tester.pumpWidget(
      _host(
        search: (_, {context = const AskLocalLinkQueryContext()}) async =>
            _response(results: results),
        opener: (context, result) async {
          opened.add(result);
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(body: Text('Opened ${result.type}')),
            ),
          );
        },
      ),
    );

    await _submitAsk(tester, 'what is nearby');
    await tester.pumpAndSettle();

    expect(find.text('Service'), findsOneWidget);
    expect(find.text('Business'), findsOneWidget);
    expect(find.text('Availability'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Organisation'), findsOneWidget);
    expect(find.text('Community Help'), findsOneWidget);
    expect(find.text('Start found item report'), findsOneWidget);

    await tester.tap(find.text('Paws & Co'));
    await tester.pumpAndSettle();

    expect(opened.single.type, 'service');
    expect(find.text('Opened service'), findsOneWidget);
  });

  testWidgets('Ask LocalLink renders exact moderator seeded business result', (
    tester,
  ) async {
    String? capturedQuery;
    AskLocalLinkQueryContext? capturedContext;
    final opened = <AskLocalLinkResult>[];

    await tester.pumpWidget(
      _host(
        contextResolver: (_) async => const AskLocalLinkQueryContext(
          locationText: 'Burntwood',
          latitude: 52.681,
          longitude: -1.927,
          radiusMiles: 40,
        ),
        search: (query, {context = const AskLocalLinkQueryContext()}) async {
          capturedQuery = query;
          capturedContext = context;
          return _response(
            results: [
              _result(
                'business',
                id: 'iQS73dgvX6RuiUuA1nRF',
                title: 'Tedsbakeryvan',
                subtitle: 'Specialist Services · Lichfield',
                route: '/businesses/iQS73dgvX6RuiUuA1nRF',
              ),
            ],
          );
        },
        opener: (_, result) async => opened.add(result),
      ),
    );

    await _submitAsk(tester, 'Tedsbakeryvan');
    await tester.pumpAndSettle();

    expect(capturedQuery, 'Tedsbakeryvan');
    expect(capturedContext?.locationText, 'Burntwood');
    expect(capturedContext?.latitude, 52.681);
    expect(capturedContext?.longitude, -1.927);
    expect(capturedContext?.radiusMiles, 40);
    expect(find.text('No matching services found right now.'), findsNothing);
    expect(find.text('Tedsbakeryvan'), findsWidgets);
    expect(find.text('Business'), findsOneWidget);

    await tester.tap(find.text('Tedsbakeryvan').last);
    await tester.pumpAndSettle();

    expect(opened.single.type, 'business');
    expect(opened.single.id, 'iQS73dgvX6RuiUuA1nRF');
    expect(opened.single.route, '/businesses/iQS73dgvX6RuiUuA1nRF');
  });

  testWidgets('Ask LocalLink opens action suggestions with action metadata', (
    tester,
  ) async {
    final opened = <AskLocalLinkResult>[];

    await tester.pumpWidget(
      _host(
        search: (_, {context = const AskLocalLinkQueryContext()}) async =>
            _response(
              intent: 'report_found_item',
              results: [
                _result(
                  'action',
                  title: 'Report found item',
                  subtitle: 'You can report it as found.',
                  metadata: {
                    'actionIntent': 'report_found_item',
                    'communityHelpType': 'lost_found',
                    'mode': 'found',
                    'itemCategory': 'Keys',
                  },
                ),
              ],
            ),
        opener: (_, result) async => opened.add(result),
      ),
    );

    await _submitAsk(tester, 'I found some keys');
    await tester.pumpAndSettle();

    expect(find.text('Report found item'), findsOneWidget);
    expect(find.text('You can report it as found.'), findsOneWidget);
    expect(find.text('Start found item report'), findsOneWidget);

    await tester.tap(find.text('Start found item report'));
    await tester.pumpAndSettle();

    expect(opened.single.isAction, isTrue);
    expect(opened.single.actionIntent, 'report_found_item');
    expect(opened.single.metadata['itemCategory'], 'Keys');
  });

  testWidgets(
    'Ask LocalLink action card shows full description and fits narrow layout',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const description =
          'Sorry your pet is missing. You can alert people nearby on LocalLink.';
      final opened = <AskLocalLinkResult>[];

      await tester.pumpWidget(
        _host(
          search: (_, {context = const AskLocalLinkQueryContext()}) async =>
              _response(
                intent: 'report_missing_pet',
                results: [
                  _result(
                    'action',
                    title: 'Report missing pet',
                    subtitle: description,
                    metadata: {
                      'actionIntent': 'report_missing_pet',
                      'communityHelpType': 'lost_found',
                      'mode': 'lost',
                      'itemCategory': 'Pet',
                      'petType': 'dog',
                    },
                  ),
                ],
              ),
          opener: (_, result) async => opened.add(result),
        ),
      );

      await _submitAsk(tester, 'I lost my dog');
      await tester.pumpAndSettle();

      expect(find.text(description), findsOneWidget);
      expect(find.text('Start missing pet report'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Start missing pet report'));
      await tester.pumpAndSettle();

      expect(opened.single.actionIntent, 'report_missing_pet');
    },
  );

  testWidgets('Ask LocalLink preserves activity result time on the card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        search: (_, {context = const AskLocalLinkQueryContext()}) async =>
            _response(
              results: [
                _result(
                  'activity',
                  title: 'Little Friends baby and toddler group',
                  subtitle: 'Wed 23 Sept, 12:45 · Burntwood',
                ),
              ],
            ),
      ),
    );

    await _submitAsk(tester, 'baby group in Burntwood');
    await tester.pumpAndSettle();

    expect(find.text('Little Friends baby and toddler group'), findsOneWidget);
    expect(find.text('Wed 23 Sept, 12:45 · Burntwood'), findsOneWidget);
    expect(find.textContaining('00:00'), findsNothing);
  });

  testWidgets(
    'Ask LocalLink result navigation is deterministic by result type',
    (tester) async {
      for (final type in const [
        'service',
        'business',
        'availability',
        'activity',
        'organisation',
        'communityHelp',
      ]) {
        final opened = <AskLocalLinkResult>[];
        await tester.pumpWidget(
          _host(
            search: (_, {context = const AskLocalLinkQueryContext()}) async =>
                _response(results: [_result(type)]),
            opener: (_, result) async => opened.add(result),
          ),
        );

        await _submitAsk(tester, type);
        await tester.pumpAndSettle();
        await tester.tap(find.text(_titleFor(type)));
        await tester.pumpAndSettle();

        expect(opened.map((result) => result.type), [type]);
      }
    },
  );

  testWidgets('Ask LocalLink handles error, unknown intent and no results', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        search: (_, {context = const AskLocalLinkQueryContext()}) async =>
            throw Exception('fail'),
      ),
    );

    await _submitAsk(tester, 'help');
    await tester.pumpAndSettle();

    expect(
      find.text("Ask LocalLink isn't available right now."),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);

    await tester.pumpWidget(
      _host(
        search: (_, {context = const AskLocalLinkQueryContext()}) async =>
            _response(intent: 'unknown', status: 'unknown'),
      ),
    );
    await _submitAsk(tester, 'something vague');
    await tester.pumpAndSettle();

    expect(
      find.text("I'm not sure what you're looking for yet."),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _host(
        search: (_, {context = const AskLocalLinkQueryContext()}) async =>
            _response(intent: 'find_availability'),
      ),
    );
    await _submitAsk(tester, 'plumber today');
    await tester.pumpAndSettle();

    expect(
      find.text('No matching availability found right now.'),
      findsOneWidget,
    );
    expect(find.text('Create a service request'), findsOneWidget);
  });

  testWidgets('existing Home discovery is visible beneath Ask LocalLink', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: CustomerHomeScreen(
          showLiveDiscovery: false,
          showBusinessAvailabilityAction: false,
          header: const Text('Header'),
          askSearch: (_, {context = const AskLocalLinkQueryContext()}) async =>
              _response(),
          askResultOpener: (_, _) async {},
        ),
      ),
    );

    expect(find.text('What do you need locally?'), findsOneWidget);
    expect(find.text("Explore what's nearby"), findsOneWidget);
    expect(
      find.text(
        'See activities, groups, services and community help around you',
      ),
      findsOneWidget,
    );
    expect(find.text('Explore your community'), findsOneWidget);
    expect(find.text("Explore what's nearby"), findsOneWidget);
    expect(find.text('I need a service'), findsNothing);
    expect(find.text('Create something'), findsNothing);
    expect(find.text('Report something'), findsNothing);
    expect(find.text('Explore Nearby'), findsNothing);
    expect(find.text('Explore on Map'), findsNothing);
  });

  testWidgets('Explore nearby action opens the full map screen', (
    tester,
  ) async {
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: CustomerHomeScreen(
          showLiveDiscovery: false,
          showBusinessAvailabilityAction: false,
          header: const Text('Header'),
          askSearch: (_, {context = const AskLocalLinkQueryContext()}) async =>
              _response(),
          askResultOpener: (_, _) async {},
          exploreNearbyOpener: () => opened = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('explore-nearby-action')));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('Home top section has no embedded GoogleMap preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: CustomerHomeScreen(
          showLiveDiscovery: false,
          showBusinessAvailabilityAction: false,
          header: const Text('Header'),
          askSearch: (_, {context = const AskLocalLinkQueryContext()}) async =>
              _response(),
          askResultOpener: (_, _) async {},
        ),
      ),
    );

    expect(find.text('Explore Nearby'), findsNothing);
    expect(
      find.text('Open the map to discover what is close by.'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('explore-nearby-action')), findsOneWidget);
  });

  testWidgets('Home top section fits representative iPhone constraints', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: LocalLinkTheme.light,
        home: CustomerHomeScreen(
          showLiveDiscovery: false,
          showBusinessAvailabilityAction: false,
          header: const Text('Header'),
          askSearch: (_, {context = const AskLocalLinkQueryContext()}) async =>
              _response(),
          askResultOpener: (_, _) async {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text("Explore what's nearby"), findsOneWidget);
  });

  testWidgets('Ask LocalLink passes resolved discovery context to search', (
    tester,
  ) async {
    AskLocalLinkQueryContext? capturedContext;

    await tester.pumpWidget(
      _host(
        contextResolver: (_) async => const AskLocalLinkQueryContext(
          locationText: 'Burntwood',
          latitude: 52.681,
          longitude: -1.927,
        ),
        search: (_, {context = const AskLocalLinkQueryContext()}) async {
          capturedContext = context;
          return _response(results: [_result('activity')]);
        },
      ),
    );

    await _submitAsk(tester, 'a baby group in Burntwood');
    await tester.pumpAndSettle();

    expect(capturedContext?.locationText, 'Burntwood');
    expect(capturedContext?.latitude, 52.681);
    expect(capturedContext?.longitude, -1.927);
  });
}

Widget _host({
  required AskLocalLinkSearch search,
  AskLocalLinkResultOpener? opener,
  AskLocalLinkContextResolver? contextResolver,
}) {
  return MaterialApp(
    theme: LocalLinkTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: AskLocalLinkPanel(
          search: search,
          resultOpener: opener ?? (_, _) async {},
          onBrowseManually: () {},
          contextResolver: contextResolver,
        ),
      ),
    ),
  );
}

Future<void> _submitAsk(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('ask-locallink-search-field')),
    text,
  );
  await tester.testTextInput.receiveAction(TextInputAction.search);
}

AskLocalLinkResponse _response({
  String intent = 'find_service',
  String status = 'ok',
  List<AskLocalLinkResult> results = const [],
}) {
  return AskLocalLinkResponse(
    intent: AskLocalLinkIntent(
      intent: intent,
      searchText: '',
      category: '',
      serviceType: '',
      requiresAvailability: false,
      audience: '',
      sort: 'relevance',
      confidence: 1,
    ),
    results: results,
    status: status,
  );
}

AskLocalLinkResult _result(
  String type, {
  String? id,
  String? title,
  String parentId = '',
  String subtitle = 'Burntwood',
  String? route,
  Map<String, dynamic> metadata = const {},
}) {
  return AskLocalLinkResult(
    type: type,
    id: id ?? '$type-id',
    parentId: parentId,
    title: title ?? _titleFor(type),
    subtitle: subtitle,
    route: route ?? '/$type',
    metadata: metadata,
  );
}

String _titleFor(String type) {
  return switch (type) {
    'service' => 'Paws & Co',
    'business' => 'Burntwood Beauty',
    'availability' => 'Same-day plumber',
    'activity' => 'Junior football',
    'organisation' => 'Litter Pickers',
    'communityHelp' => 'Lost keys near park',
    'action' => 'Report found item',
    _ => 'Local result',
  };
}
