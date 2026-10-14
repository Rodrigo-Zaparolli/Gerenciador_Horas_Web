import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:gerenciador_horas/features/edesk/comment_document_preview.dart';
import 'products_image_field_test.dart' show png;
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/edesk/comment_document_snapshot.dart';
void main() {
  testWidgets('review uses the same document content and styles in read-only mode', (tester) async {
    final delta = <dynamic>[
      {'insert': 'Percentual: 91%', 'attributes': {'bold': true, 'size': '18'}},
      {'insert': '\nSituation: '},
      {'insert': {'image': 'data:image/png;base64,${base64Encode(png)}'}},
      {'insert': '\nNext step\n'},
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: CommentDocumentPreview(delta: delta)))));
    await tester.pumpAndSettle();
    final editor = tester.widget<quill.QuillEditor>(find.byType(quill.QuillEditor));
    expect(editor.controller.readOnly, isTrue);
    expect(editor.controller.document.toDelta().toJson(), delta);
    expect(editor.controller.document.toPlainText(), isNot(contains('50%')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('review snapshot cannot be replaced by later editor or history changes', () {
    final current = <dynamic>[{'insert': 'Percentual: 91%\n'}, {'insert': {'image': 'current-image'}}, {'insert': '\n'}];
    final snapshot = CommentDocumentSnapshot(current);
    (current.first as Map)['insert'] = 'Old saved comment: 50%';
    ((current[1] as Map)['insert'] as Map)['image'] = 'old-image';
    expect(snapshot.delta.first['insert'], 'Percentual: 91%\n');
    expect(snapshot.delta[1]['insert']['image'], 'current-image');
  });
  test('HTML preserves current text-image-text order without extra separators', () {
    final result = commentHtmlFromBlocks([
      {'tipo': 'texto', 'valor': 'Situation: '},
      {'tipo': 'imagem', 'valor': 'data:image/png;base64,YQ=='},
      {'tipo': 'texto', 'valor': '\nNext step'},
    ], (block) => block['valor']!.replaceAll('\n', '<br>'));
    expect(result, startsWith('[[EDESK_HTML]]Situation: <img'));
    expect(result, contains('vertical-align:middle;"><br>Next step'));
    expect(result, isNot(contains('<br><img')));
    expect(result, isNot(contains('Old saved comment')));
  });
  test('image dimensions survive conversion without accepting unrelated CSS', () {
    final result = commentHtmlFromBlocks([
      {'tipo': 'imagem', 'valor': 'YQ==', 'estiloImagem': 'width:80px;height:14px;background:url(untrusted);'},
    ], (_) => '');
    expect(result, contains('width:80px;height:14px;'));
    expect(result, isNot(contains('untrusted')));
  });

}
