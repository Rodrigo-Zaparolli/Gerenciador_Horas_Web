import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

class CommentStage {
  const CommentStage(this.name, this.end, this.percentage);
  final String name;
  final DateTime end;
  final double percentage;
  String get date => '${end.day.toString().padLeft(2, '0')}/'
      '${end.month.toString().padLeft(2, '0')}/${end.year}';
  String get percent {
    final value = (percentage * 100).toStringAsFixed(1);
    return '${value.replaceFirst(RegExp(r'\.0$'), '').replaceAll('.', ',')}%';
  }

  static List<CommentStage> fromStatus(Map<String, dynamic> response) {
    final status = response['statusPreview'];
    if (status is! Map || status['rows'] is! List) {
      throw const FormatException(
          'A leitura não retornou a tabela Status Projeto.');
    }
    final result = <CommentStage>[];
    final names = <String>{};
    for (final row in (status['rows'] as List).whereType<Map>()) {
      final name = row['label']?.toString().trim() ?? '';
      final end = DateTime.tryParse(row['end']?.toString() ?? '');
      final pct = row['percentage'];
      if (name.isEmpty ||
          end == null ||
          pct is! num ||
          !pct.isFinite ||
          pct < 0 ||
          pct > 1) {
        throw const FormatException(
            'Há etapas sem nome, data Fim ou Realizado válido na tabela Status Projeto. Confira a planilha.');
      }
      if (!names.add(name.toLowerCase())) {
        throw const FormatException(
            'Há etapas com nomes repetidos na tabela Status Projeto.');
      }
      result.add(CommentStage(name, end, pct.toDouble()));
    }
    if (result.isEmpty) {
      throw const FormatException(
          'Nenhuma etapa encontrada na tabela Status Projeto.');
    }
    return result;
  }
}

/// Updates value ranges only; leaves surrounding Delta attributes and embeds intact.
void applyCommentStage(QuillController editor, CommentStage stage) {
  final text = editor.document.toPlainText();
  final replacements = <({int start, int length, String value})>[];
  final missing = <String>[];
  final fields = [
    (
      r'Etapa[ \t\u00a0]+atual[ \t\u00a0]+do[ \t\u00a0]+projeto[ \t\u00a0]*:',
      '{{etapa}}',
      'Etapa atual do projeto: ',
      stage.name
    ),
    (
      r'Finaliza[çc][ãa]o[ \t\u00a0]+at[ée][ \t\u00a0]+o[ \t\u00a0]+dia[ \t\u00a0]*[-–—:]',
      '{{fim_etapa}}',
      '     Finalização até o dia - ',
      stage.date
    ),
    (
      r'Percentual[ \t\u00a0]*:',
      '{{percentual_etapa}}',
      '     Percentual: ',
      stage.percent
    ),
  ];
  for (final field in fields) {
    final pattern = RegExp(
        '^([ \\t\\u00a0]*(?:${field.$1})[ \\t\\u00a0]*)([^\\r\\n\\uFFFC]*)',
        multiLine: true,
        caseSensitive: false);
    final matches = pattern.allMatches(text).toList();
    if (matches.isNotEmpty) {
      for (final match in matches) {
        final start = match.start + match.group(1)!.length;
        replacements.add(
            (start: start, length: match.group(2)!.length, value: field.$4));
      }
    } else {
      final tokens = RegExp(RegExp.escape(field.$2)).allMatches(text).toList();
      if (tokens.isEmpty) {
        missing.add('${field.$3}${field.$4}\n');
      } else {
        for (final token in tokens) {
          replacements.add((
            start: token.start,
            length: token.end - token.start,
            value: field.$4
          ));
        }
      }
    }
  }
  replacements.sort((a, b) => b.start.compareTo(a.start));
  for (final edit in replacements) {
    editor.replaceText(edit.start, edit.length, edit.value, null);
  }
  if (missing.isNotEmpty) editor.replaceText(0, 0, missing.join(), null);
  editor.updateSelection(
      TextSelection.collapsed(
          offset: editor.selection.extentOffset
              .clamp(0, editor.document.length - 1)),
      ChangeSource.local);
}
