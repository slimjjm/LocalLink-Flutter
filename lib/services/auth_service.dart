import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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

    required String email,
    required String password,

  }) async {

    await _auth
        .createUserWithEmailAndPassword(

      email: email.trim(),

      password: password.trim(),
    );
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

Future<UserCredential>
    signInWithApple() async {

  final appleCredential =
      await SignInWithApple
          .getAppleIDCredential(
    scopes: [
      AppleIDAuthorizationScopes.email,
      AppleIDAuthorizationScopes.fullName,
    ],
  );

  final oauthCredential =
      OAuthProvider("apple.com")
          .credential(
    idToken:
        appleCredential.identityToken,
    rawNonce: null,
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