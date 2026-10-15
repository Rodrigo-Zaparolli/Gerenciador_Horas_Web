import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_recipient_fields.dart';
import 'package:gerenciador_horas/features/project_emails/products_image_field.dart';
import 'project_email_modal_test.dart' show MemoryEmailStore;
import 'products_image_field_test.dart' show png;

void main() {
  setUp(() => LocalUserState.memory = {});
  tearDown(() => LocalUserState.memory = null);
  for (final origin in ProjectEmailKind.values) {
    testWidgets('workbook imported in ${origin.name} remains available in all three models', (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final book = excel.Excel.createExcel();
      final sheet = book['Informações de entrada'];
      for (final row in [
        ['CLIENTE'], ['Proprietário', 'Cliente planilha', 'cliente@example.com'],
        ['CYNCLY'], ['Exec. de Relacionamento', 'ER planilha', 'er@example.com'],
      ]) {
        sheet.appendRow(row.map(excel.TextCellValue.new).toList());
      }
      final store = MemoryEmailStore();
      for (final kind in ProjectEmailKind.values) {
        store.drafts['owner-a/123/${kind.name}'] = {'contacts': [], 'recipientsConfigured': true};
      }
      final project = ProjectModel(id: '123', id2: '', client: 'Cliente', serviceType: 'Enterprise',
        stage: '', task: '', status: 'TRAB', startDate: DateTime(2026, 10, 15),
        estimatedHours: '08:00', leader: '', hourType: 'Hs Cobradas');
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body:
        ProjectEmailModal(project: project, store: store,
          workbookLoader: () async => Uint8List.fromList(book.encode()!)))));
      await tester.pumpAndSettle();
      final originChip = find.widgetWithText(ChoiceChip, origin.label);
      await tester.ensureVisible(originChip);
      await tester.tap(originChip);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Selecionar planilha'));
      await tester.tap(find.text('Selecionar planilha'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Importar'));
      await tester.pumpAndSettle();
      for (final kind in ProjectEmailKind.values) {
        final chip = find.widgetWithText(ChoiceChip, kind.label);
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        final contacts = tester.widget<EmailRecipientFields>(find.byType(EmailRecipientFields)).contacts;
        expect(contacts.map((contact) => contact.email).toSet(),
          containsAll(['cliente@example.com', 'er@example.com']));
        // Remove any preselection so every imported address must be offered by +.
        for (final label in ['Para', 'Cc']) {
          final container = find.byKey(ValueKey('recipient-container-$label'));
          final chips = find.descendant(of: container, matching: find.byType(InputChip));
          for (final chip in tester.widgetList<InputChip>(chips).toList()) {
            chip.onDeleted!();
          }
        }
        await tester.pumpAndSettle();
        final add = find.byTooltip('Adicionar em Para');
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(find.text('Cliente planilha — cliente@example.com'), findsOneWidget);
        expect(find.text('ER planilha — er@example.com'), findsOneWidget);
        await tester.tapAt(const Offset(1430, 10));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
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
