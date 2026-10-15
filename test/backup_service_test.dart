import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/backup_service.dart';
import 'package:gerenciador_horas/data/services/edesk_integration.dart';

void main() {
  String backup(List<Map<String, dynamic>> documents,
          {String uid = 'owner', Object? history}) =>
      jsonEncode({
        'format': 'gerenciador_horas_backup',
        'version': 1,
        'uid': uid,
        'exportedAt': '2026-10-08',
        'documents': documents,
        'edeskHistory': history
      });

  test('backup preserves Firestore dates, unicode, lists, geopoints and bytes',
      () {
    final source = {
      'createdAt': Timestamp(123456789, 987654321),
      'location': const GeoPoint(-23.5, -46.6),
      'data': Blob(Uint8List.fromList([0, 128, 255])),
      'steps': [
        {'name': 'Revisão', 'hours': 2.5}
      ],
      'empty': null
    };
    final restored = decodeBackupValue(
        jsonDecode(jsonEncode(encodeBackupValue(source))),
        uid: 'owner') as Map;
    expect(restored['createdAt'], source['createdAt']);
    expect(restored['location'], source['location']);
    expect((restored['data'] as Blob).bytes, (source['data'] as Blob).bytes);
    expect(restored['steps'], source['steps']);
    expect(restored['empty'], isNull);
  });

  test('backup filters secrets recursively', () {
    expect(
        encodeBackupValue({
          'name': 'Cliente',
          'senha': 'private',
          'nested': {'token': 'private', 'value': 'ok'}
        }),
        {
          'name': 'Cliente',
          'nested': {'value': 'ok'}
        });
  });

  test('cloud E-Desk credentials are excluded from export and restore', () {
    expect(backupIncludesDocument('configuracoes/edesk_credenciais'), false);
    expect(backupIncludesDocument('configuracoes/edesk_integracao'), true);
    final plan = validateBackup(backup([
      {'path': 'configuracoes/edesk_credenciais', 'data': {'email': 'fixture@example.test', 'senha': 'fixture'}},
      {'path': 'configuracoes/edesk_integracao', 'data': {'mode': 'local'}},
    ]), 'owner');
    expect(plan.documents.map((doc) => doc.path), ['configuracoes/edesk_integracao']);
  });

  test('backup validates all paths and owner before any restore', () {
    final documents = [
      {
        'path': 'projects/project1',
        'data': {'name': 'Projeto'}
      },
      {
        'path': 'projects/project1/time_logs/log1',
        'data': {'hours': 2}
      },
      {
        'path': 'projects/project1/comentarios_edesk/comment1',
        'data': {'texto': 'Olá'}
      }
    ];
    final plan = validateBackup(backup(documents), 'owner');
    expect(plan.uid, 'owner');
    expect(plan.documents.map((e) => e.path), documents.map((e) => e['path']));
    expect(() => validateBackup(backup(documents, uid: 'other'), 'owner'),
        throwsFormatException);
    for (final path in [
      'users/other',
      'projects/../time_logs/log',
      'projects/a/unknown/b',
      'unknown/id',
      'projects//time_logs/x'
    ]) {
      expect(
          () => validateBackup(
              backup([
                {'path': path, 'data': {}}
              ]),
              'owner'),
          throwsFormatException);
    }
    expect(
        () =>
            validateBackup(backup([documents.first, documents.first]), 'owner'),
        throwsFormatException);
  });

  test('backup validates send history and keeps interrupted sends uncertain',
      () {
    final key = 'a' * 64;
    expect(
        validateBackup(backup([], history: {key: 'pending'}), 'owner')
            .edeskHistory,
        {key: 'uncertain'});
    expect(
        () => validateBackup(
            backup([], history: {'invalid': 'confirmed'}), 'owner'),
        throwsFormatException);
    expect(() => validateBackup(backup([], history: {key: 'invalid'}), 'owner'),
        throwsFormatException);
  });

  test('review shows only selected phases and hours without credentials', () {
    final lines = edeskReviewLines({
      'id': '123',
      'cliente': 'Cliente',
      'fases': [
        {
          'nome': 'Consultoria',
          'dataInicial': '08/10/2026',
          'dataFinal': '09/10/2026'
        }
      ],
      'edeskCredenciais': {'email': 'private', 'senha': 'private'}
    }, 'edesk_fases.py');
    expect(lines.length, 2);
    expect(lines.last, contains('Consultoria'));
    expect(lines.join(), isNot(contains('private')));
    expect(
        edeskReviewLines({
          'trabalhos': [
            {
              'solicitacao': '123',
              'idTrabalho': '2',
              'horas': [
                {
                  'data': '08/10/2026',
                  'inicio': '08:00',
                  'fim': '09:00',
                  'descricao': 'Revisão'
                }
              ]
            }
          ]
        }, 'edesk_horas.py')
            .single,
        contains('Revisão'));
    expect(progressLabel('login'), contains('Aguardando login'));
  });
}
