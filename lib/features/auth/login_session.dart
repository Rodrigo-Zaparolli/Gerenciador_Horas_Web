import 'login_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class LoginSession {
  static Future<UserCredential> signIn({
    required FirebaseAuth auth,
    required String email,
    required String password,
    required bool keepConnected,
    bool web = kIsWeb,
    bool? preferLocalStorage,
  }) async {
    if (web) {
      if (keepConnected) {
        // Use the same durable backend that Firebase prefers when restoring
        // authentication after a browser restart. Never fall back to a
        // session-only login when the user requested a persistent session.
        try {
          await auth.setPersistence(
              (preferLocalStorage ?? prefersLocalAuthStorage())
                  ? Persistence.LOCAL
                  : Persistence.INDEXED_DB);
        } catch (_) {
          await auth.setPersistence(Persistence.LOCAL);
        }
      } else {
        await auth.setPersistence(Persistence.SESSION);
      }
    }
    return auth.signInWithEmailAndPassword(email: email, password: password);
  }
}
