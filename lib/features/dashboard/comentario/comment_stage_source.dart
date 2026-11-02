import '../../projects/dialogs/project_spreadsheet_kind.dart';
import 'comment_stage.dart';

typedef CommentStageRead = Future<Map<String, dynamic>> Function(
    {String? worksheet, int? firstRow, int? firstColumn});

Future<List<CommentStage>> readCommentStages({
  required String serviceType,
  required Map<String, String> sheets,
  required CommentStageRead read,
}) async {
  final type = serviceType.toLowerCase();
  if (type.contains('catalog') && type.contains('treinamento')) {
    final schedule =
        await read(worksheet: 'Cronogramas', firstRow: 5, firstColumn: 2);
    if (schedule['scheduleTable'] != true ||
        schedule['worksheet'] != 'Cronogramas' ||
        schedule['revision'] is! String ||
        schedule['fields'] is! List) {
      throw StateError('Não foi identificado o cronograma deste treinamento.');
    }
    final cells = (schedule['fields'] as List).whereType<Map>();
    final rowNumbers = cells
        .map((f) => int.tryParse(
            (f['cell']?.toString() ?? '').replaceAll(RegExp('[A-Z]'), '')))
        .whereType<int>()
        .toList();
    if (rowNumbers.isEmpty) {
      throw StateError('O cronograma não retornou linhas.');
    }
    final last = rowNumbers.reduce((a, b) => a > b ? a : b);
    final summary = await read(
        worksheet: 'Cronogramas', firstRow: last + 1, firstColumn: 2);
    if (summary['revision'] != schedule['revision'] ||
        summary['worksheet'] != 'Cronogramas') {
      throw StateError(
          'A planilha mudou durante a leitura. Carregue novamente.');
    }
    return commentStagesFromScheduleSummary(summary);
  }
  final data = await read();
  if (!spreadsheetMatchesProject(data, serviceType,
      checklistSheet: sheets['checklist'], entrySheet: sheets['entry'])) {
    throw StateError(
        'A leitura não corresponde às guias configuradas para este projeto.');
  }
  return CommentStage.fromStatus(data);
}

/// Read calculated summary cells, never average the individual appointments.
List<CommentStage> commentStagesFromScheduleSummary(Map<String, dynamic> data) {
  final fields = data['fields'];
  if (fields is! List) {
    throw StateError('O resumo do cronograma não foi retornado.');
  }
  final rows = <int, Map<String, dynamic>>{};
  for (final field in fields.whereType<Map>()) {
    final cell =
        RegExp(r'^([B-I])(\d+)$').firstMatch(field['cell']?.toString() ?? '');
    if (cell != null) {
      rows.putIfAbsent(int.parse(cell[2]!), () => {})[cell[1]!] =
          field['value'];
    }
  }
  String normalize(dynamic v) => (v?.toString() ?? '')
      .toLowerCase()
      .replaceAll('ç', 'c')
      .replaceAll('ã', 'a')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[^a-z0-9]'), '');
  final headers = rows.entries
      .where((r) =>
          normalize(r.value['G']) == 'fim' &&
          normalize(r.value['H']) == 'realizado' &&
          normalize(r.value['I']) == 'trabalhodescricao')
      .toList();
  if (headers.length != 1) {
    throw StateError(
        'Não foi encontrado o resumo com Fim, Realizado % e Trabalho / Descrição no cronograma.');
  }
  final stages = <Map<String, dynamic>>[];
  final after = rows.keys.where((n) => n > headers.single.key).toList()..sort();
  for (final n in after) {
    final row = rows[n]!;
    final label = row['I']?.toString().trim() ?? '';
    if (label.isEmpty) continue;
    stages.add({'label': label, 'end': row['G'], 'percentage': row['H']});
  }
  return CommentStage.fromStatus({
    'statusPreview': {'rows': stages}
  });
}
