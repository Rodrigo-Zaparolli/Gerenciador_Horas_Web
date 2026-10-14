import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_draft_store.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'package:gerenciador_horas/features/project_emails/products_image_field.dart';
import 'products_image_field_test.dart' show png;

class MemoryEmailStore implements EmailDraftStore {
  @override
  String? currentUserId = 'owner-a';
  final drafts = <String, Map<String, dynamic>>{};
  final templates = <String, Map<String, dynamic>>{};
  bool failReads = false;
  @override
  Future<Map<String, dynamic>?> loadDraft(
      String owner, String project, ProjectEmailKind kind) async {
    if (failReads) throw StateError('Offline');
    return drafts['$owner/$project/${kind.name}'];
  }

  @override
  Future<Map<String, dynamic>?> loadTemplate(
      String owner, ProjectEmailKind kind) async {
    if (failReads) throw StateError('Offline');
    return templates['$owner/${kind.name}'];
  }

  @override
  Future<void> saveDraft(String owner, String project, ProjectEmailKind kind,
      Map<String, dynamic> data) async {
    drafts['$owner/$project/${kind.name}'] = data;
  }

  @override
  Future<void> saveTemplate(
      String owner, ProjectEmailKind kind, Map<String, dynamic> data) async {
    templates['$owner/${kind.name}'] = data;
  }
}

void main() {
  setUp(() => LocalUserState.memory = {});
  tearDown(() => LocalUserState.memory = null);
  WidgetController.hitTestWarningShouldBeFatal = true;
  final project = ProjectModel(
      id: '2256824',
      id2: '',
      client: 'Cliente de teste',
      serviceType: 'Enterprise',
      stage: '',
      task: '',
      status: 'TRAB',
      startDate: DateTime(2026, 10, 10),
      estimatedHours: '08:00',
      leader: '',
      hourType: 'Hs Cobradas');
  testWidgets('unsaved text survives reopening without sending or cloud save',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryEmailStore();
    Widget modal() => MaterialApp(
        theme: AppTheme.light,
        home:
            Scaffold(body: ProjectEmailModal(project: project, store: store)));
    final client = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Cliente');
    await tester.pumpWidget(modal());
    await tester.pumpAndSettle();
    await tester.enterText(client, 'Texto não salvo na nuvem');
    await tester.pumpAndSettle();
    expect(store.drafts, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    store.failReads = true;
    await tester.pumpWidget(modal());
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(client).controller!.text,
        'Texto não salvo na nuvem');
    expect(find.textContaining('Rascunho recuperado'), findsOneWidget);
    expect(store.drafts, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'proposal print survives save and account draft reload and can be removed',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryEmailStore();
    const key = 'owner-a/2256824/internal';
    store.drafts[key] = {
      'fields': {'cliente': 'Cliente'},
      'contacts': [],
      'productsImage': base64Encode(png)
    };
    Widget modal() => MaterialApp(
        theme: AppTheme.light,
        home:
            Scaffold(body: ProjectEmailModal(project: project, store: store)));
    Future<void> selectInternal() async {
      await tester.ensureVisible(find.text('Encerramento interno'));
      await tester.tap(find.text('Encerramento interno'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(ProductsImageField));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(modal());
    await tester.pumpAndSettle();
    await selectInternal();
    expect(
        tester
            .widget<ProductsImageField>(find.byType(ProductsImageField))
            .image,
        orderedEquals(png));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Salvar neste projeto'));
    await tester.pumpAndSettle();
    expect(store.drafts[key]!['productsImage'], base64Encode(png));
    await tester.pumpWidget(const SizedBox());
    LocalUserState.memory!.clear();
    await tester.pumpWidget(modal());
    await tester.pumpAndSettle();
    await selectInternal();
    expect(
        tester
            .widget<ProductsImageField>(find.byType(ProductsImageField))
            .image,
        orderedEquals(png));
    await tester.ensureVisible(find.text('Remover print'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover print'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar neste projeto'));
    await tester.pumpAndSettle();
    expect(store.drafts[key]!['productsImage'], isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('summary field updates and saves a manually edited internal message', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryEmailStore();
    const key = 'owner-a/2256824/internal';
    store.drafts[key] = {'fields': {'cliente': 'Cliente'}, 'contacts': [],
      'body': 'Mensagem personalizada preservada.\n\nAtt,\nRodrigo'};
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light,
      home: Scaffold(body: ProjectEmailModal(project: project, store: store))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encerramento interno'));
    await tester.pumpAndSettle();
    final summary = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Resumo da implantação');
    final message = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Mensagem — editável');
    await tester.ensureVisible(summary);
    await tester.enterText(summary, 'Treinamento concluído.');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(message).controller!.text, contains('Resumo da implantação:\nTreinamento concluído.'));
    await tester.enterText(summary, 'Implantação concluída conforme a proposta.');
    await tester.pumpAndSettle();
    final body = tester.widget<TextField>(message).controller!.text;
    expect(body, startsWith('Mensagem personalizada preservada.'));
    expect(body, contains('Implantação concluída conforme a proposta.'));
    expect(body, isNot(contains('Treinamento concluído.')));
    expect(body, endsWith('Att,\nRodrigo'));
    await tester.tap(find.text('Salvar neste projeto'));
    await tester.pumpAndSettle();
    expect(store.drafts[key]!['body'], body);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final theme in AppVisualTheme.values) {
    for (final size in [const Size(1440, 900), const Size(390, 844)]) {
      testWidgets(
          'Email modal ${theme.name} ${size.width}: saved draft isolated by owner/project/model',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = MemoryEmailStore();
        AppAppearance.instance.value = theme;
        await tester.pumpWidget(MaterialApp(
            theme:
                theme.mode == ThemeMode.dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(
                body: ProjectEmailModal(project: project, store: store))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final clientField = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Cliente');
        await tester.enterText(clientField, 'Cliente ajustado');
        await tester.tap(find.text('Salvar neste projeto'));
        await tester.pumpAndSettle();
        expect(store.drafts['owner-a/2256824/initial']!['fields']['cliente'],
            'Cliente ajustado');
        await tester.ensureVisible(find.text('Finalização ao cliente + ER'));
        await tester.tap(find.text('Finalização ao cliente + ER'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
            find.byWidgetPredicate((w) =>
                w is TextField && w.decoration?.labelText == 'E-mail do ER'),
            findsOneWidget);
        await tester.ensureVisible(find.text('Contato inicial'));
        await tester.tap(find.text('Contato inicial'));
        await tester.pumpAndSettle();
        expect((tester.widget<TextField>(clientField).controller!).text,
            'Cliente ajustado');
        store.currentUserId = 'owner-b';
        await tester.tap(find.text('Salvar neste projeto'));
        await tester.pumpAndSettle();
        expect(store.drafts.length, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
