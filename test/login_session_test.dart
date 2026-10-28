import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/auth/login_session.dart';
import 'package:gerenciador_horas/features/auth/screens/login_screen.dart';
import 'package:flutter/material.dart';

class Credential extends Fake implements UserCredential {}

class Auth extends Fake implements FirebaseAuth {
  final events = <Object>[];
  Completer<void>? persistenceWait;
  bool failPersistence = false;
  bool failIndexedDb = false;
  @override
  Future<void> setPersistence(Persistence value) async {
    events.add(value);
    if (failPersistence) throw StateError('storage unavailable');
    if (failIndexedDb && value == Persistence.INDEXED_DB) {
      throw StateError('indexed database unavailable');
    }
    if (persistenceWait != null) await persistenceWait!.future;
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword(
      {required String email, required String password}) async {
    events.add('login:$email');
    return Credential();
  }
}

void main() {
  test(
      'Waits for local persistence before authenticating; unchecked uses session',
      () async {
    final auth = Auth()..persistenceWait = Completer<void>();
    final login = LoginSession.signIn(
        auth: auth,
        email: 'user@example.com',
        password: 'test',
        keepConnected: true,
        web: true);
    await Future<void>.delayed(Duration.zero);
    expect(auth.events, [Persistence.INDEXED_DB]);
    auth.persistenceWait!.complete();
    await login;
    expect(auth.events, [Persistence.INDEXED_DB, 'login:user@example.com']);
    auth.events.clear();
    await LoginSession.signIn(
        auth: auth,
        email: 'user@example.com',
        password: 'test',
        keepConnected: false,
        web: true);
    expect(auth.events, [Persistence.SESSION, 'login:user@example.com']);
  });
  test('Persistence failure does not log in with the wrong session policy',
      () async {
    final auth = Auth()..failPersistence = true;
    await expectLater(
        LoginSession.signIn(
            auth: auth,
            email: 'user@example.com',
            password: 'test',
            keepConnected: true,
            web: true),
        throwsStateError);
    expect(auth.events, [Persistence.INDEXED_DB, Persistence.LOCAL]);
  });
  test('Unavailable IndexedDB falls back to durable local storage', () async {
    final auth = Auth()..failIndexedDb = true;
    await LoginSession.signIn(
        auth: auth,
        email: 'user@example.com',
        password: 'test',
        keepConnected: true,
        web: true);
    expect(auth.events, [
      Persistence.INDEXED_DB,
      Persistence.LOCAL,
      'login:user@example.com',
    ]);
  });
  test('Recovered profile never selects IndexedDB during sign-in', () async {
    final auth = Auth()..failIndexedDb = true;
    await LoginSession.signIn(
        auth: auth,
        email: 'user@example.com',
        password: 'test',
        keepConnected: true,
        web: true,
        preferLocalStorage: true);
    expect(auth.events, [Persistence.LOCAL, 'login:user@example.com']);
    auth.events.clear();
    await LoginSession.signIn(
        auth: auth,
        email: 'user@example.com',
        password: 'test',
        keepConnected: false,
        web: true,
        preferLocalStorage: true);
    expect(auth.events, [Persistence.SESSION, 'login:user@example.com']);
  });
  test('Native authentication keeps its existing platform behavior', () async {
    final auth = Auth();
    await LoginSession.signIn(
        auth: auth,
        email: 'user@example.com',
        password: 'test',
        keepConnected: true,
        web: false);
    expect(auth.events, ['login:user@example.com']);
  });
  testWidgets(
      'Keep connected defaults to enabled and can be unchecked on small screens',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(MaterialApp(home: LoginScreen(onLoginSuccess: () {})));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    expect(tester.takeException(), isNull);
  });
}
