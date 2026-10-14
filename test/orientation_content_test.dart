import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/orientations/orientation_content.dart';
import 'products_image_field_test.dart' show png;
import 'support/image_clipboard_test_stub.dart'
    if (dart.library.js_interop) 'support/image_clipboard_test_web.dart';

void main() {
  testWidgets('browser paste renders immediately while persistence is still pending', (tester) async {
    final controller = TextEditingController();
    final images = <String>[];
    final pending = Completer<void>();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (context, setState) =>
      OrientationContent(controller: controller, images: images, onPasteImage: (bytes) async {
        setState(() => images.add('data:image/png;base64,${base64Encode(bytes)}'));
        await pending.future;
      }, onRemoveImage: (_) {}, onOpenImage: (_) {})))));
    dispatchImagePaste(png); await tester.pump();
    expect(images, isEmpty);
    await tester.tap(find.byType(TextField)); await tester.pump();
    await tester.runAsync(() async {
      dispatchImagePaste(png);
      for (var i = 0; i < 500 && images.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(pending.isCompleted, isFalse);
    pending.complete();
  }, skip: !kIsWeb);
  testWidgets('content renders saved pasted/attached images and removes only selected image', (tester) async {
    final controller = TextEditingController(text: 'Procedimento');
    final images = List.filled(2, 'data:image/png;base64,${base64Encode(png)}', growable: true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (context, setState) =>
      OrientationContent(controller: controller, images: images, onPasteImage: (_) async {},
        onRemoveImage: (index) => setState(() => images.removeAt(index)), onOpenImage: (_) {})))));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(2));
    await tester.tap(find.byTooltip('Remover imagem 1')); await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(controller.text, 'Procedimento');
    expect(tester.takeException(), isNull);
  });
}
