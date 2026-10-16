// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:locallink_flutter/services/organisation_service.dart';
import 'package:locallink_flutter/services/recurring_series_service.dart';

class NoFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class MemoryMetadata implements SnapshotMetadata {
  const MemoryMetadata([this.isFromCache = false]);
  @override
  final bool isFromCache;
  @override
  bool get hasPendingWrites => false;
}

class MemoryStore implements FirebaseFirestore {
  final sources = <String, StreamController<dynamic>>{};
  Stream<dynamic> stream(String key) =>
      (sources[key] ??= StreamController<dynamic>.broadcast()).stream;
  void emit(String key, dynamic value) => sources[key]!.add(value);
  @override
  dynamic noSuchMethod(Invocation i) => i.memberName == #collection
      ? MemoryQuery(this, i.positionalArguments.first as String)
      : super.noSuchMethod(i);
}

class MemoryQuery implements CollectionReference<Map<String, dynamic>> {
  MemoryQuery(this.store, this.path, [this.filters = const []]);
  final MemoryStore store;
  @override
  final String path;
  final List<String> filters;
  String get key => [path, ...filters].join('|');
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #where) {
      final value =
          i.namedArguments[#arrayContains] ?? i.namedArguments[#isEqualTo];
      return MemoryQuery(store, path, [
        ...filters,
        i.positionalArguments.first is Filter
            ? 'audience:scoped'
            : '${i.positionalArguments.first}:$value',
      ]);
    }
    if (i.memberName == #orderBy) {
      return MemoryQuery(store, path, [
        ...filters,
        'order:${i.positionalArguments.first}',
      ]);
    }
    if (i.memberName == #snapshots) {
      return store.stream(key).cast<QuerySnapshot<Map<String, dynamic>>>();
    }
    if (i.memberName == #doc) {
      return MemoryDocument(store, '$path/${i.positionalArguments.first}');
    }
    if (i.memberName == #parent) {
      return MemoryDocument(
        store,
        path.split('/').take(path.split('/').length - 1).join('/'),
      );
    }
    return super.noSuchMethod(i);
  }
}

class MemoryDocument implements DocumentReference<Map<String, dynamic>> {
  MemoryDocument(this.store, this.path);
  final MemoryStore store;
  @override
  final String path;
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #id) return path.split('/').last;
    if (i.memberName == #parent) {
      return MemoryQuery(
        store,
        path.split('/').take(path.split('/').length - 1).join('/'),
      );
    }
    if (i.memberName == #collection) {
      return MemoryQuery(store, '$path/${i.positionalArguments.first}');
    }
    if (i.memberName == #snapshots) {
      return store.stream(path).cast<DocumentSnapshot<Map<String, dynamic>>>();
    }
    return super.noSuchMethod(i);
  }
}

