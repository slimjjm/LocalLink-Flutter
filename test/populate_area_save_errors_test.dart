import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/populate_area_save_errors.dart';
import 'package:locallink_flutter/services/admin_access_service.dart';

void main() {
  test('private account is authoritative, including revocation', () {
    expect(
      AdminAccessService.hasEffectiveAdminFlag({}, {'isAdmin': true}),
      isTrue,
    );
    expect(
      AdminAccessService.hasEffectiveAdminFlag(
        {'isAdmin': true},
        {'isAdmin': false},
      ),
      isFalse,
    );
    expect(
      AdminAccessService.hasEffectiveAdminFlag({'isAdmin': true}, {}),
      isFalse,
    );
    expect(
      AdminAccessService.hasEffectiveAdminFlag({'isAdmin': true}, null),
      isTrue,
    );
    expect(AdminAccessService.hasEffectiveAdminFlag(null, null), isFalse);
  });
  test('errors identify permissions and the failed stage', () {
    for (final stage in PopulateAreaSaveStage.values) {
      final message = populateAreaSaveError(
        FirebaseException(plugin: 'test', code: 'permission-denied'),
        stage,
      );
      expect(message, contains('Permission denied'));
      expect(message, contains('administrator access'));
    }
    expect(
      populateAreaSaveError(
        FirebaseException(plugin: 'firebase_storage', code: 'unauthorized'),
        PopulateAreaSaveStage.imageUpload,
      ),
      contains('upload the business image'),
    );
    expect(
      populateAreaSaveError(Exception(), PopulateAreaSaveStage.duplicateCheck),
      contains('check for duplicate'),
    );
    expect(
      populateAreaSaveError(Exception(), PopulateAreaSaveStage.listingSave),
      contains('listing and moderator details'),
    );
    expect(
      populateAreaSaveError(Exception(), PopulateAreaSaveStage.imageUpload),
      contains('listing was not saved'),
    );
  });
  test('network, session and invalid payload errors are actionable', () {
    expect(
      populateAreaSaveError(
        FirebaseException(plugin: 'test', code: 'unavailable'),
        PopulateAreaSaveStage.listingSave,
      ),
      contains('connection'),
    );
    expect(
      populateAreaSaveError(
        FirebaseException(plugin: 'test', code: 'unauthenticated'),
        PopulateAreaSaveStage.authorization,
      ),
      contains('Sign in again'),
    );
    expect(
      populateAreaSaveError(
        FirebaseException(plugin: 'test', code: 'invalid-argument'),
        PopulateAreaSaveStage.listingSave,
      ),
      contains('information is invalid'),
    );
  });
  String? validate({
    String title = 'Cafe',
    String category = 'Cafe',
    String location = 'High Street',
    double? lat = 52.6,
    double? lng = -1.8,
    double radius = 5,
  }) => populateAreaBusinessValidation(
    title: title,
    category: category,
    location: location,
    latitude: lat,
    longitude: lng,
    radius: radius,
  );
  test('missing fields and invalid coordinate pairs are rejected', () {
    expect(
      validate(title: ' ', category: '', location: ''),
      contains('name, category, address/place'),
    );
    expect(validate(lat: double.nan), contains('coordinates'));
    expect(validate(lng: double.infinity), contains('coordinates'));
    expect(validate(lat: 91), contains('coordinates'));
    expect(validate(lng: -181), contains('coordinates'));
    expect(validate(lat: null), contains('coordinates'));
    expect(
      validate(lat: null, lng: null),
      isNull,
    ); // Existing manual address flow.
    expect(validate(), isNull);
  });
  test('radius respects existing slider limits', () {
    expect(validate(radius: 0), contains('radius'));
    expect(validate(radius: 31), contains('radius'));
    expect(validate(radius: double.nan), contains('radius'));
    expect(validate(radius: 1), isNull);
    expect(validate(radius: 30), isNull);
  });
}
