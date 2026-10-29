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
        // Select the same durable backend on login and the next startup.
        // A successful session-only fallback must never satisfy this option.
        final useLocal = preferLocalStorage ?? true;
        if (useLocal) {
          if (!prepareLocalAuthStorage()) {
            throw FirebaseAuthException(
                code: 'web-storage-unsupported',
                message:
                    'O navegador bloqueou o armazenamento permanente do login.');
          }
          await auth.setPersistence(Persistence.LOCAL);
        } else {
          try {
            await auth.setPersistence(Persistence.INDEXED_DB);
          } catch (_) {
            if (!prepareLocalAuthStorage()) rethrow;
            await auth.setPersistence(Persistence.LOCAL);
          }
        }
      } else {
        await auth.setPersistence(Persistence.SESSION);
      }
    }
    return auth.signInWithEmailAndPassword(email: email, password: password);
  }
}
