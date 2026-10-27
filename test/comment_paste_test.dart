import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/comment_paste.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_paste_action.dart';
import 'support/comment_clipboard_test_stub.dart'
    if (dart.library.js_interop) 'support/comment_clipboard_test_web.dart';

class TestCommentPasteIntent extends Intent {
  const TestCommentPasteIntent();
}

void main() {
  test('browser shortcut permits the native paste event', () {
    final action = BrowserCommentPasteAction();
    expect(action.consumesKey(const TestCommentPasteIntent()), isFalse);
    expect(action.invoke(const TestCommentPasteIntent()), isNull);
  });
  test('browser paste delivers text once without clipboard API access', () {
    final received = <String>[];
    final stop = listenForCommentPaste(
        accepts: () => true,
        onText: received.add,
        onImage: (_) => fail('Text paste must not add an image'));
    expect(pasteCommentText('Current text\nSecond line'), isTrue);
    expect(received, ['Current text\nSecond line']);
    stop();
    expect(pasteCommentText('After disposal'), isFalse);
    expect(received, hasLength(1));
  }, skip: !kIsWeb);
  test('unfocused editor does not capture paste', () {
    final received = <String>[];
    final stop = listenForCommentPaste(
        accepts: () => false, onText: received.add, onImage: (_) {});
    expect(pasteCommentText('Other field'), isFalse);
    expect(received, isEmpty);
    stop();
  }, skip: !kIsWeb);
  testWidgets(
      'Ctrl+V reaches browser paste while the real comment editor is focused',
      (tester) async {
    final controller = quill.QuillController.basic();
    final focus = FocusNode();
    final scroll = ScrollController();
    final stop = listenForCommentPaste(
        accepts: () => focus.hasFocus,
        onText: (text) {
          final selection = controller.selection;
          controller.replaceText(
              selection.start,
              selection.end - selection.start,
              text,
              TextSelection.collapsed(offset: selection.start + text.length));
        },
        onImage: (_) {});
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          quill.FlutterQuillLocalizations.delegate
        ],
        home: Scaffold(
            body: Shortcuts(
                shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyV, control: true):
                  TestCommentPasteIntent(),
            },
                child: Actions(
                    actions: {
                      TestCommentPasteIntent: BrowserCommentPasteAction()
                    },
                    child: quill.QuillEditor.basic(
                        controller: controller,
                        focusNode: focus,
                        scrollController: scroll,
                        config: quill.QuillEditorConfig(
                            customShortcuts: browserCommentPasteShortcuts,
                            customActions: browserCommentPasteActions())))))));
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final consumed = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    expect(consumed, isFalse);
    expect(pasteCommentText('Pasted current text'), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(controller.document.toPlainText(), 'Pasted current text\n');
    expect(tester.takeException(), isNull);
    stop();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    focus.dispose();
    scroll.dispose();
  }, skip: !kIsWeb);
}
