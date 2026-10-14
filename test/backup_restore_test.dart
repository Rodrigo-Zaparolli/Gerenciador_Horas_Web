import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gerenciador_horas/data/services/backup_service.dart';
import 'package:gerenciador_horas/data/services/edesk_integration.dart';

class MemoryFirestore extends Fake implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  int commits = 0;
  int? failCommit;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      MemoryCollection(this, path);
  @override
  DocumentReference<Map<String, dynamic>> doc(String path) =>
      MemoryDocument(this, path);
  @override
  WriteBatch batch() => MemoryBatch(this);
}

class MemoryDocument extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  final MemoryFirestore store;
  @override
  final String path;
  MemoryDocument(this.store, this.path);
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String name) =>
      MemoryCollection(store, '$path/$name');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
          [GetOptions? options]) async =>
      MemorySnapshot(store.documents[path]);
}

class MemorySnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  final Map<String, dynamic>? value;
  MemorySnapshot(this.value);
  @override
  bool get exists => value != null;
  @override
  Map<String, dynamic>? data() => value;
}

class MemoryCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  final MemoryFirestore store;
  final String path;
  MemoryCollection(this.store, this.path);
  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      MemoryDocument(store, '$path/$id');
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get(
          [GetOptions? options]) async =>
      MemoryQuery([
        for (final entry in store.documents.entries)
          if (entry.key.startsWith('$path/') &&
              entry.key.split('/').length == path.split('/').length + 1)
            MemoryQueryDocument(store, entry.key, entry.value),
      ]);
}

class MemoryQuery extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  MemoryQuery(this.docs);
}

class MemoryQueryDocument extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  final MemoryFirestore store;
  final String path;
  final Map<String, dynamic> value;
  MemoryQueryDocument(this.store, this.path, this.value);
  @override
  String get id => path.split('/').last;
  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      MemoryDocument(store, path);
  @override
  Map<String, dynamic> data() => value;
}

class MemoryBatch extends Fake implements WriteBatch {
  final MemoryFirestore store;
  final pending = <String, Map<String, dynamic>>{};
  MemoryBatch(this.store);
  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    expect(options?.merge, true);
    pending[document.path] = Map<String, dynamic>.from(data as Map);
  }

  @override
  Future<void> commit() async {
    store.commits++;
    if (store.commits == store.failCommit)
      throw StateError('Simulated network failure');
    for (final entry in pending.entries) {
      store.documents[entry.key] = {
        ...?store.documents[entry.key],
        ...entry.value
      };
    }
  }
}

void main() {
  final originalClient = EdeskIntegrationApi.clientFactory;
  final originalToken = EdeskIntegrationApi.tokenProvider;
  setUp(() {
    EdeskIntegrationApi.tokenProvider = () async => 'test';
    EdeskIntegrationApi.clientFactory =
        () => MockClient((request) async => http.Response(
            jsonEncode(request.url.path == '/healthz'
                ? {'busy': false}
                : {
                    'items': {'a' * 64: 'confirmed'}
                  }),
            200));
  });
  tearDown(() {
    EdeskIntegrationApi.clientFactory = originalClient;
    EdeskIntegrationApi.tokenProvider = originalToken;
  });

  test(
      'export and restore keep IDs, nested logs, comments and other existing records',
      () async {
    final source = MemoryFirestore();
    source.documents.addAll({
      'users/owner': {'name': 'Rodrigo', 'senha': 'private'},
      'users/owner/projects/p1': {
        'name': 'Projeto',
        'createdAt': Timestamp(1234, 567)
      },
      'users/owner/projects/p1/time_logs/t1': {'hours': 2.5},
      'users/owner/projects/p1/comentarios_edesk/c1': {'texto': 'Revisão'},
      'users/owner/work_formats/f1': {'name': 'Consultoria'},
    });
    final text =
        await BackupService(firestore: source, userIdProvider: () => 'owner')
            .export();
    expect(text, isNot(contains('private')));
    final target = MemoryFirestore();
    target.documents['users/owner/projects/existing'] = {'name': 'Preservar'};
    final plan = validateBackup(text, 'owner', db: target);
    final service =
        BackupService(firestore: target, userIdProvider: () => 'owner');
    await service.restore(plan);
    await service.restore(plan);
    expect(target.documents.length, 6);
    expect(target.documents['users/owner/projects/p1/time_logs/t1'],
        {'hours': 2.5});
    expect(target.documents['users/owner/projects/p1/comentarios_edesk/c1'],
        {'texto': 'Revisão'});
    expect(target.documents['users/owner/projects/existing'],
        {'name': 'Preservar'});
    expect(target.documents['users/owner/projects/p1']!['createdAt'],
        Timestamp(1234, 567));
  });

  test('restore refuses a changed account before writing anything', () async {
    final store = MemoryFirestore();
    final plan = BackupPlan(
        'owner',
        [
          const BackupDocument('projects/p1', {'name': 'P'})
        ],
        null,
        '2026-10-08');
    await expectLater(
        BackupService(firestore: store, userIdProvider: () => 'other')
            .restore(plan),
        throwsStateError);
    expect(store.documents, isEmpty);
    expect(store.commits, 0);
  });

  test(
      'partial restore reports progress and retry updates the same records without duplicates',
      () async {
    final store = MemoryFirestore()..failCommit = 2;
    final plan = BackupPlan(
        'owner',
        [
          for (var i = 0; i < 205; i++)
            BackupDocument('projects/p$i', {'name': '$i'})
        ],
        null,
        '2026-10-08');
    final service =
        BackupService(firestore: store, userIdProvider: () => 'owner');
    await expectLater(
        service.restore(plan),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('100 registros'))));
    expect(store.documents.length, 100);
    store.failCommit = null;
    await service.restore(plan);
    expect(store.documents.length, 205);
  });
}
