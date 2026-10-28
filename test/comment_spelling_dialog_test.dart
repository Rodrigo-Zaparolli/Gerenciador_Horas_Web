import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_spelling_dialog.dart';

void main() {
  for (final allowed in [true, false]) {
    testWidgets(
        'comment corrector preserves formatting and checks current edit permission $allowed',
        (tester) async {
      var canEdit = true;
      final controller = quill.QuillController.basic();
      controller.replaceText(
          0, 0, 'Texto erado', const TextSelection.collapsed(offset: 0));
      controller.formatText(0, 5, quill.Attribute.bold);
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showCommentSpellingDialog(
                          context, controller,
                          canEdit: () => canEdit),
                      child: const Text('Corretor'))))));
      await tester.tap(find.text('Corretor'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextFormField), 'Texto errado\r\nSegunda linha');
      canEdit = allowed;
      await tester.tap(find.text('Aplicar corre\u00e7\u00f5es'));
      await tester.pumpAndSettle();
      expect(controller.document.toPlainText(),
          allowed ? 'Texto errado\nSegunda linha\n' : 'Texto erado\n');
      expect(
          controller.document
              .toDelta()
              .toJson()
              .any((op) => (op['attributes'] as Map?)?['bold'] == true),
          isTrue);
      controller.dispose();
    });
  }
}
