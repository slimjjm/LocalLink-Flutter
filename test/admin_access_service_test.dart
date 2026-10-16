import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink_flutter/services/admin_access_service.dart';

void main() {
  test(
    'administrator check uses protected client projection, never private account',
    () async {
      final store = _Store({'isAdmin': false}, {'isAdmin': true});
      expect(
        await AdminAccessService(
          firestore: store,
          auth: _Auth(),
        ).isCurrentUserAdmin(),
        isTrue,
      );
      expect(store.reads, [
        'users/moderator',
        'users/moderator/private/access',
      ]);
    },
  );
  test(
    'negative access projection overrides a stale public admin flag',
    () async {
      final store = _Store({'isAdmin': true}, {'isAdmin': false});
      expect(
        await AdminAccessService(
          firestore: store,
          auth: _Auth(),
        ).isCurrentUserAdmin(),
        isFalse,
      );
      expect(store.reads, isNot(contains('users/moderator/private/account')));
    },
  );
}

class _Auth extends Fake implements FirebaseAuth {
  @override
  User? get currentUser => _User();
}

class _User extends Fake implements User {
  @override
  String get uid => 'moderator';
  @override
  String? get email => 'moderator@example.test';
}

class _Store extends Fake implements FirebaseFirestore {
  _Store(this.publicData, this.accessData);
  final Map<String, dynamic> publicData;
  final Map<String, dynamic> accessData;
  final List<String> reads = [];
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
}

// SDK snapshot/reference stand-ins; no Firebase app or network is initialized.
// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.store, this.path);
  final _Store store;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      _Reference(store, '$path/$id');
}

// ignore: subtype_of_sealed_class
class _Reference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.store, this.path);
  final _Store store;
  @override
  final String path;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(store, '${this.path}/$path');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    store.reads.add(path);
    if (path.endsWith('/private/account')) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    return _Snapshot(
      path.endsWith('/private/access') ? store.accessData : store.publicData,
    );
  }
}

// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.value);
  final Map<String, dynamic> value;
  @override
  bool get exists => true;
  @override
  Map<String, dynamic>? data() => value;
}
