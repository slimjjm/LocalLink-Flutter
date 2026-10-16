import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/organisation.dart';
import '../models/organisation_group.dart';
import '../models/organisation_role.dart';
import 'organisation_permissions.dart';
import 'organisation_discovery_service.dart';

class OrganisationService {
  OrganisationService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    OrganisationCurrentUserProvider? currentUserProvider,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
       _currentUserProvider = currentUserProvider ?? _firebaseCurrentUser;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final OrganisationCurrentUserProvider _currentUserProvider;

  String get currentUserId => _currentUserProvider()?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _organisations =>
      _firestore.collection('organisations');

  CollectionReference<Map<String, dynamic>> get _opportunities =>
      _firestore.collection('opportunities');

  CollectionReference<Map<String, dynamic>> _groups(String organisationId) =>
      _organisations.doc(organisationId).collection('groups');

  CollectionReference<Map<String, dynamic>> _organisationMembers(
    String organisationId,
  ) => _organisations.doc(organisationId).collection('members');

  CollectionReference<Map<String, dynamic>> _groupMembers(
    String organisationId,
    String groupId,
  ) => _groups(organisationId).doc(groupId).collection('members');

  CollectionReference<Map<String, dynamic>> _joinRequests(
    String organisationId,
    String groupId,
  ) => _groups(organisationId).doc(groupId).collection('joinRequests');

  CollectionReference<Map<String, dynamic>> _invitations(
    String organisationId,
  ) => _organisations.doc(organisationId).collection('invitations');

  CollectionReference<Map<String, dynamic>> _announcements(
    String organisationId,
  ) => _organisations.doc(organisationId).collection('announcements');

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOrganisation(
    String organisationId,
  ) {
    return _organisations.doc(organisationId).snapshots();
  }

