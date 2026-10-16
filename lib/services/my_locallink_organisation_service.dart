import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/organisation.dart';
import '../models/organisation_role.dart';

class ManagedOrganisationEntry {
  const ManagedOrganisationEntry({
    required this.organisation,
    required this.role,
    this.activityCount,
  });

  final Organisation organisation;
  final String role;
  final Object? activityCount;
}

class MyLocalLinkOrganisationService {
  MyLocalLinkOrganisationService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<ManagedOrganisationEntry>> loadManagedOrganisations(
    String uid,
  ) async {
    return _loadOrganisations(uid: uid, includeArchived: false);
  }

  Future<List<ManagedOrganisationEntry>> loadArchivedOrganisations(
    String uid,
  ) async {
    return _loadOrganisations(uid: uid, includeArchived: true);
  }

  Future<List<ManagedOrganisationEntry>> _loadOrganisations({
    required String uid,
    required bool includeArchived,
  }) async {
    final organisationCandidates = <String, Map<String, dynamic>>{};
    final rolesById = <String, String>{};

    Future<void> addOrganisationQuery({
      required String label,
      required String field,
      required Object value,
      required String fallbackRole,
    }) async {
      var query = _firestore
          .collection('organisations')
          .where(field, isEqualTo: value)
          .where('isActive', isEqualTo: !includeArchived);
      if (includeArchived || field == 'createdBy') {
        query = query.where('listingOwnershipStatus', isEqualTo: 'claimed');
      }
      final snapshot = await _runLookup(label, query.get);
      for (final doc in snapshot.docs) {
        organisationCandidates[doc.id] = doc.data();
        rolesById[doc.id] = _highestRole(rolesById[doc.id], fallbackRole);
      }
    }

    await addOrganisationQuery(
      label: 'ownerId',
      field: 'ownerId',
      value: uid,
      fallbackRole: organisationRoleOwner,
    );
    if (usesCreatedByLookup(includeArchived: includeArchived)) {
      await addOrganisationQuery(
        label: 'createdBy',
        field: 'createdBy',
        value: uid,
        fallbackRole: organisationRoleOwner,
      );
    }

    if (usesAdminUserIdsLookup(includeArchived: includeArchived)) {
      final adminQuery = _firestore
          .collection('organisations')
          .where('adminUserIds', arrayContains: uid)
          .where('isActive', isEqualTo: true);
      final adminSnapshot = await _runLookup('adminUserIds', adminQuery.get);
      for (final doc in adminSnapshot.docs) {
        organisationCandidates[doc.id] = doc.data();
        rolesById[doc.id] = _highestRole(
          rolesById[doc.id],
          doc.data()['ownerId'] == uid || doc.data()['createdBy'] == uid
              ? organisationRoleOwner
              : organisationRoleAdmin,
        );
      }
    }

    final roleSnapshot = await _runOptionalLookup(
      'user organisation role index lookup',
      () => _firestore
          .collection('users')
          .doc(uid)
          .collection('organisationRoles')
          .where('status', isEqualTo: 'active')
          .get(),
    );

    final memberOrganisationRefs = <DocumentReference<Map<String, dynamic>>>{};
    for (final roleDoc in roleSnapshot?.docs ?? const []) {
      final data = roleDoc.data();
      final role = _normaliseAccessRole(data['role']?.toString() ?? '');
      if (data['status'] != 'active' || !_isManagerRole(role)) continue;

      final organisationRef = _firestore
          .collection('organisations')
          .doc(roleDoc.id);
      memberOrganisationRefs.add(organisationRef);
      rolesById[organisationRef.id] = _highestRole(
        rolesById[organisationRef.id],
        role,
      );
    }

    final memberOrganisations = await Future.wait(
      memberOrganisationRefs.map(
        (ref) => _runOptionalLookup(
          'user organisation role parent lookup ${ref.path}',
          ref.get,
        ),
      ),
    );
    for (final doc in memberOrganisations) {
      if (doc != null && doc.exists) {
        organisationCandidates[doc.id] = doc.data() ?? const {};
      }
    }

    return entriesFromCandidateData(
      uid: uid,
      organisationDataById: organisationCandidates,
      rolesById: rolesById,
      includeArchived: includeArchived,
    );
  }

