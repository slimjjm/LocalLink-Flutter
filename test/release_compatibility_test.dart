import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/release_compatibility.dart';
import 'package:locallink_flutter/widgets/release_compatibility_gate.dart';

const ready = {
  'ready': true,
  'minimumBuild': 21,
  'discoverySchema': 1,
  'reviewApi': 1,
  'membershipApi': 1,
  'locationSchema': 1,
};
void main() {
  test('release identity matches the unchanged Flutter version', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains(
        'version: ${ReleaseCompatibility.version}+${ReleaseCompatibility.build}',
      ),
    );
  });
  test('missing, unready or incomplete backend capabilities fail closed', () {
    expect(ReleaseCompatibility.blockingReason(null), 'preparing');
    expect(
      ReleaseCompatibility.blockingReason({...ready, 'ready': false}),
      'preparing',
    );
    expect(
      ReleaseCompatibility.blockingReason({...ready, 'reviewApi': 0}),
      'preparing',
    );
    expect(
      ReleaseCompatibility.blockingReason({...ready, 'minimumBuild': '21'}),
      'preparing',
    );
  });
  test(
    'supported release proceeds and a later minimum build requires an update',
    () {
      expect(ReleaseCompatibility.blockingReason(ready), isNull);
      expect(
        ReleaseCompatibility.blockingReason({
          ...ready,
          'minimumBuild': ReleaseCompatibility.build + 1,
        }),
        'update',
      );
    },
  );
  testWidgets(
    'unprepared backend does not expose the app and retry can recover',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ReleaseCompatibilityGate(
            child: const Text('LocalLink ready'),
            loadConfiguration: () async => ++calls == 1 ? null : ready,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('LocalLink ready'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('LocalLink ready'), findsOneWidget);
    },
  );
  testWidgets('network failure keeps unsupported app actions unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReleaseCompatibilityGate(
          child: const Text('LocalLink ready'),
          loadConfiguration: () async => throw Exception('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LocalLink ready'), findsNothing);
    expect(find.textContaining('could not check'), findsOneWidget);
  });
}