class MemorySnapshot implements QueryDocumentSnapshot<Map<String, dynamic>> {
  MemorySnapshot(this.store, this.path, this.payload);
  final MemoryStore store;
  final String path;
  final Map<String, dynamic> payload;
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #id) return path.split('/').last;
    if (i.memberName == #reference) return MemoryDocument(store, path);
    if (i.memberName == #exists) return true;
    if (i.memberName == #metadata) return const MemoryMetadata();
    if (i.memberName == #data) return payload;
    return super.noSuchMethod(i);
  }
}

class MemoryResults implements QuerySnapshot<Map<String, dynamic>> {
  MemoryResults(this.documents);
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> documents;
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #metadata) return const MemoryMetadata();
    if (i.memberName == #docs) return documents;
    return super.noSuchMethod(i);
  }
}

Future<void> settle() async {
  for (var n = 0; n < 5; n++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'creator-only legacy and organiser scopes never use bare series IDs',
    () {
      expect(recurringSeriesScopes(userId: 'u', seed: {}), [
        {'createdBy': 'u'},
        {'organiserId': 'u'},
      ]);
      expect(recurringSeriesScopes(userId: '', seed: {}), isEmpty);
    },
  );
  test(
    'linked scopes constrain both organisation and group; admin is explicit',
    () {
      final scopes = recurringSeriesScopes(
        userId: 'u',
        seed: {'organisationId': 'o', 'groupId': 'g'},
        organisationManager: true,
        groupLeader: true,
      );
      expect(scopes[3], {'organisationId': 'o', 'groupId': 'g'});
      expect(scopes.every((s) => s.isNotEmpty), isTrue);
      expect(
        recurringSeriesScopes(userId: 'admin', seed: {}, isAdmin: true).last,
        isEmpty,
      );
      expect(
        recurringSeriesScopes(
          userId: 'u',
          seed: {'organisationId': 12, 'groupId': 'g'},
        ).length,
        2,
      );
    },
  );
  test(
    'adapter uses exact scoped ordered queries and clears seed revocation',
    () async {
      final store = MemoryStore(), rows = <List<String>>[], errors = <Object>[];
      final subscription = RecurringSeriesService(firestore: store)
          .watch(opportunityId: 'seed', seriesId: 's', userId: 'u')
          .listen(
            (docs) => rows.add(docs.map((d) => d.id).toList()),
            onError: errors.add,
          );
      await settle();
      store.emit(
        'opportunities/seed',
        MemorySnapshot(store, 'opportunities/seed', {
          'seriesId': 's',
          'organisationId': 'o',
          'groupId': 'g',
        }),
      );
      await settle();
      const creator = 'opportunities|seriesId:s|createdBy:u|order:eventDate';
      const organiser =
          'opportunities|seriesId:s|organiserId:u|order:eventDate';
      const group =
          'opportunities|seriesId:s|organisationId:o|groupId:g|order:eventDate';
      expect(store.sources[creator]!.hasListener, isTrue);
      store.emit(
        'organisations/o/groups/g',
        MemorySnapshot(store, 'organisations/o/groups/g', {
          'leaderUserIds': ['u'],
        }),
      );
      await settle();
      expect(store.sources[group]!.hasListener, isTrue);
      expect(
        store.sources.containsKey('opportunities|seriesId:s|order:eventDate'),
        isFalse,
      );
      final late = MemorySnapshot(store, 'opportunities/late', {
        'eventDate': Timestamp.fromDate(DateTime(2030, 1, 2)),
      });
      final early = MemorySnapshot(store, 'opportunities/early', {
        'eventDate': Timestamp.fromDate(DateTime(2030, 1, 1)),
      });
      store.emit(creator, MemoryResults([late]));
      store.emit(organiser, MemoryResults([late, early]));
      await settle();
      expect(rows.last, ['early', 'late']);
      store.sources['opportunities/seed']!.addError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      await settle();
      expect(rows.last, isEmpty);
      expect(errors, isNotEmpty);
      expect(store.sources[creator]!.hasListener, isFalse);
      await subscription.cancel();
      expect(store.sources.values.every((c) => !c.hasListener), isTrue);
    },
  );
  test(
    'adapter cancels all cached scopes on sign-out or account switch',
    () async {
      final store = MemoryStore(),
          session = StreamController<String?>(),
          rows = <List<String>>[];
      final subscription = RecurringSeriesService(firestore: store)
          .watch(
            opportunityId: 'seed',
            seriesId: 's',
            userId: 'u',
            sessionUserIds: session.stream,
          )
          .listen((docs) => rows.add(docs.map((d) => d.id).toList()));
      await settle();
      store.emit(
        'opportunities/seed',
        MemorySnapshot(store, 'opportunities/seed', {'seriesId': 's'}),
      );
      await settle();
      store.emit(
        'opportunities|seriesId:s|createdBy:u|order:eventDate',
        MemoryResults([
          MemorySnapshot(store, 'opportunities/a', {
            'eventDate': Timestamp.now(),
          }),
        ]),
      );
      await settle();
      expect(rows.last, ['a']);
      session.add('other');
      await settle();
      expect(rows.last, isEmpty);
      expect(store.sources.values.every((c) => !c.hasListener), isTrue);
      await subscription.cancel();
      await session.close();
    },
  );
  test(
    'private account overrides legacy admin profile and revocation cancels admin query',
    () async {
      final store = MemoryStore();
      final subscription = RecurringSeriesService(firestore: store)
          .watch(opportunityId: 'seed', seriesId: 's', userId: 'admin')
          .listen((_) {});
      await settle();
      store.emit(
        'opportunities/seed',
        MemorySnapshot(store, 'opportunities/seed', {'seriesId': 's'}),
      );
      store.emit(
        'users/admin/private/account',
        MemorySnapshot(store, 'users/admin/private/account', {'isAdmin': true}),
      );
      await settle();
      const admin = 'opportunities|seriesId:s|order:eventDate';
      expect(store.sources[admin]!.hasListener, isTrue);
      store.emit(
        'users/admin',
        MemorySnapshot(store, 'users/admin', {'isAdmin': true}),
      );
      store.emit(
        'users/admin/private/account',
        MemorySnapshot(store, 'users/admin/private/account', {
          'isAdmin': false,
        }),
      );
      await settle();
      expect(store.sources[admin]!.hasListener, isFalse);
      await subscription.cancel();
    },
  );
  test(
    'authority change clears private rows and cancels a live group query without changing the activity',
    () async {
      final store = MemoryStore(), rows = <List<String>>[];
      final subscription = RecurringSeriesService(firestore: store)
          .watch(opportunityId: 'seed', seriesId: 's', userId: 'leader')
          .listen((docs) => rows.add(docs.map((d) => d.id).toList()));
      await settle();
      store.emit(
        'opportunities/seed',
        MemorySnapshot(store, 'opportunities/seed', {
          'seriesId': 's',
          'organisationId': 'o',
          'groupId': 'g',
        }),
      );
      await settle();
      store.emit(
        'organisations/o/groups/g',
        MemorySnapshot(store, 'organisations/o/groups/g', {
          'leaderUserIds': ['leader'],
        }),
      );
      await settle();
      const scope =
          'opportunities|seriesId:s|organisationId:o|groupId:g|order:eventDate';
      store.emit(
        scope,
        MemoryResults([
          MemorySnapshot(store, 'opportunities/private', {
            'eventDate': Timestamp.now(),
          }),
        ]),
      );
      await settle();
      expect(rows.last, ['private']);
      store.emit(
        'organisations/o/groups/g',
        MemorySnapshot(store, 'organisations/o/groups/g', {
          'leaderUserIds': [],
        }),
      );
      await settle();
      expect(rows.last, isEmpty);
      expect(store.sources[scope]!.hasListener, isFalse);
      await subscription.cancel();
    },
  );
  test(
    'actual group feed scopes members while preserving the manager legacy query',
    () async {
      final store = MemoryStore();
      final service = OrganisationService(
        firestore: store,
        functions: NoFunctions(),
        currentUserProvider: () => const OrganisationCurrentUser(uid: 'member'),
      );
      final member = service
          .watchGroupActivities(organisationId: 'o', groupId: 'g')
          .listen((_) {});
      final manager = service
          .watchGroupActivities(
            organisationId: 'o',
            groupId: 'g',
            canManage: true,
          )
          .listen((_) {});
      await settle();
      expect(
        store
            .sources['opportunities|organisationId:o|groupId:g|isActive:true|audience:scoped']!
            .hasListener,
        isTrue,
      );
      expect(
        store
            .sources['opportunities|organisationId:o|groupId:g|isActive:true']!
            .hasListener,
        isTrue,
      );
      await member.cancel();
      await manager.cancel();
    },
  );
  test('mixed scopes deduplicate, sort and clear revoked rows', () async {
    final a = StreamController<List<String>>();
    final b = StreamController<List<String>>();
    final events = <List<String>>[];
    final subscription = mergeRecurringSeriesStreams(
      [a.stream, b.stream],
      id: (s) => s,
      compare: (a, b) => a.compareTo(b),
    ).listen(events.add);
    a.add(['legacy', 'shared']);
    b.add(['private', 'shared']);
    await Future<void>.delayed(Duration.zero);
    expect(events.last, ['legacy', 'private', 'shared']);
    b.addError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(events.last, ['legacy', 'shared']);
    await subscription.cancel();
    expect(a.hasListener, isFalse);
    expect(b.hasListener, isFalse);
    await a.close();
    await b.close();
  });
  test(
    'index and network failures stay visible and clear their cached scope',
    () async {
      final source = StreamController<List<String>>();
      final rows = <List<String>>[], errors = <Object>[];
      final subscription = mergeRecurringSeriesStreams(
        [source.stream],
        id: (s) => s,
        compare: (a, b) => a.compareTo(b),
      ).listen(rows.add, onError: errors.add);
      source.add(['private']);
      await Future<void>.delayed(Duration.zero);
      source.addError(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'failed-precondition',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(rows.last, isEmpty);
      expect(errors.length, 1);
      await subscription.cancel();
      await source.close();
    },
  );
}
