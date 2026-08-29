import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/utils/single_flight_guard.dart';

void main() {
  test('SingleFlightGuard ignores repeated async work while running', () async {
    final guard = SingleFlightGuard();
    final completer = Completer<void>();
    var calls = 0;

    final first = guard.run(() async {
      calls += 1;
      await completer.future;
    });
    final second = await guard.run(() async {
      calls += 1;
    });

    expect(second, isNull);
    expect(calls, 1);
    expect(guard.isRunning, isTrue);

    completer.complete();
    await first;

    expect(guard.isRunning, isFalse);
  });
}
