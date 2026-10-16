// SDK interfaces are substituted only in tests to exercise listener lifecycle.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/organisation_service.dart';

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
        '${i.positionalArguments.first}:$value',
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
    if (i.memberName == #data) return payload;
    return super.noSuchMethod(i);
  }
}

class MemoryResults implements QuerySnapshot<Map<String, dynamic>> {
  MemoryResults(this.documents);
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> documents;
  @override
  dynamic noSuchMethod(Invocation i) =>
      i.memberName == #docs ? documents : super.noSuchMethod(i);
}

class NoFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> settle() async {
  for (var n = 0; n < 4; n++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'member sees public and assigned private groups; removal clears private data and cancels listeners',
    () async {
      final store = MemoryStore();
      final service = OrganisationService(
        firestore: store,
        functions: NoFunctions(),
        currentUserProvider: () => const OrganisationCurrentUser(uid: 'member'),
      );
      var ids = <String>[];
      final subscription = service
          .watchGroups('org')
          .listen((groups) => ids = groups.map((g) => g.id).toList());
      await settle();
      store.emit(
        'organisations/org',
        MemorySnapshot(store, 'organisations/org', {
          'ownerId': 'owner',
          'listingOwnershipStatus': 'claimed',
        }),
      );
      await settle();
      store.emit(
        'organisations/org/members/member',
        MemorySnapshot(store, 'organisations/org/members/member', {
          'role': 'member',
          'status': 'active',
          'groupIds': ['private'],
        }),
      );
      await settle();
      store.emit(
        'organisations/org/groups|isActive:true|discoveryVisibility:public',
        MemoryResults([
          MemorySnapshot(store, 'organisations/org/groups/public', {
            'name': 'A',
            'isActive': true,
            'visibility': 'public',
          }),
        ]),
      );
      store.emit(
        'organisations/org/groups/private',
        MemorySnapshot(store, 'organisations/org/groups/private', {
          'name': 'B',
          'isActive': true,
          'visibility': 'private',
        }),
      );
      await settle();
      expect(ids, ['public', 'private']);
      expect(
        store.sources['organisations/org/groups|isActive:true']?.hasListener ??
            false,
        false,
      );
      store.emit(
        'organisations/org/members/member',
        MemorySnapshot(store, 'organisations/org/members/member', {
          'status': 'removed',
        }),
      );
      await settle();
      expect(ids, isNot(contains('private')));
      expect(
        store.sources['organisations/org/groups/private']!.hasListener,
        false,
      );
      await subscription.cancel();
      expect(store.sources.values.any((s) => s.hasListener), false);
      for (final source in store.sources.values) {
        await source.close();
      }
    },
  );
  test('organisation owner uses the authorised management query', () async {
    final store = MemoryStore();
    final service = OrganisationService(
      firestore: store,
      functions: NoFunctions(),
      currentUserProvider: () => const OrganisationCurrentUser(uid: 'owner'),
    );
    final sub = service.watchGroups('org').listen((_) {});
    await settle();
    store.emit(
      'organisations/org',
      MemorySnapshot(store, 'organisations/org', {
        'ownerId': 'owner',
        'listingOwnershipStatus': 'claimed',
      }),
    );
    await settle();
    expect(
      store.sources['organisations/org/groups|isActive:true']!.hasListener,
      true,
    );
    await sub.cancel();
    for (final source in store.sources.values) {
      await source.close();
    }
  });
  test('anonymous browsing subscribes only to public groups', () async {
    final store = MemoryStore();
    final service = OrganisationService(
      firestore: store,
      functions: NoFunctions(),
      currentUserProvider: () =>
          const OrganisationCurrentUser(uid: 'guest', isAnonymous: true),
    );
    final sub = service.watchGroups('org').listen((_) {});
    await settle();
    expect(store.sources.keys, [
      'organisations/org/groups|isActive:true|discoveryVisibility:public',
    ]);
    await sub.cancel();
    for (final source in store.sources.values) {
      await source.close();
    }
  });
}
