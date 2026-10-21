import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class LoginSession {
  static Future<UserCredential> signIn({
    required FirebaseAuth auth,
    required String email,
    required String password,
    required bool keepConnected,
    bool web = kIsWeb,
  }) async {
    if (web) {
      await auth.setPersistence(
        keepConnected ? Persistence.LOCAL : Persistence.SESSION,
      );
    }
    return auth.signInWithEmailAndPassword(email: email, password: password);
  }
}
