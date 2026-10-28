import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gerenciador_horas/firebase_options.dart';
import 'package:gerenciador_horas/features/auth/login_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    final auth = FirebaseAuth.instance;
    final user = await auth.authStateChanges().first;
    web.window.setProperty('probeUid'.toJS, (user?.uid ?? '').toJS);
    web.window.setProperty(
        'probeLogin'.toJS,
        ((JSBoolean keep) => LoginSession.signIn(
                    auth: auth,
                    email: 'fixture@example.invalid',
                    password: 'fixture-only',
                    keepConnected: keep.toDart)
                .then((credential) {
              web.window
                  .setProperty('probeUid'.toJS, credential.user!.uid.toJS);
              return true.toJS;
            }).toJS).toJS);
    web.window.setProperty('probeReady'.toJS, true.toJS);
  } catch (error) {
    web.window.setProperty('probeError'.toJS, error.toString().toJS);
  }
}