  Stream<List<Organisation>> watchModeratorSeededOrganisations({String? area}) {
    return _organisations
        .where('createdByModerator', isEqualTo: true)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .where(
                (doc) =>
                    OrganisationDiscoveryService.isDiscoverable(doc.data()),
              )
              .map(Organisation.fromFirestore)
              .where(
                (organisation) => area == null || organisation.area == area,
              )
              .toList();
          items.sort((a, b) => a.name.compareTo(b.name));
          return items;
        });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOrganisationActivities(
    String organisationId,
  ) {
    return _opportunities
        .where('organisationId', isEqualTo: organisationId)
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPublicOrganisationActivities(
    String organisationId,
  ) {
    return _opportunities
        .where('organisationId', isEqualTo: organisationId)
        .where('discoveryVisibility', isEqualTo: 'public')
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  Stream<List<OrganisationGroup>> watchGroups(String organisationId) {
    final user = _currentUserProvider();
    final uid = user?.isAnonymous == false ? user!.uid : '';
    final groups = _groups(organisationId);
    final buckets = <String, List<OrganisationGroup>>{};
    final sourceSubscriptions = <StreamSubscription>[];
    final controlSubscriptions = <StreamSubscription>[];
    var organisationManager = false;
    var roleManager = false;
    var memberGroupIds = <String>[];
    var generation = 0;
    var cancelled = false;
    late StreamController<List<OrganisationGroup>> controller;

    void emit() {
      if (controller.isClosed || cancelled) return;
      final unique = <String, OrganisationGroup>{};
      for (final records in buckets.values) {
        for (final group in records) {
          unique[group.id] = group;
        }
      }
      final result = unique.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      controller.add(result);
    }

    void error(String key, Object error) {
      buckets.remove(key);
      emit();
      if (!(error is FirebaseException && error.code == 'permission-denied') &&
          !cancelled) {
        controller.addError(error);
      }
    }

    void listenQuery(String key, Query<Map<String, dynamic>> query) {
      sourceSubscriptions.add(
        query.snapshots().listen((snapshot) {
          buckets[key] = snapshot.docs
              .map(OrganisationGroup.fromFirestore)
              .toList();
          emit();
        }, onError: (Object issue) => error(key, issue)),
      );
    }

    Future<void> restart() async {
      final revision = ++generation;
      final old = sourceSubscriptions.toList();
      sourceSubscriptions.clear();
      buckets.clear();
      emit();
      await Future.wait(old.map((subscription) => subscription.cancel()));
      if (revision != generation || controller.isClosed || cancelled) return;
      if (organisationManager || roleManager) {
        listenQuery('managed', groups.where('isActive', isEqualTo: true));
        return;
      }
      listenQuery(
        'public',
        groups
            .where('isActive', isEqualTo: true)
            .where('discoveryVisibility', isEqualTo: 'public'),
      );
      if (uid.isEmpty) return;
      listenQuery(
        'led',
        groups
            .where('isActive', isEqualTo: true)
            .where('leaderUserIds', arrayContains: uid),
      );
      for (final id in memberGroupIds.toSet()) {
        if (id.isEmpty || id.contains('/')) continue;
        sourceSubscriptions.add(
          groups.doc(id).snapshots().listen((snapshot) {
            buckets['member:$id'] =
                snapshot.exists && snapshot.data()?['isActive'] == true
                ? [OrganisationGroup.fromFirestore(snapshot)]
                : [];
            emit();
          }, onError: (Object issue) => error('member:$id', issue)),
        );
      }
    }

    controller = StreamController<List<OrganisationGroup>>(
      onListen: () {
        unawaited(restart());
        if (uid.isEmpty) return;
        controlSubscriptions.add(
          _organisations
              .doc(organisationId)
              .snapshots()
              .listen(
                (snapshot) {
                  final data = snapshot.data() ?? {};
                  organisationManager =
                      data['listingOwnershipStatus'] == 'claimed' &&
                      (data['ownerId'] == uid ||
                          (data['adminUserIds'] is List &&
                              (data['adminUserIds'] as List).contains(uid)));
                  unawaited(restart());
                },
                onError: (Object issue) {
                  organisationManager = false;
                  unawaited(restart());
                  error('organisation', issue);
                },
              ),
        );
        controlSubscriptions.add(
          _organisationMembers(organisationId)
              .doc(uid)
              .snapshots()
              .listen(
                (snapshot) {
                  final data = snapshot.data() ?? {};
                  roleManager =
                      data['status'] == 'active' &&
                      const [
                        'owner',
                        'organisation_admin',
                        'secretary',
                      ].contains(data['role']);
                  memberGroupIds =
                      data['status'] == 'active' && data['groupIds'] is List
                      ? (data['groupIds'] as List).whereType<String>().toList()
                      : [];
                  unawaited(restart());
                },
                onError: (Object issue) {
                  roleManager = false;
                  memberGroupIds = [];
                  unawaited(restart());
                  error('membership', issue);
                },
              ),
        );
      },
      onCancel: () async {
        cancelled = true;
        generation++;
        await Future.wait(
          [
            ...sourceSubscriptions,
            ...controlSubscriptions,
          ].map((subscription) => subscription.cancel()),
        );
      },
    );
    return controller.stream;
  }

  Stream<List<OrganisationMembership>> watchOrganisationPeople(
    String organisationId,
  ) {
    return _organisationMembers(organisationId).snapshots().map((snapshot) {
      final people = snapshot.docs
          .map(OrganisationMembership.fromFirestore)
          .toList();
      people.sort((a, b) => a.userName.compareTo(b.userName));
      return people;
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOrganisationMembership({
    required String organisationId,
    required String userId,
  }) {
    return _organisationMembers(organisationId).doc(userId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOrganisationInvitations(
    String organisationId,
  ) {
    return _invitations(
      organisationId,
    ).where('status', isEqualTo: 'pending').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOrganisationAnnouncements(
    String organisationId,
  ) {
    return _announcements(organisationId).limit(20).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchGroup(
    String organisationId,
    String groupId,
  ) {
    return _groups(organisationId).doc(groupId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchGroupActivities({
    required String organisationId,
    required String groupId,
    bool canManage = false,
  }) {
    Query<Map<String, dynamic>> query = _opportunities
        .where('organisationId', isEqualTo: organisationId)
        .where('groupId', isEqualTo: groupId)
        .where('isActive', isEqualTo: true);
    // Manager flags only select a query; Firestore remains authoritative.
    if (!canManage) {
      query = query.where(
        Filter.or(
          Filter('activityAudienceScope', isEqualTo: 'group'),
          Filter('discoveryVisibility', isEqualTo: 'public'),
        ),
      );
    }
    return query.snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchGroupMembership({
    required String organisationId,
    required String groupId,
    required String userId,
  }) {
    return _groupMembers(organisationId, groupId).doc(userId).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchJoinRequest({
    required String organisationId,
    required String groupId,
    required String userId,
  }) {
    return _joinRequests(organisationId, groupId).doc(userId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchGroupMembers({
    required String organisationId,
    required String groupId,
  }) {
    return _groupMembers(
      organisationId,
      groupId,
    ).where('status', isEqualTo: 'active').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchGroupJoinRequests({
    required String organisationId,
    required String groupId,
  }) {
    return _joinRequests(
      organisationId,
      groupId,
    ).where('status', isEqualTo: 'pending').snapshots();
  }

  Future<DocumentReference<Map<String, dynamic>>>
  createSelfServiceOrganisation({
    required String name,
    required String category,
    required String location,
    required String description,
    double? latitude,
    double? longitude,
  }) async {
    final user = _currentUserProvider();
    if (user == null || user.isAnonymous) {
      throw StateError('Sign in required.');
    }

    final ref = _organisations.doc();
    await ref.set(
      selfServiceOrganisationData(
        user: user,
        name: name,
        category: category,
        location: location,
        description: description,
        latitude: latitude,
        longitude: longitude,
      ),
    );
    return ref;
  }

  Future<void> invitePerson({
    required String organisationId,
    required String email,
    required String role,
    String groupId = '',
    List<String> groupIds = const [],
    String displayRole = '',
  }) async {
    final groups = _normaliseUserIds([
      if (groupId.trim().isNotEmpty) groupId.trim(),
      ...groupIds,
    ]);
    await _functions.httpsCallable('sendOrganisationInvitation').call({
      'organisationId': organisationId,
      'email': email.trim(),
      'role': normaliseOrganisationRole(role),
      'groupId': groups.isEmpty ? '' : groups.first,
      'groupIds': groups,
      'displayRole': displayRole.trim(),
    });
  }

  Future<void> acceptInvitation({required String token}) async {
    await _functions.httpsCallable('acceptOrganisationInvitation').call({
      'token': token.trim(),
    });
  }

  Future<void> updatePersonRole({
    required String organisationId,
    required String userId,
    required String role,
    String groupId = '',
    List<String> groupIds = const [],
    String displayRole = '',
  }) async {
    final groups = _normaliseUserIds([
      if (groupId.trim().isNotEmpty) groupId.trim(),
      ...groupIds,
    ]);
    await _functions.httpsCallable('updateOrganisationPersonRole').call({
      'organisationId': organisationId,
      'userId': userId.trim(),
      'role': normaliseOrganisationRole(role),
      'groupId': groups.isEmpty ? '' : groups.first,
      'groupIds': groups,
      'displayRole': displayRole.trim(),
    });
  }

  Future<void> removePerson({
    required String organisationId,
    required String userId,
  }) async {
    await _functions.httpsCallable('removeOrganisationPerson').call({
      'organisationId': organisationId,
      'userId': userId.trim(),
    });
  }

  Future<void> archiveOrganisation({required String organisationId}) async {
    await _functions.httpsCallable('archiveOrganisation').call({
      'organisationId': organisationId,
    });
  }

  Future<void> restoreOrganisation({required String organisationId}) async {
    await _functions.httpsCallable('restoreOrganisation').call({
      'organisationId': organisationId,
    });
  }

  Future<void> publishOrganisationAnnouncement({
    required String organisationId,
    required String message,
    String groupId = '',
    String groupName = '',
  }) async {
    await _functions.httpsCallable('publishOrganisationAnnouncement').call({
      'organisationId': organisationId,
      'message': message.trim(),
      'groupId': groupId.trim(),
      'groupName': groupName.trim(),
    });
  }

  Future<void> markAnnouncementRead({
    required String organisationId,
    required String announcementId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    await _announcements(
      organisationId,
    ).doc(announcementId).collection('reads').doc(user.uid).set({
      'userId': user.uid,
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Map<String, dynamic> selfServiceOrganisationData({
    required OrganisationCurrentUser user,
    required String name,
    required String category,
    required String location,
    required String description,
    double? latitude,
    double? longitude,
  }) {
    final trimmedLocation = location.trim();
    final data = <String, dynamic>{
      'name': name.trim(),
      'description': description.trim(),
      'category': category.trim(),
      'subcategories': const [],
      'area': trimmedLocation,
      'publicLocation': trimmedLocation,
      'location': trimmedLocation,
      'phone': '',
      'email': user.email ?? '',
      'website': '',
      'imageUrl': '',
      'capabilities': OrganisationCapabilities.defaultsFor(
        category: category,
        name: name,
      ).toMap(),
      'ownerId': user.uid,
      'adminUserIds': [user.uid],
      'createdBy': user.uid,
      'createdByModerator': false,
      'claimStatus': 'approved',
      'listingOwnershipStatus': 'claimed',
      'isActive': true,
      'selfServiceCreated': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (latitude != null) data['latitude'] = latitude;
    if (longitude != null) data['longitude'] = longitude;
    return data;
  }

  Future<DocumentReference<Map<String, dynamic>>> createGroup({
    required Organisation organisation,
    required String name,
    required String description,
    required String displayType,
    required String category,
    required String subcategory,
    required String ageLabel,
    required String membershipMode,
    List<String> leaderUserIds = const [],
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Sign in required.');
    }

    final ref = _groups(organisation.id).doc();
    final leaders = _normaliseUserIds(leaderUserIds);
    await ref.set({
      'name': name.trim(),
      'description': description.trim(),
      'displayType': displayType.trim().isEmpty ? 'group' : displayType.trim(),
      'category': category.trim().isEmpty
          ? organisation.category
          : category.trim(),
      'subcategory': subcategory.trim(),
      'ageLabel': ageLabel.trim(),
      'leaderUserIds': leaders,
      'isActive': true,
      'visibility': 'public',
      'discoveryVisibility': 'public',
      'membershipMode': membershipMode,
      'memberCount': 0,
      'imageUrl': '',
      'createdBy': user.uid,
      'updatedBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref;
  }

  Future<void> updateGroup({
    required OrganisationGroup group,
    required String name,
    required String description,
    required String displayType,
    required String category,
    required String subcategory,
    required String ageLabel,
    required String membershipMode,
    required List<String> leaderUserIds,
    String? imageUrl,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Sign in required.');
    }

    await _groups(group.organisationId).doc(group.id).update({
      'name': name.trim(),
      'description': description.trim(),
      'displayType': displayType.trim().isEmpty ? 'group' : displayType.trim(),
      'category': category.trim(),
      'subcategory': subcategory.trim(),
      'ageLabel': ageLabel.trim(),
      'membershipMode': membershipMode,
      'leaderUserIds': _normaliseUserIds(leaderUserIds),
      if (imageUrl != null) 'imageUrl': imageUrl.trim(),
      'updatedBy': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> joinOrRequestGroup({
    required Organisation organisation,
    required OrganisationGroup group,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Sign in required.');
    }
    if (group.isInviteOnly) return 'invite_only';

    final userName = _displayName(user);
    if (group.isOpenMembership) {
      await _addMember(
        organisationId: organisation.id,
        groupId: group.id,
        userId: user.uid,
        userName: userName,
        role: 'member',
      );
      return 'active';
    }

    await _joinRequests(organisation.id, group.id).doc(user.uid).set({
      'userId': user.uid,
      'userName': userName,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return 'pending';
  }

  Future<void> approveJoinRequest({
    required Organisation organisation,
    required OrganisationGroup group,
    required String userId,
    required String userName,
  }) async {
    final reviewer = FirebaseAuth.instance.currentUser;
    if (reviewer == null || reviewer.isAnonymous) {
      throw StateError('Sign in required.');
    }

    await _addMember(
      organisationId: organisation.id,
      groupId: group.id,
      userId: userId,
      userName: userName,
      role: 'member',
    );
    await _joinRequests(organisation.id, group.id).doc(userId).set({
      'status': 'approved',
      'reviewedBy': reviewer.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> declineJoinRequest({
    required Organisation organisation,
    required OrganisationGroup group,
    required String userId,
  }) async {
    final reviewer = FirebaseAuth.instance.currentUser;
    if (reviewer == null || reviewer.isAnonymous) {
      throw StateError('Sign in required.');
    }

    await _joinRequests(organisation.id, group.id).doc(userId).set({
      'status': 'declined',
      'reviewedBy': reviewer.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> leaveGroup({
    required String organisationId,
    required String groupId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Sign in required.');
    }
    await removeMember(
      organisationId: organisationId,
      groupId: groupId,
      userId: user.uid,
    );
  }

  Future<void> removeMember({
    required String organisationId,
    required String groupId,
    required String userId,
  }) async {
    final groupMemberRef = _groupMembers(organisationId, groupId).doc(userId);
    final orgMemberRef = _organisationMembers(organisationId).doc(userId);
    final groupRef = _groups(organisationId).doc(groupId);

    await _firestore.runTransaction((transaction) async {
      final memberSnap = await transaction.get(groupMemberRef);
      if (!memberSnap.exists || memberSnap.data()?['status'] != 'active') {
        return;
      }

      transaction.update(groupMemberRef, {
        'status': 'removed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(orgMemberRef, {
        'groupIds': FieldValue.arrayRemove([groupId]),
        'membershipGroupId': groupId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      transaction.update(groupRef, {
        'memberCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<DocumentReference<Map<String, dynamic>>> createModeratorOrganisation(
    Map<String, dynamic> data,
  ) async {
    final ref = _organisations.doc();
    await ref.set(data);
    return ref;
  }

  Future<void> _addMember({
    required String organisationId,
    required String groupId,
    required String userId,
    required String userName,
    required String role,
  }) async {
    final groupMemberRef = _groupMembers(organisationId, groupId).doc(userId);
    final orgMemberRef = _organisationMembers(organisationId).doc(userId);
    final groupRef = _groups(organisationId).doc(groupId);

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(groupMemberRef);
      final existingOrganisationMember = await transaction.get(orgMemberRef);
      final alreadyActive =
          existing.exists && existing.data()?['status'] == 'active';

      transaction.set(groupMemberRef, {
        'userId': userId,
        'userName': userName,
        'role': role,
        'status': 'active',
        'createdAt':
            existing.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(orgMemberRef, {
        'userId': userId,
        'userName': userName,
        'role': existingOrganisationMember.data()?['role'] ?? 'member',
        'status': 'active',
        'groupIds': FieldValue.arrayUnion([groupId]),
        'createdAt':
            existingOrganisationMember.data()?['createdAt'] ??
            FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!alreadyActive) {
        transaction.update(groupRef, {
          'memberCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  static bool canManageOrganisation(Organisation organisation, String? uid) {
    return OrganisationPermissions.isDirectOwnerOrAdmin(organisation, uid);
  }

  static bool canManageGroup({
    required Organisation organisation,
    required OrganisationGroup group,
    required String? uid,
    String organisationRole = '',
  }) {
    return OrganisationPermissions.canManageGroup(
      organisation: organisation,
      group: group,
      uid: uid,
      organisationRole: organisationRole,
    );
  }

  static bool isAuthorityAlsoMembership({
    required Organisation organisation,
    required OrganisationGroup group,
    required String uid,
    required bool hasMembership,
  }) {
    if (!canManageGroup(organisation: organisation, group: group, uid: uid)) {
      return hasMembership;
    }
    return hasMembership;
  }

  static List<String> _normaliseUserIds(List<String> values) {
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  static String _displayName(User user) {
    final name = user.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email;
    return 'LocalLink member';
  }

  static OrganisationCurrentUser? _firebaseCurrentUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return OrganisationCurrentUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      isAnonymous: user.isAnonymous,
    );
  }
}

typedef OrganisationCurrentUserProvider = OrganisationCurrentUser? Function();

class OrganisationCurrentUser {
  const OrganisationCurrentUser({
    required this.uid,
    this.email,
    this.displayName,
    this.isAnonymous = false,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final bool isAnonymous;
}
