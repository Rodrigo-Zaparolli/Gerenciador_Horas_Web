import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/edesk/phase_date_sync.dart';

void main() {
  Map<String, dynamic> task() => {
        'subId': '5',
        'stage': 'Implantacao',
        'planStart': '2026-07-31T00:00:00.000',
        'planEnd': '2026-11-30T00:00:00.000',
        'status': 'TRAB_EXE',
        'estimatedHours': '30:30',
        'custom': 'preservado'
      };
  List<Map<String, dynamic>> patch(List<dynamic> tasks) => phaseDatePatch(tasks,
      request: '2260860',
      work: '5',
      phase: 'Implantacao',
      expectedStart: '31/07/2026',
      expectedEnd: '30/11/2026',
      start: DateTime(2026, 7, 31),
      end: DateTime(2026, 12, 15));
  test('reject invalid dates and reversed ranges', () {
    expect(parsePhaseDate('31/02/2026'), isNull);
    expect(parsePhaseDate('00/01/2026'), isNull);
    expect(parsePhaseDate('29/02/2024'), DateTime(2024, 2, 29));
    expect(
        () =>
            validatePhaseDates(DateTime(2026, 12, 15), DateTime(2026, 11, 30)),
        throwsFormatException);
  });
  test('changes only selected task dates without mutating source', () {
    final source = task();
    final other = {...task(), 'subId': '6'};
    final result = patch([source, other]);
    expect(result.first['planEnd'], '2026-12-15T00:00:00.000');
    expect(source['planEnd'], '2026-11-30T00:00:00.000');
    expect(
        {...result.first}
          ..remove('planStart')
          ..remove('planEnd'),
        {...source}
          ..remove('planStart')
          ..remove('planEnd'));
    expect(result.last, other);
  });
  test('blocks absent, duplicate or mismatched work references', () {
    expect(() => patch([]), throwsStateError);
    expect(() => patch([task(), task()]), throwsStateError);
    expect(
        () => patch([
              {...task(), 'edeskSolicitacao': '999'}
            ]),
        throwsStateError);
  });
  test('blocks stale dates and phase names', () {
    expect(
        () => patch([
              {...task(), 'planEnd': '2026-12-01T00:00:00.000'}
            ]),
        throwsStateError);
    expect(
        () => patch([
              {...task(), 'stage': 'Outro'}
            ]),
        throwsStateError);
  });
}
