import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class AuthService {

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  // =====================================================
  // LOGIN
  // =====================================================

  Future<void> login({

    required String email,
    required String password,

  }) async {

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

 final credential =
    await _auth
        .createUserWithEmailAndPassword(

  email: email.trim(),

  password: password.trim(),
);

await credential.user
    ?.updateDisplayName(
  name.trim(),
);

await FirebaseFirestore.instance
    .collection('users')
    .doc(
      credential.user!.uid,
    )
    .set({

  'name': name.trim(),

  'photoUrl': '',

  'bio': '',

  'reviewCount': 0,

  'ratingTotal': 0,

  'averageRating': 0.0,

  'createdAt':
      Timestamp.now(),

});
  }

  // =====================================================
  // GOOGLE LOGIN
  // =====================================================

  Future<UserCredential>
      signInWithGoogle() async {

    final GoogleSignInAccount?
        googleUser =
            await GoogleSignIn().signIn();

    if (googleUser == null) {

      throw Exception(
        'Google sign in cancelled',
      );
    }

    final GoogleSignInAuthentication
        googleAuth =
            await googleUser.authentication;

    final credential =
        GoogleAuthProvider.credential(

      accessToken:
          googleAuth.accessToken,

      idToken:
          googleAuth.idToken,
    );

    return await _auth
        .signInWithCredential(
      credential,
    );
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
    (_) => charset[
        random.nextInt(charset.length)],
  ).join();
}

String _sha256ofString(
  String input,
) {

  final bytes =
      utf8.encode(input);

  final digest =
      sha256.convert(bytes);

  return digest.toString();
}

Future<UserCredential>
    signInWithApple() async {

  final rawNonce =
      _generateNonce();

  final nonce =
      _sha256ofString(
    rawNonce,
  );

  final appleCredential =
      await SignInWithApple
          .getAppleIDCredential(
    scopes: [
      AppleIDAuthorizationScopes.email,
      AppleIDAuthorizationScopes.fullName,
    ],
    nonce: nonce,
  );

  if (appleCredential.identityToken == null) {
  throw Exception('Apple identity token was null');
}

final oauthCredential =
    OAuthProvider('apple.com').credential(
  idToken: appleCredential.identityToken!,
  accessToken: appleCredential.authorizationCode,
  rawNonce: rawNonce,
);

  return await _auth
      .signInWithCredential(
    oauthCredential,
  );
}
  // =====================================================
  // LOGOUT
  // =====================================================

  Future<void> logout() async {

    await _auth.signOut();
  }
}