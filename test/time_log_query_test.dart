// In-memory Firestore test doubles; production uses the SDK classes directly.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';

class TestUser extends Fake implements User {
  TestUser(this.uid);
  @override
  final String uid;
}

class TestAuth extends Fake implements FirebaseAuth {
  User? user = TestUser('a');
  @override
  User? get currentUser => user;
}

class TestDocument extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  TestDocument(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic> value;
  @override
  Map<String, dynamic> data() => value;
}

class TestSnapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  TestSnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

class TestDatabase extends Fake implements FirebaseFirestore {
  final documents = <String, List<TestDocument>>{};
  final streams = <TestQuery>[];
  bool failCompleted = false;
  String? failPath;
  void Function(String)? onRead;
  final serverReads = <String>[];
  int subscriptions = 0;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      TestQuery(this, path);
  void emit() {
    for (final query in streams) {
      query.emit();
    }
  }

  Future<void> close() async {
    for (final query in streams) {
      await query.controller?.close();
    }
  }
}

class TestReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  TestReference(this.db, this.path);
  final TestDatabase db;
  @override
  final String path;
  @override
  CollectionReference<Map<String, dynamic>> collection(String name) =>
      TestQuery(db, '$path/$name');
}

// This test double deliberately owns a mutable subscription controller.
// ignore: must_be_immutable
class TestQuery extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  TestQuery(this.db, this.path, {this.start, this.end});
  final TestDatabase db;
  @override
  final String path;
  final Timestamp? start, end;
  StreamController<QuerySnapshot<Map<String, dynamic>>>? controller;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? name]) =>
      TestReference(db, '$path/$name');
  TestSnapshot snapshot() =>
      TestSnapshot((db.documents[path] ?? []).where((doc) {
        if (start == null) return true;
        final date = doc.value['date'];
        return date is Timestamp &&
            date.compareTo(start!) >= 0 &&
            date.compareTo(end!) < 0;
      }).toList());
  void emit() {
    if (controller?.hasListener == true) controller!.add(snapshot());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      return TestQuery(db, path,
          start: invocation.namedArguments[#isGreaterThanOrEqualTo]
                  as Timestamp? ??
              start,
          end: invocation.namedArguments[#isLessThan] as Timestamp? ?? end);
    }
    if (invocation.memberName == #get) {
      final options = invocation.positionalArguments.isNotEmpty
          ? invocation.positionalArguments.first as GetOptions?
          : null;
      if (options?.source == Source.server) db.serverReads.add(path);
      db.onRead?.call(path);
      if (path == db.failPath) {
        return Future<QuerySnapshot<Map<String, dynamic>>>.error(
            StateError('Offline'));
      }
      if (db.failCompleted && path.endsWith('completed_projects')) {
        return Future<QuerySnapshot<Map<String, dynamic>>>.error(
            StateError('Offline'));
      }
      return Future<QuerySnapshot<Map<String, dynamic>>>.value(snapshot());
    }
    if (invocation.memberName == #snapshots) {
      db.subscriptions++;
      controller =
          StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast(
              onListen: () => scheduleMicrotask(emit));
      db.streams.add(this);
      return controller!.stream;
    }
    return super.noSuchMethod(invocation);
  }
}

TestDocument hour(String id, DateTime date, {bool legacy = false}) =>
    TestDocument(id, {
      if (!legacy) 'date': Timestamp.fromDate(date),
      'createdAt': Timestamp.fromDate(date),
      'durationFormatted': '01:00',
      'isRegistered': true,
      'startTime': '08:00',
      'endTime': '09:00',
    });
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late TestDatabase db;
  late TestAuth auth;
  late TimeLogStore store;
  setUp(() {
    db = TestDatabase();
    auth = TestAuth();
    db.documents['users/a/completed_projects'] = [
      TestDocument('archived', {'id': 'archived'})
    ];
    db.documents['users/a/projects/p/time_logs'] = [
      hour('old', DateTime(2026, 9, 1)),
      hour('current', DateTime(2026, 10, 12))
    ];
    db.documents['users/a/projects/archived/time_logs'] = [
      hour('archived-hour', DateTime(2026, 8, 1))
    ];
    store = TimeLogStore(firestore: db, auth: auth);
  });
  tearDown(() async {
    store.dispose();
    await db.close();
  });
  test('daily voice preparation reads server independently of history scope',
      () async {
    final day = DateTime(2026, 10, 15);
    db.documents['users/a/projects'] = [TestDocument('p', {})];
    db.documents['users/a/projects/p/time_logs']!.addAll([
      hour('today', day),
      hour('legacy-today', day, legacy: true),
      TestDocument(
          'timer', {'date': Timestamp.fromDate(day), 'isRegistered': false}),
      TestDocument('no-date', {'isRegistered': true}),
    ]);
    db.documents['users/a/projects/archived/time_logs']!
        .add(hour('archived-today', day));
    await store.startListeningToProjects(['p']);
    await settle();
    await store.setHistoryPeriod(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
    await settle();
    final subscriptions = db.subscriptions;
    final found = await store.loadRegisteredDay(day);
    expect(found.map((log) => log.id).toSet(),
        {'today', 'legacy-today', 'archived-today'});
    expect(db.subscriptions, subscriptions);
    expect(
        db.serverReads,
        containsAll([
          'users/a/projects',
          'users/a/completed_projects',
          'users/a/projects/p/time_logs',
          'users/a/projects/archived/time_logs'
        ]));
  });
  test('daily preparation aborts entirely if one project fails', () async {
    db.documents['users/a/projects'] = [TestDocument('p', {})];
    db.failPath = 'users/a/projects/p/time_logs';
    await expectLater(
        store.loadRegisteredDay(DateTime(2026, 10, 15)), throwsStateError);
  });
  test('daily preparation rejects changed or unauthenticated account',
      () async {
    db.onRead = (_) => auth.user = TestUser('b');
    await expectLater(
        store.loadRegisteredDay(DateTime(2026, 10, 15)), throwsStateError);
    auth.user = null;
    await expectLater(
        store.loadRegisteredDay(DateTime(2026, 10, 15)), throwsStateError);
  });
  test('dashboard revisits retain listeners and all project hours', () async {
    await store.startListeningToProjects(['p']);
    await settle();
    expect(db.subscriptions, 2);
    expect(store.logs.length, 3);
    await store.startListeningToProjects(['p']);
    await settle();
    expect(db.subscriptions, 2);
    expect(store.lastSubscriptionChanges, 0);
    expect(store.logs.length, 3);
  });
  test(
      'period queries preserve older cached totals and handle deletions in range',
      () async {
    await store.startListeningToProjects(['p']);
    await settle();
    await store.setHistoryPeriod(DateTime(2026, 10, 1), DateTime(2026, 10, 31));
    await settle();
    expect(db.subscriptions, 4);
    expect(db.streams.last.start, isNotNull);
    expect(store.logs.length, 3);
    db.documents['users/a/projects/p/time_logs']!
        .removeWhere((doc) => doc.id == 'current');
    db.emit();
    await settle();
    expect(store.logs.map((log) => log.id).toSet(), {'old', 'archived-hour'});
    await store.setHistoryPeriod(null, null);
    await settle();
    expect(db.streams.last.start, isNull);
    expect(store.logs.length, 2);
  });
  test('legacy date documents keep full queries instead of disappearing',
      () async {
    db.documents['users/a/projects/p/time_logs'] = [
      hour('legacy', DateTime(2026, 10, 12), legacy: true)
    ];
    await store.startListeningToProjects(['p']);
    await settle();
    await store.setHistoryPeriod(DateTime(2026, 10, 1), DateTime(2026, 10, 31));
    await settle();
    expect(store.logs.any((log) => log.id == 'legacy'), isTrue);
    expect(
        db.subscriptions, 3); // Only the non-legacy archived project switches.
  });
  test('failed archive discovery preserves known archived hours and can retry',
      () async {
    await store.startListeningToProjects(['p']);
    await settle();
    db.failCompleted = true;
    await store.startListeningToProjects(['p']);
    await settle();
    expect(store.logs.length, 3);
    expect(store.loadError, isNotNull);
    db.failCompleted = false;
    await store.retryListening();
    await settle();
    expect(store.loadError, isNull);
    expect(store.logs.length, 3);
  });
  test('switching account clears cache and ignores previous account streams',
      () async {
    await store.startListeningToProjects(['p']);
    await settle();
    auth.user = TestUser('b');
    db.documents['users/b/projects/p/time_logs'] = [
      hour('b-hour', DateTime(2026, 10, 12))
    ];
    await store.startListeningToProjects(['p']);
    await settle();
    db.emit();
    await settle();
    expect(store.logs.map((log) => log.id), ['b-hour']);
  });
}