  static List<ManagedOrganisationEntry> entriesFromCandidateData({
    required String uid,
    required Map<String, Map<String, dynamic>> organisationDataById,
    Map<String, String> rolesById = const {},
    bool includeArchived = false,
  }) {
    final entries = <ManagedOrganisationEntry>[];
    for (final item in organisationDataById.entries) {
      final data = item.value;
      final role = _highestRole(rolesById[item.key], _roleFromData(data, uid));
      if (!isManageableOrganisationData(
        data,
        uid,
        role: role,
        includeArchived: includeArchived,
      )) {
        continue;
      }

      entries.add(
        ManagedOrganisationEntry(
          organisation: Organisation.fromMap(item.key, data),
          role: role,
          activityCount: data['activityCount'],
        ),
      );
    }

    entries.sort((a, b) => a.organisation.name.compareTo(b.organisation.name));
    return entries;
  }

  @visibleForTesting
  static bool usesCreatedByLookup({required bool includeArchived}) {
    return !includeArchived;
  }

  @visibleForTesting
  static bool usesAdminUserIdsLookup({required bool includeArchived}) {
    return !includeArchived;
  }

  static bool isManageableOrganisationData(
    Map<String, dynamic> data,
    String uid, {
    String? role,
    bool includeArchived = false,
  }) {
    if (uid.trim().isEmpty) return false;
    final isArchived = data['isActive'] == false;
    if (includeArchived != isArchived) return false;
    if (!_isApprovedOrClaimed(data)) return false;

    return data['ownerId']?.toString() == uid ||
        data['createdBy']?.toString() == uid ||
        _listContains(data['adminUserIds'], uid) ||
        _isManagerRole(_normaliseAccessRole(role ?? ''));
  }

  static bool _isApprovedOrClaimed(Map<String, dynamic> data) {
    return data['listingOwnershipStatus']?.toString() == 'claimed' ||
        data['claimStatus']?.toString() == 'approved';
  }

  static String _roleFromData(Map<String, dynamic> data, String uid) {
    if (data['ownerId']?.toString() == uid ||
        data['createdBy']?.toString() == uid) {
      return organisationRoleOwner;
    }
    if (_listContains(data['adminUserIds'], uid)) {
      return organisationRoleAdmin;
    }
    return organisationRoleMember;
  }

  static bool _isManagerRole(String role) {
    return role == organisationRoleOwner ||
        role == organisationRoleAdmin ||
        role == organisationRoleSecretary ||
        role == organisationRoleGroupLeader;
  }

  static bool _listContains(Object? value, String uid) {
    return value is Iterable &&
        value.map((item) => item.toString()).contains(uid);
  }

  static String _highestRole(String? current, String? next) {
    const order = {
      organisationRoleOwner: 4,
      organisationRoleAdmin: 3,
      organisationRoleSecretary: 2,
      organisationRoleGroupLeader: 1,
      organisationRoleMember: 0,
    };
    final normalisedCurrent = _normaliseAccessRole(current ?? '');
    final normalisedNext = _normaliseAccessRole(next ?? '');
    return (order[normalisedNext] ?? 0) > (order[normalisedCurrent] ?? 0)
        ? normalisedNext
        : normalisedCurrent;
  }

  static String _normaliseAccessRole(String role) {
    return switch (role) {
      organisationRoleOwner => organisationRoleOwner,
      organisationRoleAdmin => organisationRoleAdmin,
      organisationRoleSecretary => organisationRoleSecretary,
      organisationRoleGroupLeader => organisationRoleGroupLeader,
      _ => organisationRoleMember,
    };
  }

  Future<T> _runLookup<T>(String label, Future<T> Function() query) async {
    try {
      return await query();
    } catch (error, stackTrace) {
      _logLookupFailure(label, error, stackTrace);
      rethrow;
    }
  }

  Future<T?> _runOptionalLookup<T>(
    String label,
    Future<T> Function() query,
  ) async {
    try {
      return await query();
    } catch (error, stackTrace) {
      _logLookupFailure(label, error, stackTrace);
      return null;
    }
  }

  void _logLookupFailure(String label, Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;

    debugPrint('MyLocalLinkOrganisationService lookup failed: $label');
    if (error is FirebaseException) {
      debugPrint('Firestore code: ${error.code}');
      debugPrint('Firestore message: ${error.message ?? error.toString()}');
    } else {
      debugPrint('Exception type: ${error.runtimeType}');
      debugPrint('Exception message: $error');
    }
    debugPrintStack(stackTrace: stackTrace);
  }
}
