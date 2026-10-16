import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'analytics_service.dart';
import 'notification_service.dart';

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
    await LocalLinkAnalytics.instance.logLogin(method: 'email');
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
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
    await LocalLinkAnalytics.instance.logSignUp(method: 'email');
  }

  // =====================================================
  // GOOGLE LOGIN
  // =====================================================

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');

      var stage = 'popup';
      try {
        final userCredential = await _auth.signInWithPopup(provider);
        stage = 'ensure-user-document';
        await _ensureUserDocument(userCredential.user);
        await _logAuthSuccess(userCredential, method: 'google');
        return userCredential;
      } catch (error, stackTrace) {
        _logWebAuthFailure(
          provider: 'Google',
          stage: stage,
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
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
    await _logAuthSuccess(userCredential, method: 'google');

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

      var stage = 'set-local-persistence';
      try {
        await _auth.setPersistence(Persistence.LOCAL);
        stage = 'popup';
        final userCredential = await _auth.signInWithPopup(provider);
        stage = 'ensure-user-document';
        await _ensureUserDocument(userCredential.user);
        await _logAuthSuccess(userCredential, method: 'apple');
        return userCredential;
      } catch (error, stackTrace) {
        _logWebAuthFailure(
          provider: 'Apple',
          stage: stage,
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
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
    await _logAuthSuccess(userCredential, method: 'apple');

    return userCredential;
  }

  Future<void> _logAuthSuccess(
    UserCredential credential, {
    required String method,
  }) async {
    if (credential.additionalUserInfo?.isNewUser == true) {
      await LocalLinkAnalytics.instance.logSignUp(method: method);
    } else {
      await LocalLinkAnalytics.instance.logLogin(method: method);
    }
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
    await NotificationService.shared.unregisterCurrentDevice();
    await _auth.signOut();
  }
}

void _logWebAuthFailure({
  required String provider,
  required String stage,
  required Object error,
  required StackTrace stackTrace,
}) {
  if (!kIsWeb) return;

  debugPrint('[$provider Web Auth] failed during $stage');
  debugPrint('[$provider Web Auth] exception type: ${error.runtimeType}');

  if (error is FirebaseAuthException) {
    debugPrint(
      '[$provider Web Auth] FirebaseAuthException.code: ${error.code}',
    );
    debugPrint(
      '[$provider Web Auth] FirebaseAuthException.message: ${error.message}',
    );
  } else if (error is FirebaseException) {
    debugPrint('[$provider Web Auth] FirebaseException.code: ${error.code}');
    debugPrint(
      '[$provider Web Auth] FirebaseException.message: ${error.message}',
    );
  } else if (error is PlatformException) {
    debugPrint('[$provider Web Auth] PlatformException.code: ${error.code}');
    debugPrint(
      '[$provider Web Auth] PlatformException.message: ${error.message}',
    );
    debugPrint(
      '[$provider Web Auth] PlatformException.details: ${error.details}',
    );
  } else {
    debugPrint('[$provider Web Auth] error: $error');
  }

  if (kDebugMode) {
    debugPrint('[$provider Web Auth] stack trace: $stackTrace');
  }
}
