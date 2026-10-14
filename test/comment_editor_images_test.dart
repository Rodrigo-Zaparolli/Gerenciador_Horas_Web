import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:gerenciador_horas/features/dashboard/comentario/comment_editor_images.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_editor_toolbar.dart';

void main() {
  test('Deleting Excel embed also clears only its saved preview and range', () {
    final controller = quill.QuillController.basic();
    controller.document = quill.Document.fromJson([
      {'insert': 'Texto preservado\n'},
      {
        'insert': {'image': 'data:image/png;base64,Yg=='}
      },
      {'insert': '\n'},
    ]);
    final images = ['YQ==', 'Yg=='];
    final ranges = ['Dados!A1:D3', 'Outra!B2:F7'];
    CommentEditorImages.retainPresent(controller, images, ranges);
    expect(images, ['Yg==']);
    expect(ranges, ['Outra!B2:F7']);
    CommentEditorImages.remove(controller, 'data:image/png;base64,Yg==');
    CommentEditorImages.retainPresent(controller, images, ranges);
    expect(images, isEmpty);
    expect(ranges, isEmpty);
    expect(controller.document.toPlainText(), 'Texto preservado\n\n');
    controller.dispose();
  });
  test(
      'Remove selected image occurrences and preserves text, other image and styles',
      () {
    final controller = quill.QuillController.basic();
    controller.document = quill.Document.fromJson([
      {
        'insert': 'Antes\n',
        'attributes': {'bold': true}
      },
      {
        'insert': {'image': 'data:image/png;base64,YQ=='}
      },
      {'insert': '\nDepois\n'},
      {
        'insert': {'image': 'Yg=='}
      },
      {'insert': '\n'},
      {
        'insert': {'image': 'YQ=='}
      },
      {'insert': '\nFim\n'},
    ]);
    controller.updateSelection(
        const TextSelection.collapsed(offset: 6), quill.ChangeSource.local);
    CommentEditorImages.remove(controller, 'YQ==');
    final delta = controller.document.toDelta().toJson();
    expect(delta.where((op) => op['insert'] is Map).length, 1);
    expect(delta.first['attributes'], {'bold': true});
    expect(
        controller.document.toPlainText(), 'Antes\n\nDepois\n\uFFFC\n\nFim\n');
    expect(controller.selection.baseOffset, 6);
    final before = controller.document.toDelta();
    CommentEditorImages.remove(controller, 'missing');
    expect(controller.document.toDelta(), before);
    controller.dispose();
  });

  testWidgets('Decoded image stays the same across edits and data URI forms',
      (tester) async {
    final images = CommentEditorImages();
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      expect(
          identical(images.provider(context, 'YQ=='),
              images.provider(context, 'data:image/png;base64,YQ==')),
          isTrue);
      expect(images.provider(context, 'https://example.com/image.png'), isNull);
      return const SizedBox();
    })));
  });

  testWidgets('All three indicators remain visible in a narrow toolbar',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 280,
      height: 42,
      child: CommentEditorToolbar(
        formatting: const SizedBox(width: 1200, child: Text('Formatting')),
        indicators: [
          for (final color in ['verde', 'amarelo', 'vermelho'])
            IconButton(
                tooltip: color,
                onPressed: () {},
                icon: const Icon(Icons.circle))
        ],
      ),
    ))));
    for (final color in ['verde', 'amarelo', 'vermelho']) {
      expect(find.byTooltip(color).hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
