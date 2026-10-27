import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// Four-column tab stops. Non-breaking spaces also retain spacing in E-Desk HTML.
KeyEventResult? handleCommentTab(
    quill.QuillController controller, KeyEvent event) {
  if (event.logicalKey != LogicalKeyboardKey.tab ||
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isAltPressed ||
      controller.readOnly) {
    return null;
  }
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.handled;
  }
  final selection = controller.selection;
  final text = controller.document.toPlainText();
  if (!selection.isValid || selection.end >= text.length) {
    return KeyEventResult.handled;
  }
  final start = selection.start;
  final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
  final column = start - lineStart;
  if (HardwareKeyboard.instance.isShiftPressed) {
    if (!selection.isCollapsed) return KeyEventResult.handled;
    final limit = column % 4 == 0 ? 4 : column % 4;
    var count = 0;
    while (count < limit &&
        start - count > lineStart &&
        (text[start - count - 1] == ' ' ||
            text[start - count - 1] == '\u00a0')) {
      count++;
    }
    if (count > 0) {
      controller.replaceText(start - count, count, '',
          TextSelection.collapsed(offset: start - count));
    }
  } else {
    final spaces = '\u00a0' * (4 - column % 4);
    controller.replaceText(start, selection.end - start, spaces,
        TextSelection.collapsed(offset: start + spaces.length));
  }
  return KeyEventResult.handled;
}
