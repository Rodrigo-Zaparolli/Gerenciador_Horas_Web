import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Keep Quill's mandatory terminal newline anchored while applying native edits.
/// A generic diff may otherwise append after that newline, outside its tree.
void applyNativeCommentDocument(QuillController controller,
    List<dynamic> incoming, TextSelection selection) {
  final before = controller.document.toDelta();
  final oldLength = controller.document.length;
  final incomingDocument = Document.fromJson(incoming);
  final after = incomingDocument.toDelta();
  final newLength = incomingDocument.length;
  final delta =
      before.slice(0, oldLength - 1).diff(after.slice(0, newLength - 1));
  final oldEnd = Map<String, dynamic>.from(
      before.toJson().last['attributes'] as Map? ?? {});
  final newEnd = Map<String, dynamic>.from(
      after.toJson().last['attributes'] as Map? ?? {});
  final attributes = <String, dynamic>{
    for (final key in {...oldEnd.keys, ...newEnd.keys})
      if (oldEnd[key] != newEnd[key]) key: newEnd[key],
  };
  if (attributes.isNotEmpty) {
    final consumed = delta.toJson().fold<int>(
        0,
        (total, op) =>
            total + ((op['retain'] ?? op['delete'] ?? 0) as num).toInt());
    delta.retain(oldLength - 1 - consumed);
    delta.retain(1, attributes);
  }
  if (delta.isNotEmpty) {
    controller.compose(delta, controller.selection, ChangeSource.local);
  }
  controller.updateSelection(
      TextSelection(
          baseOffset:
              selection.baseOffset.clamp(0, controller.document.length - 1),
          extentOffset:
              selection.extentOffset.clamp(0, controller.document.length - 1)),
      ChangeSource.local);
}
