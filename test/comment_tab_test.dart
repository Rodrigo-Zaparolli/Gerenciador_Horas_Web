import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_tab.dart';

void main() {
  testWidgets(
      'Tab advances to four-column stops and Shift Tab removes only spacing',
      (tester) async {
    final controller = quill.QuillController.basic();
    final focus = FocusNode();
    final scroll = ScrollController();
    controller.replaceText(
        0, 0, 'ab next', const TextSelection.collapsed(offset: 2));
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          quill.FlutterQuillLocalizations.delegate
        ],
        home: Scaffold(
            body: quill.QuillEditor.basic(
                controller: controller,
                focusNode: focus,
                scrollController: scroll,
                config: quill.QuillEditorConfig(
                    // Same Quill 11.6 hook as the comment editor.
                    // ignore: experimental_member_use
                    onKeyPressed: (event, node) =>
                        handleCommentTab(controller, event))))));
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.document.toPlainText(), 'ab\u00a0\u00a0 next\n');
    expect(controller.selection.baseOffset, 4);
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.selection.baseOffset, 8);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.selection.baseOffset, 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.document.toPlainText(), 'ab next\n');
    expect(controller.selection.baseOffset, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.document.toPlainText(), 'ab next\n');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    focus.dispose();
    scroll.dispose();
  });
  test('read-only comments and other keys are unchanged', () {
    final controller = quill.QuillController.basic();
    controller.readOnly = true;
    expect(
        handleCommentTab(
            controller,
            const KeyDownEvent(
                physicalKey: PhysicalKeyboardKey.tab,
                logicalKey: LogicalKeyboardKey.tab,
                timeStamp: Duration.zero)),
        isNull);
    controller.readOnly = false;
    expect(
        handleCommentTab(
            controller,
            const KeyDownEvent(
                physicalKey: PhysicalKeyboardKey.keyA,
                logicalKey: LogicalKeyboardKey.keyA,
                timeStamp: Duration.zero)),
        isNull);
    controller.dispose();
  });
}
