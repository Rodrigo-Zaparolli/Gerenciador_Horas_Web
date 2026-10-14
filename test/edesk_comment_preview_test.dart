import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/edesk/edesk_comment_preview.dart';
import 'package:gerenciador_horas/data/services/edesk_integration.dart';
import 'products_image_field_test.dart' show png;

void main() {
  testWidgets('HTML document stays readable on dark theme without changing text color', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: const Scaffold(
      body: EdeskCommentPreview(text: '[[EDESK_HTML]]<span style="color:#111827">Comentário</span>'))));
    final surface = tester.widget<ColoredBox>(find.descendant(of: find.byType(EdeskCommentPreview), matching: find.byType(ColoredBox)).first);
    expect(surface.color, Colors.white);
    final span = tester.widget<SelectableText>(find.byType(SelectableText)).textSpan!.children!.first as TextSpan;
    expect(span.style!.color, const Color(0xFF111827));
  });
  testWidgets('preserves comment styles and avoids fixed image height', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EdeskCommentPreview(
      text: '[[EDESK_HTML]]<span style="font-family:Verdana;font-size:18px;font-weight:bold;font-style:italic;text-decoration:underline line-through;color:#234567;text-align:center;">Comentário</span><br><img src="data:image/png;base64,${base64Encode(png)}">',
    ))));
    await tester.pumpAndSettle();
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.textAlign, TextAlign.center);
    final span = text.textSpan!.children!.first as TextSpan;
    expect(span.style!.fontFamily, 'Verdana');
    expect(span.style!.fontSize, 18);
    expect(span.style!.fontWeight, FontWeight.bold);
    expect(span.style!.fontStyle, FontStyle.italic);
    expect(span.style!.color, const Color(0xFF234567));
    expect(span.style!.decoration!.contains(TextDecoration.lineThrough), isTrue);
    expect(tester.widget<Image>(find.byType(Image)).height, isNull);
  });
  testWidgets('review renders inline image and formatted text without HTML or base64', (tester) async {
    final body = '[[EDESK_HTML]]<strong>Atualização</strong><br><img src="data:image/png;base64,${base64Encode(png)}">Depois &amp; fim';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EdeskCommentPreview(text: body))));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    final texts = tester.widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.textSpan?.toPlainText() ?? w.data ?? '').join();
    expect(texts, contains('Atualização'));
    expect(texts, contains('Depois & fim'));
    expect(texts, isNot(contains('base64')));
    expect(texts, isNot(contains('EDESK_HTML')));
    expect(edeskReviewLines({'texto': body}, 'edesk_comentario.py').join(), isNot(contains('base64')));
    expect(tester.takeException(), isNull);
  });
}
