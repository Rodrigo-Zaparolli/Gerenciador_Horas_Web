import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/data/services/recoverable_draft.dart';
import 'package:gerenciador_horas/data/services/edesk_operation_history.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/work_duration.dart';
import 'package:gerenciador_horas/domain/models/history_period.dart';
import 'package:gerenciador_horas/shared/widgets/recovery_error.dart';

TimeLog example(
        {String duration = '',
        dynamic hours,
        int minutes = 0,
        String start = '08:00',
        String end = '09:30'}) =>
    TimeLog(
        id: '1',
        targetId: '123_4',
        date: DateTime(2026, 10, 12),
        startTime: start,
        endTime: end,
        durationFormatted: duration,
        durationMinutes: minutes,
        hours: hours,
        isRegistered: true);

void main() {
  setUp(() { LocalUserState.memory = {}; EdeskOperationHistory.clearSession(); });
  tearDown(() => LocalUserState.memory = null);
  test('duration handles decimal hours, totals over 24h and invalid input', () {
    expect(WorkDuration.parse('183:20'), 11000);
    expect(WorkDuration.parse('1,5'), 90);
    for (final bad in ['01:90', '-1', 'NaN', 'Infinity', 'abc']) {
      expect(WorkDuration.parse(bad), isNull);
    }
    expect(WorkDuration.format(-90), '-01:30');
  });
  test('explicit duration avoids counting pauses from the time window', () {
    expect(
        WorkDuration.minutes(example(duration: '01:00', hours: 8, minutes: 45)),
        45);
    expect(WorkDuration.minutes(example(duration: '01:00', hours: 8)), 60);
    expect(WorkDuration.minutes(example(duration: '00:00', hours: 8)), 0);
    expect(WorkDuration.minutes(example(hours: '1,5')), 90);
    expect(WorkDuration.minutes(example()), 90);
    expect(WorkDuration.minutes(example(start: '23:00', end: '01:00')), 0);
    expect(WorkDuration.minutes(example(start: '99:00')), 0);
  });
  test('recovery remains private to account, project and email model', () {
    expect(RecoverableDraft.save('a', 'email.123.initial', {'body': 'Texto'}),
        isTrue);
    expect(RecoverableDraft.read('a', 'email.123.initial')?['body'], 'Texto');
    expect(RecoverableDraft.read('b', 'email.123.initial'), isNull);
    expect(RecoverableDraft.read('a', 'email.456.initial'), isNull);
    expect(RecoverableDraft.read('a', 'email.123.internal'), isNull);
    RecoverableDraft.clear('a', 'email.123.initial');
    expect(RecoverableDraft.read('a', 'email.123.initial'), isNull);
  });
  test('expired recovery is removed and corrupted state is harmless', () {
    LocalUserState.write('a', 'draft.comment.1', {
      'savedAt':
          DateTime.now().subtract(const Duration(days: 31)).toIso8601String(),
      'body': 'Old'
    });
    expect(RecoverableDraft.read('a', 'comment.1'), isNull);
    LocalUserState.memory![LocalUserState.key('a', 'filters')] = 'invalid json';
    expect(LocalUserState.read('a', 'filters'), isNull);
  });
  test('rich recovery retains text formatting and omits image bytes', () {
    final delta = RecoverableDraft.textDelta([
      {
        'insert': 'Olá',
        'attributes': {'bold': true}
      },
      {
        'insert': {'image': 'data:image/png;base64,private'}
      },
      {'insert': '\n'}
    ]);
    expect(delta.length, 2);
    expect(delta.first['attributes'], {'bold': true});
    expect(delta.toString(), isNot(contains('private')));
  });
  test('oversized recovery cannot replace a valid recovery', () {
    LocalUserState.write('a', 'draft', {'text': 'Safe'});
    expect(
        LocalUserState.write('a', 'draft', {'text': 'x' * (2 * 1024 * 1024)}),
        isFalse);
    expect(LocalUserState.read('a', 'draft')?['text'], 'Safe');
  });
  test('operation history records only metadata, not credentials or comments',
      () {
    final id = EdeskOperationHistory.begin('a', '/api/edesk/horas', {
      'operationId': 'job-1',
      'enviar': true,
      'request': {
        'edeskCredenciais': {'senha': 'SECRET'},
        'trabalhos': [
          {
            'solicitacao': '123',
            'horas': [
              {'descricao': 'PRIVATE'}
            ]
          },
          {
            'solicitacao': '456',
            'horas': [{}, {}]
          }
        ]
      }
    });
    final row = EdeskOperationHistory.read('a').single;
    expect(row['project'], '123, 456');
    expect(row['entries'], 3);
    expect(row.toString(), isNot(contains('SECRET')));
    expect(row.toString(), isNot(contains('PRIVATE')));
    EdeskOperationHistory.update('a', id, 'confirmed');
    EdeskOperationHistory.update('a', id, 'uncertain');
    expect(EdeskOperationHistory.read('a').single['state'], 'confirmed');
    expect(EdeskOperationHistory.read('b'), isEmpty);
  });
  test('calendar query includes final day and excludes next day', () {
    final period =
        HistoryPeriod(DateTime(2026, 10, 1, 15), DateTime(2026, 10, 31));
    expect(period.contains(DateTime(2026, 10, 1)), isTrue);
    expect(period.contains(DateTime(2026, 10, 31, 23, 59)), isTrue);
    expect(period.contains(DateTime(2026, 11, 1)), isFalse);
    expect(period.contains(DateTime(2026, 9, 30, 23, 59)), isFalse);
  });
  test('missing or damaged local history cannot lose the final result', () {
    final id = EdeskOperationHistory.begin('a', '/api/edesk/comentarios', {'request': {'solicitacao': '123'}, 'enviar': true});
    LocalUserState.memory![LocalUserState.key('a', EdeskOperationHistory.feature)] = '{"items":7}';
    EdeskOperationHistory.update('a', id, 'confirmed');
    expect(EdeskOperationHistory.read('a').single['state'], 'confirmed');
    final merged = EdeskOperationHistory.combine([
      {'id': 'x', 'state': 'confirmed', 'created': '2026-10-12'}
    ], [
      {'id': 'x', 'state': 'uncertain', 'created': '2026-10-12'}
    ]);
    expect(merged.single['state'], 'confirmed');
  });
  test('returning to same dashboard avoids rebuilding subscriptions', () {
    final unchanged =
        SubscriptionChanges({'a': 'all', 'b': 'all'}, {'a': 'all', 'b': 'all'});
    expect(unchanged.add, isEmpty);
    expect(unchanged.remove, isEmpty);
    final changed = SubscriptionChanges(
        {'a': 'all', 'b': 'all'}, {'a': 'month', 'c': 'all'});
    expect(changed.remove, {'a', 'b'});
    expect(changed.add, {'a', 'c'});
  });
  test('errors guide retry without exposing raw server messages', () {
    expect(recoveryError(TimeoutException('SECRET')), contains('internet'));
    expect(recoveryError(StateError('Entre novamente')), contains('sessão'));
    expect(recoveryError(Exception('PRIVATE')), isNot(contains('PRIVATE')));
  });
}
