import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/checklist_stage_progress.dart';

void main() {
  test('parent percentage follows all children using known weights', () {
    final tasks = [
      {'sheet': 'S', 'cell': 'E1'},
      {'sheet': 'S', 'cell': 'E2'}
    ];
    final values = {'S!E1': 1.0, 'S!E2': 0.0};
    expect(
        checklistBlockProgress(tasks, values, {
          'taskProgress': {
            'S!E1': {'weight': .1},
            'S!E2': {'weight': .3}
          }
        }),
        .25);
    expect(
        checklistBlockProgress(tasks, values, {
          'taskProgress': {
            'S!E1': {'weight': 0},
            'S!E2': {'weight': 0}
          }
        }),
        .5);
    expect(checklistBlockProgress(tasks, values, null), .5);
    expect(checklistBlockProgress(tasks, {'S!E1': 1, 'S!E2': 1}, null), 1);
  });

  const tasks = [
    {'sheet': 'S', 'cell': 'E1'},
    {'sheet': 'S', 'cell': 'E2'}
  ];
  const preview = {
    'rows': [
      {'label': 'Implantacao', 'percentage': .375}
    ],
    'taskProgress': {
      'S!E1': {'weight': .25, 'value': 0},
      'S!E2': {'weight': .75, 'value': .5}
    }
  };
  test('instant preview follows Excel weights, not an equal average', () {
    expect(
        immediateStageProgress(
            'Implantacao', tasks, {'S!E1': 1, 'S!E2': .5}, preview),
        .625);
    expect(
        immediateStageProgress(
            'Implantacao', tasks, {'S!E1': 1, 'S!E2': 1}, preview),
        1);
  });
  test(
      'unknown weights, other stages or inconsistent totals cannot invent a percentage',
      () {
    expect(
        immediateStageProgress('Outro', tasks, {'S!E1': 1, 'S!E2': 1}, preview),
        isNull);
    expect(
        immediateStageProgress('Implantacao', tasks, {'S!E1': 1, 'S!E2': 1},
            {'rows': preview['rows']}),
        isNull);
    expect(
        immediateStageProgress('Implantacao', tasks, {
          'S!E1': 1,
          'S!E2': 1
        }, {
          ...preview,
          'rows': [
            {'label': 'Implantacao', 'percentage': .99}
          ]
        }),
        isNull);
  });
}
