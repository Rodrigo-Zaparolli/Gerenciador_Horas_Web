import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/data/services/recoverable_draft.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_draft_store.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'package:gerenciador_horas/features/project_emails/products_image_field.dart';
import 'products_image_field_test.dart' show png;
import 'voice_dictation_test.dart' show FakeVoice;
import 'package:gerenciador_horas/core/platform/voice.dart';

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
  testWidgets('dictation edits the email without sending and is isolated when switching models', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryEmailStore();
    final clients = <FakeVoice>[];
    FakeVoice factory(VoiceEventHandler cb) { final client = FakeVoice(cb); clients.add(client); return client; }
    store.drafts['owner-a/2256824/initial'] = {'body': 'Mensagem existente.', 'contacts': [], 'recipientsConfigured': true};
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProjectEmailModal(project: project, store: store, voiceFactory: factory))));
    await tester.pumpAndSettle();
    final message = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Mensagem — editável');
    await tester.ensureVisible(find.text('Ditar por voz'));
    await tester.tap(find.text('Ditar por voz'));
    await tester.pump();
    final recording = clients.last;
    recording.onEvent('final', 'O treinamento foi concluído.');
    await tester.pump();
    expect(tester.widget<TextField>(message).controller!.text, 'Mensagem existente. O treinamento foi concluído.');
    expect(store.drafts['owner-a/2256824/initial']!['body'], 'Mensagem existente.');
    await tester.tap(find.text('Salvar neste projeto'));
    await tester.pump();
    expect(store.drafts['owner-a/2256824/initial']!['body'], 'Mensagem existente.');
    expect(find.text('Pare o ditado e revise o texto antes de salvar.'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, ProjectEmailKind.finalization.label));
    await tester.tap(find.widgetWithText(ChoiceChip, ProjectEmailKind.finalization.label));
    await tester.pumpAndSettle();
    expect(recording.disposed, true);
    recording.onEvent('final', 'Não deve entrar em outro modelo');
    expect(tester.widget<TextField>(message).controller!.text, isNot(contains('Não deve entrar')));
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, ProjectEmailKind.initial.label));
    await tester.tap(find.widgetWithText(ChoiceChip, ProjectEmailKind.initial.label));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(message).controller!.text, contains('O treinamento foi concluído.'));
    await tester.tap(find.text('Salvar neste projeto'));
    await tester.pumpAndSettle();
    expect(store.drafts['owner-a/2256824/initial']!['body'], contains('O treinamento foi concluído.'));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('finalization with existing empty draft offers workbook contacts from another model', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryEmailStore();
    for (final kind in ['initial', 'finalization']) {
      store.drafts['owner-a/2256824/$kind'] = {
        'contacts': [], 'recipientsConfigured': true,
      };
    }
    store.drafts['owner-a/2256824/internal'] = {
      'contacts': [
        EmailContact(name: 'Cliente importado', email: 'cliente@example.com',
          group: 'Cliente', destination: 'Para').toJson(),
        EmailContact(name: 'Relacionamento', email: 'er@example.com',
          role: 'Exec. de Relacionamento', destination: 'Cc').toJson(),
      ],
    };
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light,
      home: Scaffold(body: ProjectEmailModal(project: project, store: store))));
    await tester.pumpAndSettle();
    final model = find.widgetWithText(ChoiceChip, ProjectEmailKind.finalization.label);
    await tester.ensureVisible(model);
    await tester.tap(model);
    await tester.pumpAndSettle();
    final addTo = find.byTooltip('Adicionar em Para');
    await tester.ensureVisible(addTo);
    await tester.tap(addTo);
    await tester.pumpAndSettle();
    expect(find.text('Cliente importado \u2014 cliente@example.com'), findsOneWidget);
    expect(find.text('Relacionamento \u2014 er@example.com'), findsOneWidget);
    await tester.tap(find.text('Cliente importado \u2014 cliente@example.com'));
    await tester.pumpAndSettle();
    final addCc = find.byTooltip('Adicionar em Cc');
    await tester.ensureVisible(addCc);
    await tester.tap(addCc);
    await tester.pumpAndSettle();
    expect(find.text('Cliente importado \u2014 cliente@example.com'), findsNothing);
    expect(find.text('Relacionamento \u2014 er@example.com'), findsOneWidget);
    expect(store.drafts['owner-a/2256824/finalization']!['contacts'], isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('all three models offer contacts recovered from a different local draft', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryEmailStore();
    for (final kind in ProjectEmailKind.values) {
      store.drafts['owner-a/2256824/${kind.name}'] = {
        'contacts': [], 'recipientsConfigured': true,
      };
    }
    RecoverableDraft.save('owner-a', 'email.2256824.internal', {
      'contacts': [EmailContact(name: 'Contato da planilha', email: 'planilha@example.com',
        group: 'Cliente').toJson()], 'recipientsConfigured': true,
    });
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light,
      home: Scaffold(body: ProjectEmailModal(project: project, store: store))));
    await tester.pumpAndSettle();
    for (final kind in ProjectEmailKind.values) {
      final model = find.widgetWithText(ChoiceChip, kind.label);
      await tester.ensureVisible(model);
      await tester.tap(model);
      await tester.pumpAndSettle();
      final add = find.byTooltip('Adicionar em Para');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Contato da planilha — planilha@example.com'), findsOneWidget);
      // Close the menu without selecting: availability must not select recipients.
      await tester.tapAt(const Offset(1430, 10));
      await tester.pumpAndSettle();
    }
    expect(store.drafts.values.every((draft) => (draft['contacts'] as List).isEmpty), true);
    expect(tester.takeException(), isNull);
  });
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
