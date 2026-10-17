import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Patch only changed text. Keep retained spans, attributes and image embeds.
void applyCommentWritingReview(QuillController controller, String revised) {
  final original = controller.document.toPlainText();
  // Quill requires the final document newline.
  final target = revised.endsWith('\n') ? revised : '$revised\n';
  final changes = diff(original, target);
  // Embedded objects are never editable in this plain-text review.
  if (changes.any((change) =>
      change.operation != DIFF_EQUAL && change.text.contains('\uFFFC'))) {
    throw const FormatException(
        'Mantenha os marcadores das imagens na revisão.');
  }
  final edits = <({int offset, int length, String text})>[];
  var offset = 0;
  for (var i = 0; i < changes.length; i++) {
    final change = changes[i];
    if (change.operation == DIFF_EQUAL) {
      offset += change.text.length;
      continue;
    }
    final start = offset;
    var removed = 0;
    var inserted = '';
    while (i < changes.length && changes[i].operation != DIFF_EQUAL) {
      if (changes[i].operation == DIFF_DELETE) {
        removed += changes[i].text.length;
        offset += changes[i].text.length;
      } else {
        inserted += changes[i].text;
      }
      i++;
    }
    i--;
    edits.add((offset: start, length: removed, text: inserted));
  }
  for (final edit in edits.reversed) {
    controller.replaceText(edit.offset, edit.length, edit.text,
        TextSelection.collapsed(offset: edit.offset),
        ignoreFocus: true);
  }
}
