import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/widgets/community_help_own_reports.dart';

// Test-only snapshot stand-in; no Firestore SDK implementation is subclassed in app code.
// ignore: subtype_of_sealed_class
class _Report implements DocumentSnapshot<Map<String, dynamic>> {
  _Report(this.id);
  @override
  final String id;
  @override
  Map<String, dynamic> data() => {'title': id};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const emptyMessage = 'Reports you create or claim will appear here.';
const errorMessage = "We couldn't load your reports. Please try again.";
Widget reports(CommunityHelpReportsLoader loader, {String? userId = 'owner'}) =>
    MaterialApp(
      home: Scaffold(
        body: CommunityHelpOwnReports(
          userId: userId,
          loadReports: loader,
          reportBuilder: (doc) => Text(doc.id),
        ),
      ),
    );

void main() {
  testWidgets('guests do not query or show the owner section', (tester) async {
    await tester.pumpWidget(
      reports((_) => throw StateError('must not query'), userId: null),
    );
    expect(find.text('Your reports'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waiting is not an empty result', (tester) async {
    final stream =
        StreamController<List<DocumentSnapshot<Map<String, dynamic>>>>();
    await tester.pumpWidget(reports((_) => stream.stream));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(emptyMessage), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(stream.close);
  });

  testWidgets('successful empty results retain the existing guidance', (
    tester,
  ) async {
    await tester.pumpWidget(reports((_) => Stream.value([])));
    await tester.pumpAndSettle();
    expect(find.text(emptyMessage), findsOneWidget);
    expect(find.text(errorMessage), findsNothing);
  });

  testWidgets('authorised reports use existing cards and survive rebuilds', (
    tester,
  ) async {
    var calls = 0;
    Stream<List<DocumentSnapshot<Map<String, dynamic>>>> loader(String uid) {
      expect(uid, 'owner');
      calls++;
      return Stream.value([
        _Report('created report'),
        _Report('approved claimed report'),
      ]);
    }

    await tester.pumpWidget(reports(loader));
    await tester.pumpAndSettle();
    await tester.pumpWidget(reports(loader));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('created report'), findsOneWidget);
    expect(find.text('approved claimed report'), findsOneWidget);
  });

  for (final code in ['permission-denied', 'unavailable']) {
    testWidgets(
      '$code shows an error and retry performs a fresh successful load',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          reports((_) {
            calls++;
            return calls == 1
                ? Stream.error(
                    FirebaseException(plugin: 'cloud_firestore', code: code),
                  )
                : Stream.value([_Report('recovered report')]);
          }),
        );
        await tester.pumpAndSettle();
        expect(find.text(errorMessage), findsOneWidget);
        expect(find.text(emptyMessage), findsNothing);
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(find.text('recovered report'), findsOneWidget);
        expect(find.text(errorMessage), findsNothing);
      },
    );
  }

  testWidgets('a failed refresh does not silently display stale results', (
    tester,
  ) async {
    final stream =
        StreamController<List<DocumentSnapshot<Map<String, dynamic>>>>();
    await tester.pumpWidget(reports((_) => stream.stream));
    stream.add([_Report('old report')]);
    await tester.pumpAndSettle();
    stream.addError(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    );
    await tester.pumpAndSettle();
    expect(find.text(errorMessage), findsOneWidget);
    expect(find.text('old report'), findsNothing);
    expect(find.text(emptyMessage), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(stream.close);
  });

  testWidgets(
    'account change removes previous reports and reloads the new owner',
    (tester) async {
      Stream<List<DocumentSnapshot<Map<String, dynamic>>>> loader(String uid) =>
          Stream.value([_Report(uid)]);
      await tester.pumpWidget(reports(loader));
      await tester.pumpAndSettle();
      await tester.pumpWidget(reports(loader, userId: 'other owner'));
      await tester.pumpAndSettle();
      expect(find.text('owner'), findsNothing);
      expect(find.text('other owner'), findsOneWidget);
      await tester.pumpWidget(reports(loader, userId: null));
      await tester.pumpAndSettle();
      expect(find.text('other owner'), findsNothing);
    },
  );

  testWidgets('synchronous query failure also presents retryable error', (
    tester,
  ) async {
    await tester.pumpWidget(
      reports((_) => throw StateError('query setup failed')),
    );
    await tester.pumpAndSettle();
    expect(find.text(errorMessage), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text(emptyMessage), findsNothing);
  });
}
