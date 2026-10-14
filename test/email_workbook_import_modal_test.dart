import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'package:gerenciador_horas/features/project_emails/products_image_field.dart';
import 'project_email_modal_test.dart' show MemoryEmailStore;
import 'products_image_field_test.dart' show png;

void main() {
  setUp(() => LocalUserState.memory = {});
  tearDown(() => LocalUserState.memory = null);
  for (final regenerate in [true, false]) {
    testWidgets(
        'sheet import regenerates=$regenerate preserves proposal print and summary',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final book = excel.Excel.createExcel();
      final sheet = book['Informações de entrada'];
      for (final row in [
        ['Nome do sistema', 'Sistema atualizado'],
        ['ID da Biblioteca', '4431'],
        ['NS para instalação', '80200790'],
        ['Versão / Revisão', '2026.1'],
        ['CYNCLY'],
        [
          'Consultor de Implantação',
          'Consultor',
          'consultor@example.com',
          '54 9999-9999'
        ],
      ]) {
        sheet.appendRow(row.map(excel.TextCellValue.new).toList());
      }
      final store = MemoryEmailStore();
      store.templates['owner-a/internal'] = {
        'subject': 'Encerramento {sistema}',
        'body':
            'Sistema: {sistema}\nBiblioteca: {biblioteca}\nNS: {ns}\nVersão: {versao}\nTelefone: {telefone_consultor}\nProdutos adquiridos pelo cliente:\n{produtos}\nResumo da implantação:\n{resumo}\nAtt,\n{consultor}'
      };
      store.drafts['owner-a/123/internal'] = {
        'fields': {'resumo': 'Resumo digitado pelo usuário'},
        'contacts': [],
        'productsImage': base64Encode(png),
        'body': 'Mensagem editada manualmente.\nAtt,\nRodrigo'
      };
      final project = ProjectModel(
          id: '123',
          id2: '',
          client: 'Cliente',
          serviceType: 'Enterprise',
          stage: '',
          task: '',
          status: 'TRAB',
          startDate: DateTime(2026, 10, 13),
          estimatedHours: '08:00',
          leader: '',
          hourType: 'Hs Cobradas');
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
              body: ProjectEmailModal(
                  project: project,
                  store: store,
                  workbookLoader: () async =>
                      Uint8List.fromList(book.encode()!)))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encerramento interno'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Selecionar planilha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Selecionar planilha'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isTrue);
      if (!regenerate) {
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.tap(find.text('Importar'));
      await tester.pumpAndSettle();
      final bodyField = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.labelText == 'Mensagem — editável',
          skipOffstage: false);
      final body = tester.widget<TextField>(bodyField).controller!.text;
      if (regenerate) {
        expect(body, contains('Sistema: Sistema atualizado'));
        expect(body, contains('NS: 80200790'));
        expect(body, isNot(contains('Telefone: 54 9999-9999')));
        expect(body, isNot(contains('Mensagem editada manualmente.')));
      } else {
        expect(body, contains('Mensagem editada manualmente.'));
      }
      expect(body, contains('Resumo digitado pelo usuário'));
      expect(
          tester.widget<Image>(find.byKey(
              const ValueKey('email-products-image-preview'))).image,
          isA<MemoryImage>());
      expect(
          tester
              .widget<ProductsImageField>(find.byType(ProductsImageField))
              .image,
          orderedEquals(png));
      await tester.tap(find.text('Salvar neste projeto'));
      await tester.pumpAndSettle();
      final saved = store.drafts['owner-a/123/internal']!;
      expect(saved['fields']['ns'], '80200790');
      expect(saved['productsImage'], base64Encode(png));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
