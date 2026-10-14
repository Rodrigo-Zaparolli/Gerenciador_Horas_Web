import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/products_image_field.dart';
import 'support/image_clipboard_test_stub.dart'
    if (dart.library.js_interop) 'support/image_clipboard_test_web.dart';

final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
void main() {
  testWidgets('pasted proposal is shown in its field and can be removed',
      (tester) async {
    Uint8List? image;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => ProductsImageField(
                    image: image,
                    clipboardReader: () async => png,
                    onChanged: (next) => setState(() => image = next))))));
    await tester.runAsync(() async {
      await tester.tap(find.text('Colar print'));
      for (var i = 0; i < 500 && image == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(image, isNotNull);
    });
    await tester.pumpAndSettle();
    expect(image, isNotNull);
    expect(
        find.byKey(const ValueKey('products-proposal-image')), findsOneWidget);
    await tester.tap(find.text('Remover print'));
    await tester.pumpAndSettle();
    expect(image, isNull);
    expect(find.byKey(const ValueKey('products-proposal-image')), findsNothing);
  });
  testWidgets('non-image clipboard leaves the existing print untouched',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProductsImageField(
                image: png,
                clipboardReader: () async => null,
                onChanged: (_) => fail('Must preserve the existing image')))));
    await tester.tap(find.text('Colar print'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('products-proposal-image')), findsOneWidget);
    expect(find.textContaining('Copie o print'), findsOneWidget);
  });
  testWidgets(
      'browser paste event works only while the products field is focused',
      (tester) async {
    Uint8List? image;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => ProductsImageField(
                    image: image,
                    onChanged: (next) => setState(() => image = next))))));
    dispatchImagePaste(png);
    await tester.pump();
    expect(image, isNull);
    await tester.tap(find.text('Produtos adquiridos'));
    await tester.pump();
    await tester.runAsync(() async {
      dispatchImagePaste(png);
      for (var i = 0; i < 500 && image == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(image, isNotNull);
    });
    await tester.pumpAndSettle();
    expect(image, isNotNull);
    expect(
        find.byKey(const ValueKey('products-proposal-image')), findsOneWidget);
  }, skip: !kIsWeb);
}
