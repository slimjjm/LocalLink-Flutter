import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/utils/helpers.dart';

void main() {
  group('safeInitial', () {
    test('returns a capital initial for display names', () {
      expect(safeInitial('James'), 'J');
      expect(safeInitial('  local link'), 'L');
    });

    test('falls back safely for missing names', () {
      expect(safeInitial(null), '?');
      expect(safeInitial(''), '?');
      expect(safeInitial('   '), '?');
    });
  });
}
