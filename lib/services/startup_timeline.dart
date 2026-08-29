import 'package:flutter/foundation.dart';

class StartupTimeline {
  StartupTimeline._();

  static final Stopwatch _stopwatch = Stopwatch();

  static void start() {
    if (!_stopwatch.isRunning) {
      _stopwatch.start();
    }
  }

  static void log(String message) {
    if (!kDebugMode) return;

    if (!_stopwatch.isRunning) {
      _stopwatch.start();
    }

    debugPrint('[Startup +${_stopwatch.elapsedMilliseconds}ms] $message');
  }
}
