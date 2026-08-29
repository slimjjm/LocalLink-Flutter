import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // =====================================================
  // LOGIN
  // =====================================================

  Future<void> login({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),

      password: password.trim(),
    );
  }

  // =====================================================
  // REGISTER
  // =====================================================

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),

      password: password.trim(),
    );

    await credential.user?.updateDisplayName(name.trim());
    await credential.user?.sendEmailVerification();

    await FirebaseFirestore.instance
        .collection('users')
        .doc(credential.user!.uid)
        .set({
          'name': name.trim(),

          'userName': name.trim(),

          'photoUrl': '',

          'bio': '',

          'reviewCount': 0,

          'ratingTotal': 0,

          'averageRating': 0.0,

          'createdAt': Timestamp.now(),
        });
  }

  // =====================================================
  // GOOGLE LOGIN
  // =====================================================

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');

      final userCredential = await _auth.signInWithPopup(provider);
      await _ensureUserDocument(userCredential.user);
      return userCredential;
    }

    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

    if (googleUser == null) {
      throw Exception('Google sign in cancelled');
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,

      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);

    await _ensureUserDocument(userCredential.user);

    return userCredential;
  }
  // =====================================================
  // APPLE LOGIN
  // =====================================================

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';

    final random = Random.secure();

    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);

    final digest = sha256.convert(bytes);

    return digest.toString();
  }

  Future<UserCredential> signInWithApple() async {
    if (kIsWeb) {
      final provider = OAuthProvider('apple.com')
        ..addScope('email')
        ..addScope('name');

      final userCredential = await _auth.signInWithPopup(provider);
      await _ensureUserDocument(userCredential.user);
      return userCredential;
    }

    final rawNonce = _generateNonce();

    final nonce = _sha256ofString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    if (appleCredential.identityToken == null) {
      throw Exception('Apple identity token was null');
    }

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken!,
      accessToken: appleCredential.authorizationCode,
      rawNonce: rawNonce,
    );

    final userCredential = await _auth.signInWithCredential(oauthCredential);

    final fullName = [appleCredential.givenName, appleCredential.familyName]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');

    if (fullName.isNotEmpty &&
        (userCredential.user?.displayName == null ||
            userCredential.user!.displayName!.trim().isEmpty)) {
      await userCredential.user?.updateDisplayName(fullName);
    }

    await _ensureUserDocument(userCredential.user, name: fullName);

    return userCredential;
  }

  Future<void> _ensureUserDocument(User? user, {String? name}) async {
    if (user == null) {
      return;
    }

    final userDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final snapshot = await userDoc.get();

    if (snapshot.exists) {
      return;
    }

    final fallbackName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : null;

    final resolvedName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : fallbackName?.isNotEmpty == true
        ? fallbackName!
        : 'LocalLink user';

    await userDoc.set({
      'name': resolvedName,
      'userName': resolvedName,
      'photoUrl': user.photoURL ?? '',
      'bio': '',
      'reviewCount': 0,
      'ratingTotal': 0,
      'averageRating': 0.0,
      'createdAt': Timestamp.now(),
    });
  }
  // =====================================================
  // LOGOUT
  // =====================================================

  Future<void> logout() async {
    await _auth.signOut();
  }
}
