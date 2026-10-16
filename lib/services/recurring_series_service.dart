import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Each scope is checked by Firestore independently. A series ID never grants access.
List<Map<String, String>> recurringSeriesScopes({
  required String userId,
  required Map<String, dynamic> seed,
  bool isAdmin = false,
  bool organisationManager = false,
  bool groupLeader = false,
}) {
  if (userId.isEmpty) return [];
  final org = seed['organisationId'];
  final group = seed['groupId'];
  return [
    {'createdBy': userId},
    {'organiserId': userId},
    if (organisationManager && org is String && org.isNotEmpty)
      {'organisationId': org},
    if (groupLeader &&
        org is String &&
        org.isNotEmpty &&
        group is String &&
        group.isNotEmpty)
      {'organisationId': org, 'groupId': group},
    if (isAdmin) {},
  ];
}

/// Permission loss removes that scope's cached documents immediately. Other
/// authorised scopes remain usable; index/network failures remain visible.
Stream<List<T>> mergeRecurringSeriesStreams<T>(
  List<Stream<List<T>>> streams, {
  required String Function(T) id,
  required int Function(T, T) compare,
}) {
  late StreamController<List<T>> output;
  final subscriptions = <StreamSubscription<List<T>>>[];
  final values = <int, List<T>>{};
  bool stopped = false;
  void emit() {
    if (stopped) return;
    final unique = <String, T>{};
    for (final batch in values.values) {
      for (final item in batch) {
        unique[id(item)] = item;
      }
    }
    output.add(unique.values.toList()..sort(compare));
  }

  output = StreamController<List<T>>(
    onListen: () {
      if (streams.isEmpty) emit();
      for (var i = 0; i < streams.length; i++) {
        final scope = i;
        subscriptions.add(
          streams[i].listen(
            (items) {
              values[scope] = items;
              emit();
            },
            onError: (Object error, StackTrace stack) {
              values.remove(scope);
              emit();
              if (error is! FirebaseException ||
                  error.code != 'permission-denied') {
                output.addError(error, stack);
              }
            },
          ),
        );
      }
    },
    onCancel: () async {
      stopped = true;
      values.clear();
      await Future.wait(subscriptions.map((s) => s.cancel()));
    },
  );
  return output.stream;
}

