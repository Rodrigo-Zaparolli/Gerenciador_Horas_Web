import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_native_document.dart';

void main() {
  test('native edits append paragraphs before the mandatory final newline', () {
    final c = QuillController.basic();
    for (final text in [
      'coment\u00e1rio!\n',
      'coment\u00e1rio!\nSegunda linha\n',
      'coment\u00e1rio!\nSegunda linha\n\nTerceira\n',
      '\n'
    ]) {
      applyNativeCommentDocument(
          c,
          [
            {'insert': text}
          ],
          TextSelection.collapsed(offset: text.length - 1));
      expect(c.document.toPlainText(), text);
      expect(c.document.toDelta().toJson(), [
        {'insert': text}
      ]);
    }
    c.dispose();
  });
  test('native edits preserve styles, images and block attributes', () {
    final c = QuillController.basic();
    final delta = <Map<String, dynamic>>[
      {
        'insert': 'Titulo',
        'attributes': {'bold': true, 'font': 'Lato', 'size': '18'}
      },
      {
        'insert': '\n',
        'attributes': {'align': 'center'}
      },
      {
        'insert': {'image': 'data:image/png;base64,abc'}
      },
      {'insert': '\nFim\n'}
    ];
    applyNativeCommentDocument(
        c, delta, const TextSelection.collapsed(offset: 2));
    expect(c.document.toDelta().toJson(), delta);
    final changed = <Map<String, dynamic>>[
      ...delta.take(3),
      {'insert': '\nFim\nNovo paragrafo'},
      {
        'insert': '\n',
        'attributes': {'align': 'right'}
      }
    ];
    applyNativeCommentDocument(
        c, changed, const TextSelection.collapsed(offset: 20));
    expect(c.document.toDelta().toJson(), changed);
    expect(c.document.toPlainText(), contains('Novo paragrafo'));
    c.dispose();
  });
}
