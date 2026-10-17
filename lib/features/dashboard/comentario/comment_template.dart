import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Prefer the Excel table when present; otherwise use the current selection.
/// Existing text, formatting and pasted images are retained.
bool insertCommentTemplate(QuillController editor, String content,
    {String? excelImage}) {
  final text = content.trim();
  if (text.isEmpty) {
    throw const FormatException('O modelo ainda não tem conteúdo.');
  }
  final document = editor.document.toPlainText();
  final end = editor.document.length - 1;
  var position = editor.selection.isValid
      ? editor.selection.extentOffset.clamp(0, end)
      : end;
  if (excelImage != null) {
    var offset = 0;
    for (final operation in editor.document.toDelta().toJson()) {
      final value = operation['insert'];
      if (value is String) {
        offset += value.length;
      } else {
        if (value is Map && value['image'] is String) {
          final source = value['image'] as String;
          final raw = source.startsWith('data:') && source.contains(',')
              ? source.substring(source.indexOf(',') + 1)
              : source;
          if (raw == excelImage) position = (offset + 1).clamp(0, end);
        }
        offset++;
      }
    }
  }
  if (position < end && document[position] == '\n') position++;
  if (document.startsWith(text, position)) return false;
  final prefix = position > 0 && document[position - 1] != '\n' ? '\n' : '';
  final insertion = '$prefix$text\n\n';
  editor.replaceText(position, 0, insertion,
      TextSelection.collapsed(offset: position + insertion.length));
  return true;
}
