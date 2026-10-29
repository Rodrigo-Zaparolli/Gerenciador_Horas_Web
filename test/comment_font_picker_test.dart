import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_editor_toolbar.dart';

void main() {
  testWidgets(
      'font selection changes only the selected text and preserves emphasis',
      (tester) async {
    final controller = quill.QuillController.basic();
    final focus = FocusNode();
    controller.document.insert(0, 'Primeiro segundo');
    controller.updateSelection(
        const TextSelection(baseOffset: 9, extentOffset: 16),
        quill.ChangeSource.local);
    controller.formatSelection(quill.Attribute.bold);
    var selected = 'Roboto';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
      builder: (context, setState) => SizedBox(
          width: 200,
          child: CommentFontPicker(
            value: selected,
            controller: controller,
            editorFocus: focus,
            onChanged: (font) => setState(() => selected = font),
          )),
    ))));
    await tester.tap(find.byKey(const ValueKey('comment-font-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Noto Serif').last);
    await tester.pumpAndSettle();
    final delta = controller.document.toDelta().toJson();
    expect(selected, 'Noto Serif');
    expect(delta.first['insert'], 'Primeiro ');
    expect(delta.first['attributes'], isNull);
    expect(delta[1]['attributes'], containsPair('font', 'Noto Serif'));
    expect(delta[1]['attributes'], containsPair('bold', true));
    expect(controller.selection,
        const TextSelection(baseOffset: 9, extentOffset: 16));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    focus.dispose();
  });

  testWidgets(
      'chosen font applies to new typing and legacy saved families remain readable',
      (tester) async {
    final controller = quill.QuillController.basic();
    final focus = FocusNode();
    var selected = 'Calibri';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
      builder: (context, setState) => SizedBox(
          width: 200,
          child: CommentFontPicker(
            value: selected,
            controller: controller,
            editorFocus: focus,
            onChanged: (font) => setState(() => selected = font),
          )),
    ))));
    expect(find.text('Calibri'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('comment-font-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roboto Mono').last);
    await tester.pumpAndSettle();
    controller.replaceText(
        0, 0, 'Nova descrição', const TextSelection.collapsed(offset: 14));
    expect(controller.document.toDelta().toJson().first['attributes'],
        containsPair('font', 'Roboto Mono'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    focus.dispose();
  });

  testWidgets(
      'bundled families contain distinct glyphs instead of the same fallback',
      (tester) async {
    const files = {
      'Roboto': 'Roboto-Regular.ttf',
      'Lato': 'Lato-Regular.ttf',
      'Noto Serif': 'NotoSerif.ttf',
      'Roboto Mono': 'RobotoMono.ttf'
    };
    await tester.runAsync(() async {
      for (final entry in files.entries) {
        await (FontLoader(entry.key)
              ..addFont(rootBundle.load('assets/fonts/${entry.value}')))
            .load();
      }
    });
    final widths = <double>[];
    for (final family in CommentFontPicker.bundledFamilies) {
      final painter = TextPainter(
          text: TextSpan(
              text: 'Implantação: WWW iii 2026',
              style: TextStyle(fontFamily: family, fontSize: 24)),
          textDirection: ui.TextDirection.ltr)
        ..layout();
      widths.add(painter.width);
      painter.dispose();
    }
    expect(widths.map((width) => width.round()).toSet(), hasLength(4));
  });
}
