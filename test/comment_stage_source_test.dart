import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_stage.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_stage_source.dart';

void main() {
  test(
      'stage names come from the workbook for every service, without fixed lists',
      () {
    for (final names in [
      ['Contato Inicial', 'Implantação', 'Pós-Implantação'],
      [
        'Contato Inicial',
        'Levantamento de escopo',
        'Desenvolvimento',
        'Implantação',
        'Pós-Implantação'
      ],
      [
        'Contato Inicial',
        'Treinamento Catalog',
        'Treinamento Builder',
        'Treinamento Construtor',
        'Acompanhamento'
      ],
      ['Implantação Plugin'],
      ['Um novo trabalho personalizado'],
    ]) {
      final stages = CommentStage.fromStatus({
        'statusPreview': {
          'rows': [
            for (final name in names)
              {'label': name, 'end': '2026-11-05', 'percentage': .4}
          ]
        }
      });
      expect(stages.map((s) => s.name).toList(), names);
    }
  });

  Map<String, dynamic> summary({String revision = 'r1'}) => {
        'worksheet': 'Cronogramas',
        'revision': revision,
        'fields': [
          {'cell': 'G29', 'value': 'Fim'},
          {'cell': 'H29', 'value': 'Realizado %'},
          {'cell': 'I29', 'value': 'Trabalho / Descrição'},
          for (final entry in [
            (30, 'Contato Inicial', 1.0, '2026-09-30'),
            (31, 'Treinamento Catalog', .75, '2026-10-26'),
            (32, 'Treinamento Builder', .5, '2026-10-28'),
            (33, 'Treinamento Construtor', .25, '2026-10-30'),
            (34, 'Acompanhamento', 0.0, '2026-11-06'),
          ]) ...[
            {'cell': 'G${entry.$1}', 'value': entry.$4},
            {'cell': 'H${entry.$1}', 'value': entry.$3},
            {'cell': 'I${entry.$1}', 'value': entry.$2},
          ]
        ]
      };

  test(
      'Catalog reads calculated summary after appointments and preserves all names',
      () async {
    final calls = <String>[];
    final stages = await readCommentStages(
        serviceType: 'Treinamento Catalog + Builder',
        sheets: {},
        read: ({String? worksheet, int? firstRow, int? firstColumn}) async {
          calls.add('$worksheet:$firstRow:$firstColumn');
          if (firstRow == 5) {
            return {
              'worksheet': 'Cronogramas',
              'revision': 'r1',
              'scheduleTable': true,
              'fields': [
                {'cell': 'B23'},
                {'cell': 'I23'}
              ]
            };
          }
          return summary();
        });
    expect(calls, ['Cronogramas:5:2', 'Cronogramas:24:2']);
    expect(stages.length, 5);
    expect(stages[1].name, 'Treinamento Catalog');
    expect(stages[1].percent, '75%');
    expect(stages[1].date, '26/10/2026');
    expect(stages.last.percent, '0%');
  });
  test('rejects changed workbook between Catalog reads', () async {
    await expectLater(
        readCommentStages(
            serviceType: 'Treinamento Catalog',
            sheets: {},
            read: (
                    {String? worksheet,
                    int? firstRow,
                    int? firstColumn}) async =>
                firstRow == 5
                    ? {
                        'worksheet': 'Cronogramas',
                        'revision': 'r1',
                        'scheduleTable': true,
                        'fields': [
                          {'cell': 'B23'}
                        ]
                      }
                    : summary(revision: 'r2')),
        throwsStateError);
  });
  test(
      'missing summary does not substitute a checklist or an appointment percentage',
      () {
    expect(
        () => commentStagesFromScheduleSummary({
              'fields': [
                {'cell': 'H6', 'value': 1},
                {'cell': 'I6', 'value': 'Contato Inicial'}
              ]
            }),
        throwsStateError);
  });
}
