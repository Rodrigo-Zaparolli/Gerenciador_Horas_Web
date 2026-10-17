import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_template.dart';

void main() {
  test('Insere modelo sem exigir imagem ou planilha', () {
    final editor = QuillController.basic();
    expect(insertCommentTemplate(editor, 'Atualização do projeto'), isTrue);
    expect(editor.document.toPlainText(), contains('Atualização do projeto'));
    editor.dispose();
  });
  test('Respeita o cursor e preserva texto e prints já colados', () {
    final editor = QuillController.basic();
    editor.document.insert(0, 'Antes\nDepois\n');
    editor.document.insert(6, BlockEmbed.image('data:image/png;base64,print'));
    editor.updateSelection(
        const TextSelection.collapsed(offset: 0), ChangeSource.local);
    insertCommentTemplate(editor, 'Modelo');
    expect(editor.document.toPlainText(), startsWith('Modelo\n\nAntes'));
    expect(editor.document.toPlainText(), contains('Depois'));
    expect(editor.document.toDelta().toJson().any((op) => op['insert'] is Map),
        isTrue);
    editor.dispose();
  });
  test('Prioriza a tabela Excel e não duplica modelo já abaixo dela', () {
    final editor = QuillController.basic();
    editor.document = Document.fromJson([
      {
        'insert': {'image': 'data:image/png;base64,tabela'}
      },
      {'insert': '\nTexto existente\n'},
    ]);
    insertCommentTemplate(editor, 'Modelo', excelImage: 'tabela');
    final saved = editor.document.toDelta().toJson();
    expect(
        editor.document.toPlainText(), contains('Modelo\n\nTexto existente'));
    expect(
        insertCommentTemplate(editor, 'Modelo', excelImage: 'tabela'), isFalse);
    expect(editor.document.toDelta().toJson(), saved);
    editor.dispose();
  });
  test('Insere abaixo da imagem quando ela é o último conteúdo do editor', () {
    final editor = QuillController.basic();
    editor.document.insert(0, BlockEmbed.image('data:image/png;base64,tabela'));
    expect(
        insertCommentTemplate(editor, 'Modelo', excelImage: 'tabela'), isTrue);
    expect(editor.document.toPlainText(), contains('Modelo'));
    editor.dispose();
  });
  test(
      'Imagem Excel removida não impede inserir modelo; conteúdo vazio é rejeitado',
      () {
    final editor = QuillController.basic();
    editor.document.insert(0, 'Texto preservado\n');
    editor.updateSelection(
        const TextSelection.collapsed(offset: 16), ChangeSource.local);
    insertCommentTemplate(editor, 'Modelo', excelImage: 'imagem-removida');
    expect(editor.document.toPlainText(), contains('Modelo'));
    final before = editor.document.toDelta().toJson();
    expect(() => insertCommentTemplate(editor, '  '), throwsFormatException);
    expect(editor.document.toDelta().toJson(), before);
    editor.dispose();
  });
}