class RecurringSeriesService {
  RecurringSeriesService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watch({
    required String opportunityId,
    required String seriesId,
    required String? userId,
    String? email,
    Stream<String?>? sessionUserIds,
  }) {
    if (userId == null || userId.isEmpty || seriesId.isEmpty) {
      return Stream.value([]);
    }
    late StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    output;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? seedWatch;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? adminWatch;
    StreamSubscription<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? rows;
    Map<String, dynamic>? seed;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? accountWatch;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? emailWatch;
    StreamSubscription<String?>? sessionWatch;
    Map<String, dynamic>? profile;
    Map<String, dynamic>? account;
    var accountExists = false;
    var emailEnabled = false;
    var admin = false;
    final authorityWatches =
        <StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>[];
    String? relationKey;
    Map<String, dynamic> organisation = {}, membership = {}, group = {};
    var organisationManager = false, groupLeader = false;
    var generation = 0;
    var stopped = false;
    void rebuild() {
      final epoch = ++generation;
      rows?.cancel();
      if (stopped) return;
      output.add([]); // Clear all old scopes when the seed/authority changes.
      if (seed == null || seed!['seriesId'] != seriesId) return;
      final streams =
          recurringSeriesScopes(
            userId: userId,
            seed: seed!,
            isAdmin: admin,
            organisationManager: organisationManager,
            groupLeader: groupLeader,
          ).map((scope) {
            Query<Map<String, dynamic>> query = _db
                .collection('opportunities')
                .where('seriesId', isEqualTo: seriesId);
            for (final filter in scope.entries) {
              query = query.where(filter.key, isEqualTo: filter.value);
            }
            return query
                .orderBy('eventDate')
                .snapshots(includeMetadataChanges: true)
                .map(
                  (s) => s.metadata.isFromCache
                      ? <QueryDocumentSnapshot<Map<String, dynamic>>>[]
                      : s.docs,
                );
          }).toList();
      rows =
          mergeRecurringSeriesStreams(
            streams,
            id: (d) => d.id,
            compare: (a, b) {
              final left = a.data()['eventDate'] as Timestamp;
              final right = b.data()['eventDate'] as Timestamp;
              final date = left.compareTo(right);
              return date == 0 ? a.id.compareTo(b.id) : date;
            },
          ).listen(
            (data) {
              if (!stopped && epoch == generation) output.add(data);
            },
            onError: (Object error, StackTrace stack) {
              if (!stopped && epoch == generation) {
                output.addError(error, stack);
              }
            },
          );
    }

    void watchAuthority() {
      final orgId = seed?['organisationId'];
      final groupId = seed?['groupId'];
      final key = '$orgId/$groupId';
      if (key == relationKey) return;
      relationKey = key;
      for (final watch in authorityWatches) {
        watch.cancel();
      }
      authorityWatches.clear();
      organisation = {};
      membership = {};
      group = {};
      organisationManager = false;
      groupLeader = false;
      if (orgId is! String || orgId.isEmpty) return;
      void refresh() {
        if (stopped || relationKey != key) return;
        final nextManager =
            (organisation['listingOwnershipStatus'] == 'claimed' &&
                (organisation['ownerId'] == userId ||
                    (organisation['adminUserIds'] is List &&
                        (organisation['adminUserIds'] as List).contains(
                          userId,
                        )))) ||
            (membership['status'] == 'active' &&
                [
                  'owner',
                  'organisation_admin',
                  'secretary',
                ].contains(membership['role']));
        final nextLeader =
            group['leaderUserIds'] is List &&
            (group['leaderUserIds'] as List).contains(userId);
        if (nextManager != organisationManager || nextLeader != groupLeader) {
          organisationManager = nextManager;
          groupLeader = nextLeader;
          rebuild();
        }
      }

      void watch(
        DocumentReference<Map<String, dynamic>> ref,
        void Function(Map<String, dynamic>) save,
      ) {
        authorityWatches.add(
          ref
              .snapshots(includeMetadataChanges: true)
              .listen(
                (doc) {
                  if (stopped || relationKey != key) return;
                  save(doc.metadata.isFromCache ? {} : doc.data() ?? {});
                  refresh();
                },
                onError: (Object error) {
                  if (stopped || relationKey != key) return;
                  save({});
                  refresh();
                },
              ),
        );
      }

      final orgRef = _db.collection('organisations').doc(orgId);
      watch(orgRef, (value) => organisation = value);
      watch(
        orgRef.collection('members').doc(userId),
        (value) => membership = value,
      );
      if (groupId is String && groupId.isNotEmpty) {
        watch(
          orgRef.collection('groups').doc(groupId),
          (value) => group = value,
        );
      }
    }

    output = StreamController(
      onListen: () {
        seedWatch = _db
            .collection('opportunities')
            .doc(opportunityId)
            .snapshots(includeMetadataChanges: true)
            .listen(
              (doc) {
                seed = doc.metadata.isFromCache ? null : doc.data();
                watchAuthority();
                rebuild();
              },
              onError: (Object error, StackTrace stack) {
                seed = null;
                watchAuthority();
                rebuild();
                if (!stopped) output.addError(error, stack);
              },
            );
        void refreshAdmin() {
          final next =
              (accountExists ? (account?['isAdmin']) : (profile?['isAdmin'])) ==
                  true ||
              emailEnabled;
          if (next != admin) {
            admin = next;
            rebuild();
          }
        }

        adminWatch = _db
            .collection('users')
            .doc(userId)
            .snapshots()
            .listen(
              (doc) {
                profile = doc.data();
                refreshAdmin();
              },
              onError: (Object error) {
                profile = null;
                refreshAdmin();
              },
            );
        accountWatch = _db
            .collection('users')
            .doc(userId)
            .collection('private')
            .doc('account')
            .snapshots()
            .listen(
              (doc) {
                accountExists = doc.exists;
                account = doc.data();
                refreshAdmin();
              },
              onError: (Object error) {
                accountExists = true;
                account = null;
                refreshAdmin();
              },
            );
        if (email == 'jae19882011@hotmail.co.uk' ||
            email == 'founder@locallinkapp.co.uk') {
          emailWatch = _db
              .collection('adminEmails')
              .doc(email)
              .snapshots()
              .listen(
                (doc) {
                  emailEnabled = doc.exists && doc.data()?['enabled'] != false;
                  refreshAdmin();
                },
                onError: (Object error) {
                  emailEnabled = false;
                  refreshAdmin();
                },
              );
        }
        sessionWatch = sessionUserIds?.listen((current) {
          if (current == userId || stopped) return;
          output.add([]);
          generation++;
          rows?.cancel();
          seedWatch?.cancel();
          adminWatch?.cancel();
          accountWatch?.cancel();
          emailWatch?.cancel();
          for (final watch in authorityWatches) {
            watch.cancel();
          }
          authorityWatches.clear();
          stopped = true;
        });
      },
      onCancel: () async {
        stopped = true;
        generation++;
        await seedWatch?.cancel();
        await adminWatch?.cancel();
        await accountWatch?.cancel();
        await emailWatch?.cancel();
        await sessionWatch?.cancel();
        await rows?.cancel();
        await Future.wait(authorityWatches.map((watch) => watch.cancel()));
        authorityWatches.clear();
      },
    );
    return output.stream;
  }
}
