import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
  // LOGOUT
  // =====================================================

  Future<void> logout() async {

    await _auth.signOut();
  }
}