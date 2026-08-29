import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/screens/availability_detail_screen.dart';

void main() {
  testWidgets(
    'Ask to Book dialog opens and cancel returns null without submit',
    (tester) async {
      String? result = 'not-yet';
      var submitCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    final value = await showAskToBookDialog(context);
                    result = value;
                    if (value != null) submitCount += 1;
                  },
                  child: const Text('Ask to Book'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Ask to Book'));
      await tester.pumpAndSettle();

      expect(find.byType(AskToBookDialog), findsOneWidget);
      expect(find.text('Ask to book'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AskToBookDialog), findsNothing);
      expect(result, isNull);
      expect(submitCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Ask to Book dialog sends trimmed text exactly once', (
    tester,
  ) async {
    String? result;
    var submitCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final value = await showAskToBookDialog(context);
                  result = value;
                  if (value != null) submitCount += 1;
                },
                child: const Text('Ask to Book'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Ask to Book'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Friday morning please  ');

    await tester.tap(find.text('Send'));
    await tester.tap(find.text('Send'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(result, 'Friday morning please');
    expect(submitCount, 1);
    expect(find.byType(AskToBookDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ask to Book dialog can close while parent is replaced', (
    tester,
  ) async {
    var showParent = true;
    String? result = 'not-yet';

    Widget buildApp() {
      return MaterialApp(
        home: showParent
            ? Builder(
                builder: (context) {
                  return Scaffold(
                    body: ElevatedButton(
                      onPressed: () async {
                        result = await showAskToBookDialog(context);
                      },
                      child: const Text('Ask to Book'),
                    ),
                  );
                },
              )
            : const Scaffold(body: Text('Gone')),
      );
    }

    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Ask to Book'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    showParent = false;
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text('Gone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
