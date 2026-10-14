import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_body_preview.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'products_image_field_test.dart' show png;

void main() {
  testWidgets('proposal appears at marker between products and system data', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EmailBodyPreview(
        body: 'Produtos adquiridos pelo cliente:\n$productsImageMarker\nDados gerais do sistema',
        productsImage: png))));
    await tester.pumpAndSettle();
    final image = find.byKey(const ValueKey('email-products-image-preview'));
    final before = find.text('Produtos adquiridos pelo cliente:\n');
    final after = find.text('\nDados gerais do sistema');
    expect(tester.getBottomLeft(before).dy, lessThan(tester.getTopLeft(image).dy));
    expect(tester.getBottomLeft(image).dy, lessThan(tester.getTopLeft(after).dy));
    expect(find.textContaining(productsImageMarker), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
