import 'package:diff_match_patch/diff_match_patch.dart';
import '../../../core/platform/comment_paste_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Patch only changed text. Keep retained spans, attributes and image embeds.
void applyCommentWritingReview(QuillController controller, String revised) {
  final original = controller.document.toPlainText();
  // Quill requires the final document newline.
  final normalized = normalizeCommentPastedText(revised);
  // Exclude Quill's mandatory terminal newline from the diff, so appending
  // a new paragraph never tries inserting after the end of the document.
  final body = original.endsWith('\n') ? original.substring(0, original.length - 1) : original;
  final target = normalized.endsWith('\n') ? normalized.substring(0, normalized.length - 1) : normalized;
  final changes = diff(body, target);
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
