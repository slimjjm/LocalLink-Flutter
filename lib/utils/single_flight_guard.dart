class SingleFlightGuard {
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  Future<T?> run<T>(Future<T> Function() action) async {
    if (_isRunning) return null;

    _isRunning = true;
    try {
      return await action();
    } finally {
      _isRunning = false;
    }
  }
}
