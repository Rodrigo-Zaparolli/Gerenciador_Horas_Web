// In-memory SDK doubles for transaction failures and identity checks.
// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/received_work_store.dart';
import 'package:gerenciador_horas/features/edesk/received_work.dart';
import 'backup_restore_test.dart'
    show
        MemoryFirestore,
        MemoryCollection,
        MemoryDocument,
        MemorySnapshot,
        MemoryQuery;

class ImportUser extends Fake implements User {
  @override
  String get uid => 'owner';
  @override
  String get email => 'rodrigozaparolli79@gmail.com';
}

class ImportAuth extends Fake implements FirebaseAuth {
  User? user = ImportUser();
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() => Stream.value(user);
}

class ImportDatabase extends MemoryFirestore {
  void Function()? beforeTransaction;
  bool loseAcknowledgement = false;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      ImportCollection(this, path);
  @override
  Future<T> runTransaction<T>(TransactionHandler<T> handler,
      {Duration timeout = const Duration(seconds: 30),
      int maxAttempts = 5}) async {
    beforeTransaction?.call();
    final tx = ImportTransaction(this);
    final result = await handler(tx);
    documents.addAll(tx.pending);
    if (loseAcknowledgement) {
      loseAcknowledgement = false;
      throw StateError('Connection lost after commit');
    }
    return result;
  }
}

class ImportCollection extends MemoryCollection {
  ImportCollection(super.store, super.path, {this.field, this.equal});
  final Object? field, equal;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      ImportDocument(store, '$path/$id');
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      return ImportCollection(store, path,
          field: invocation.positionalArguments.first,
          equal: invocation.namedArguments[#isEqualTo]);
    }
    return super.noSuchMethod(invocation);
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    expect(options?.source, Source.server);
    final result = await super.get(options);
    return MemoryQuery(result.docs
        .where((doc) => field == null || doc.data()[field] == equal)
        .toList());
  }
}

class ImportDocument extends MemoryDocument {
  ImportDocument(super.store, super.path);
  @override
  CollectionReference<Map<String, dynamic>> collection(String name) =>
      ImportCollection(store, '$path/$name');
}

class ImportTransaction extends Fake implements Transaction {
  ImportTransaction(this.db);
  final ImportDatabase db;
  final pending = <String, Map<String, dynamic>>{};
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
      DocumentReference<T> reference) async {
    expect(pending, isEmpty,
        reason: 'All reads must precede transaction writes');
    return MemorySnapshot(db.documents[reference.path]) as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(DocumentReference<T> reference, T data,
      [SetOptions? options]) {
    pending[reference.path] = Map<String, dynamic>.from(data as Map);
    return this;
  }

  @override
  Transaction update(DocumentReference reference, Map<Object, Object?> data) {
    pending[reference.path] = {
      ...db.documents[reference.path]!,
      ...Map<String, dynamic>.from(data)
    };
    return this;
  }
}

void main() {
  incoming(String id) => receivedProject(
          request: '226144',
          client: 'Cliente',
          type: 'Professional',
          leader: 'Líder',
          receivedAt: DateTime(2026, 10, 22),
          hourType: 'Hs Cobradas',
          steps: [
            {'id': id, 'name': 'Etapa $id', 'hours': '08:00'}
          ]);
  test(
      'a lost acknowledgement followed by retry creates one project and one task',
      () async {
    final db = ImportDatabase()..loseAcknowledgement = true;
    final auth = ImportAuth();
    final store = ReceivedWorkStore(database: db, auth: auth);
    await expectLater(
        store.import(incoming('3'), expectedExisting: false), throwsStateError);
    expect(await store.import(incoming('3'), expectedExisting: false), 0);
    final project = db.documents['users/owner/projects/226144']!;
    expect((project['subTasks'] as List), hasLength(1));
    expect(db.documents.keys.where((key) => key.contains('/edesk_received/')),
        hasLength(1));
  });
  test('appending preserves client, leader, folder and existing task settings',
      () async {
    final db = ImportDatabase();
    final store = ReceivedWorkStore(database: db, auth: ImportAuth());
    await store.import(incoming('3'));
    final saved = db.documents['users/owner/projects/226144']!;
    saved.addAll({
      'client': 'Editado',
      'leader': 'Outro líder',
      'folderPath': 'C:/Clientes/Projeto',
      'workedHours': '04:00'
    });
    expect(await store.import(incoming('6')), 1);
    final after = db.documents['users/owner/projects/226144']!;
    expect(after['client'], 'Editado');
    expect(after['leader'], 'Outro líder');
    expect(after['workedHours'], '04:00');
    expect(after['folderPath'], 'C:/Clientes/Projeto');
    expect(after['estimatedHours'], '16:00');
    expect(after['subTasks'], hasLength(2));
  });
  test(
      'completion between preflight and transaction blocks creation and markers',
      () async {
    final db = ImportDatabase();
    final store = ReceivedWorkStore(database: db, auth: ImportAuth());
    db.beforeTransaction = () => db
        .documents['users/owner/completed_projects/226144'] = {'id': '226144'};
    await expectLater(
        store.import(incoming('3'), expectedExisting: false), throwsStateError);
    expect(
        db.documents.keys.where((key) =>
            key.contains('/projects/') || key.contains('/edesk_received/')),
        isEmpty);
  });
  test('changing account during the transaction prevents every write',
      () async {
    final db = ImportDatabase();
    final auth = ImportAuth();
    final store = ReceivedWorkStore(database: db, auth: auth);
    db.beforeTransaction = () => auth.user = null;
    await expectLater(
        store.import(incoming('3'), expectedExisting: false), throwsStateError);
    expect(db.documents, isEmpty);
  });
  test('deleting or creating the project during review requires a fresh review',
      () async {
    final db = ImportDatabase();
    final store = ReceivedWorkStore(database: db, auth: ImportAuth());
    db.documents['users/owner/projects/226144'] = incoming('3').toJson();
    db.beforeTransaction =
        () => db.documents.remove('users/owner/projects/226144');
    await expectLater(
        store.import(incoming('6'), expectedExisting: true), throwsStateError);
    expect(db.documents, isEmpty);
    db.beforeTransaction = () =>
        db.documents['users/owner/projects/226144'] = incoming('3').toJson();
    await expectLater(
        store.import(incoming('6'), expectedExisting: false), throwsStateError);
    expect(
        db.documents['users/owner/projects/226144']!['subTasks'], hasLength(1));
  });
}
