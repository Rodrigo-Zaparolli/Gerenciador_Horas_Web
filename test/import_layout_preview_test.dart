import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'package:gerenciador_horas/features/edesk/received_work_dialog.dart';
import 'received_work_store_test.dart' show ImportAuth;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = File(r'C:\Windows\Fonts\segoeui.ttf');
    if (await font.exists()) {
      await (FontLoader('Segoe UI')..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
      await (FontLoader('Ahem')..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
    }
    await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final (name, width) in [('desktop', 1440.0), ('celular', 390.0)]) {
    testWidgets('import preview fits $name without horizontal table scrolling',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
                debugShowCheckedModeBanner: false,
            // Flutter tests use Ahem for styles with no explicit family. Use
            // the same readable system family for screenshot button labels.
            theme: AppTheme.light.copyWith(
              filledButtonTheme: FilledButtonThemeData(style: AppTheme.light.filledButtonTheme.style?.copyWith(
                textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'Segoe UI', fontSize: 13, fontWeight: FontWeight.w600)))),
              textButtonTheme: TextButtonThemeData(style: AppTheme.light.textButtonTheme.style?.copyWith(
                textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'Segoe UI', fontSize: 13, fontWeight: FontWeight.w600)))),
              outlinedButtonTheme: OutlinedButtonThemeData(style: AppTheme.light.outlinedButtonTheme.style?.copyWith(
                textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'Segoe UI', fontSize: 13, fontWeight: FontWeight.w600)))),
            ),
            home: Scaffold(
                body: ReceivedWorkReview(
              auth: ImportAuth(),
              summary: const {
                'solicitacao': '2260860',
                'client': 'Cliente de exemplo',
                'leader': 'Rodrigo',
                'serviceType': 'Enterprise'
              },
              types: const ['Enterprise'],
              formats: [
                WorkFormat(id: 'enterprise', name: 'Enterprise', steps: [
                  'Contato Inicial',
                  'Levantamento de Escopo',
                  'Desenvolvimento',
                  'Implantação',
                  'Pós-Implantação'
                ])
              ],
              details: [
                for (final (id, label, hours) in [
                  ('2', 'Contato Inicial', '08:00'),
                  ('3', 'Levantamento de Escopo', '14:00'),
                  ('4', 'Desenvolvimento', '14:00'),
                  ('5', 'Implantação', '30:30'),
                  ('6', 'Pós-Implantação', '21:00')
                ])
                  {
                    'idTrabalho': id,
                    'values': {
                      'name': label,
                      'estimatedHours': hours,
                      'start': '02/07/2026',
                      'end': '30/11/2026'
                    }
                  },
              ],
              importProject: (_) async => 5,
            )),
          )));
      await tester.pumpAndSettle();
      expect(find.textContaining('Total previsto: 87:30'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/previews/importacao-melhorada/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    });
  }
}
