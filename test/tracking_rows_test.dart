import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/solicitacoes/tracking_rows.dart';

void main() {
  test('Projeto finalizado sai do acompanhamento, com status normalizado', () {
    for (final status in ['TRAB_FIM', ' trab_fim ', 'trab_fim']) {
      expect(isActiveTrackingProject({'status': status}), false);
    }
    expect(isActiveTrackingProject({'status': 'TRAB'}), true);
    // Finishing one step must not remove an otherwise active project.
    expect(isActiveTrackingProject({'status': 'TRAB', 'subTasks': [{'status': 'TRAB_FIM'}]}), true);
  });
  test('Snapshot remove imediatamente só o acompanhamento do documento finalizado', () {
    final rows = <Map<String, dynamic>>[
      {'docId': 'finished', 'id': '100', 'cliente': 'Plugin finalizado'},
      {'docId': 'active', 'id': '200', 'cliente': 'Plugin ativo'},
    ];
    final retained = retainActiveTrackingRows(rows, {'active'});
    expect(retained, [rows[1]]);
    expect(rows, hasLength(2)); // No project/history is destroyed.
    expect(retainActiveTrackingRows(retained, {}), isEmpty);
  });
}
