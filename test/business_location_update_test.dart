import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/business_location_update.dart';

void main() {
  test('unrelated profile save leaves existing coordinates untouched', () {
    final update = BusinessLocationUpdate.build(
      originalAddress: 'Dundee',
      address: ' Dundee ',
    );
    expect(update, {'address': 'Dundee'});
  });
  test('changed address cannot reuse stale or unresolved map coordinates', () {
    expect(
      () => BusinessLocationUpdate.build(
        originalAddress: 'Dundee',
        address: 'Glasgow',
      ),
      throwsStateError,
    );
    expect(
      () => BusinessLocationUpdate.build(
        originalAddress: 'Dundee',
        address: 'Glasgow',
        selectedAddress: 'Dundee',
        latitude: 56.46,
        longitude: -2.97,
      ),
      throwsStateError,
    );
  });
  test('selected address and its coordinates form one atomic update', () {
    final update = BusinessLocationUpdate.build(
      originalAddress: 'Dundee',
      address: 'Glasgow',
      selectedAddress: 'Glasgow',
      latitude: 55.86,
      longitude: -4.25,
    );
    expect(update, {
      'address': 'Glasgow',
      'latitude': 55.86,
      'longitude': -4.25,
      'locationAddress': 'Glasgow',
    });
  });
  test(
    'invalid and placeholder locations never overwrite valid business coordinates',
    () {
      for (final pair in [
        [0.0, 0.0],
        [91.0, 2.0],
        [55.0, double.nan],
      ]) {
        expect(
          () => BusinessLocationUpdate.build(
            originalAddress: 'Dundee',
            address: 'Glasgow',
            selectedAddress: 'Glasgow',
            latitude: pair[0],
            longitude: pair[1],
          ),
          throwsStateError,
        );
      }
    },
  );
}
