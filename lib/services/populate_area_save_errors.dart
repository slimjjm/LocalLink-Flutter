import 'package:firebase_core/firebase_core.dart';

enum PopulateAreaSaveStage {
  authorization,
  duplicateCheck,
  imageUpload,
  listingSave,
}

String populateAreaSaveError(Object error, PopulateAreaSaveStage stage) {
  final code = error is FirebaseException ? error.code : '';
  final action = switch (stage) {
    PopulateAreaSaveStage.authorization => 'verify administrator access',
    PopulateAreaSaveStage.duplicateCheck => 'check for duplicate listings',
    PopulateAreaSaveStage.imageUpload => 'upload the business image',
    PopulateAreaSaveStage.listingSave =>
      'save the listing and moderator details',
  };
  if (code == 'permission-denied' || code == 'unauthorized') {
    return 'Permission denied: could not $action. Check your administrator access.';
  }
  if (code == 'unauthenticated' || code == 'unauthorized-app') {
    return 'Your session could not be verified. Sign in again before retrying.';
  }
  if (code == 'unavailable' ||
      code == 'network-request-failed' ||
      code == 'retry-limit-exceeded' ||
      code == 'deadline-exceeded') {
    return stage == PopulateAreaSaveStage.listingSave
        ? 'The connection failed while saving. Check existing listings before retrying.'
        : 'Could not $action because the connection failed. Check your connection and retry.';
  }
  if (code == 'invalid-argument') {
    return 'Could not $action: some information is invalid. Check the form details.';
  }
  if (stage == PopulateAreaSaveStage.imageUpload) {
    return 'Image upload failed. Check the image and try again. The listing was not saved.';
  }
  return 'Could not $action. Please try again. If it continues, contact support.';
}

String? populateAreaBusinessValidation({
  required String title,
  required String category,
  required String location,
  required double? latitude,
  required double? longitude,
  required double radius,
}) {
  final missing = <String>[
    if (title.trim().isEmpty) 'name',
    if (category.trim().isEmpty) 'category',
    if (location.trim().isEmpty) 'address/place',
  ];
  if (missing.isNotEmpty) return 'Add the business ${missing.join(', ')}.';
  if ((latitude == null) != (longitude == null) ||
      (latitude != null &&
          (!latitude.isFinite || latitude < -90 || latitude > 90)) ||
      (longitude != null &&
          (!longitude.isFinite || longitude < -180 || longitude > 180))) {
    return 'The address has invalid coordinates. Select the address again.';
  }
  if (!radius.isFinite || radius < 1 || radius > 30) {
    return 'Choose a service radius between 1 and 30 miles.';
  }
  return null;
}

const populateAreaImageSizeLimit = 8 * 1024 * 1024;
