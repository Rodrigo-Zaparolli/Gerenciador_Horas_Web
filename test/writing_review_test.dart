import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:gerenciador_horas/shared/widgets/writing_review.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_writing_review.dart';

void main() {
  test('Textos livres permitem revisão; senhas, números e endereços não', () {
    final controller = TextEditingController();
    final focus = FocusNode();
    EditableText field(
            {TextInputType type = TextInputType.text,
            bool obscure = false,
            bool readOnly = false,
            bool autocorrect = true}) =>
        EditableText(
            controller: controller,
            focusNode: focus,
            style: const TextStyle(),
            cursorColor: Colors.blue,
            backgroundCursorColor: Colors.grey,
            keyboardType: type,
            obscureText: obscure,
            readOnly: readOnly,
            autocorrect: autocorrect);
    expect(supportsWritingReview(field()), isTrue);
    expect(supportsWritingReview(field(type: TextInputType.multiline)), isTrue);
    for (final type in [
      TextInputType.number,
      TextInputType.datetime,
      TextInputType.emailAddress,
      TextInputType.url,
      TextInputType.phone
    ]) {
      expect(supportsWritingReview(field(type: type)), isFalse);
    }
    expect(supportsWritingReview(field(obscure: true)), isFalse);
    expect(supportsWritingReview(field(readOnly: true)), isFalse);
    expect(supportsWritingReview(field(autocorrect: false)), isFalse);
    controller.dispose();
    focus.dispose();
  });

  test('Revisão preserva imagens, negrito, trechos e nova linha final', () {
    final controller = QuillController.basic();
    controller.document.insert(0, 'Relatorio errado\nTexto mantido\n');
    controller.document.format(17, 5, Attribute.bold);
    controller.document
        .insert(0, BlockEmbed.image('data:image/png;base64,abc'));
    final original = controller.document.toPlainText();
    applyCommentWritingReview(
        controller,
        original
            .replaceFirst('Relatorio', 'Relatório')
            .replaceFirst('errado', 'revisado'));
    final delta = controller.document.toDelta().toJson();
    expect(controller.document.toPlainText(), contains('Relatório revisado'));
    expect(
        delta.any((op) =>
            op['insert'] is Map && (op['insert'] as Map)['image'] != null),
        isTrue);
    expect(
        delta.any((op) =>
            op['attributes'] is Map &&
            (op['attributes'] as Map)['bold'] == true),
        isTrue);
    final before = controller.document.toDelta().toJson();
    expect(
        () => applyCommentWritingReview(controller,
            controller.document.toPlainText().replaceAll('\uFFFC', '')),
        throwsFormatException);
    expect(controller.document.toDelta().toJson(), before);
    controller.dispose();
  });

  for (final size in [const Size(1200, 800), const Size(390, 700)]) {
    testWidgets('Revisa descrição de horas com aplicar e cancelar em $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController(text: 'Descricao do servico');
      var changed = '';
      await tester.pumpWidget(MaterialApp(
          builder: (_, child) =>
              WritingReviewScope(enabled: true, child: child!),
          home: Scaffold(
              body: TextField(
                  controller: controller,
                  maxLines: 4,
                  onChanged: (value) => changed = value))));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('Revisar escrita'), findsOneWidget);
      await tester.tap(find.text('Revisar escrita'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextFormField), 'Descrição do serviço');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Descricao do servico');
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisar escrita'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextFormField), 'Descrição do serviço');
      await tester.tap(find.text('Aplicar correções'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Descrição do serviço');
      expect(changed, controller.text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
