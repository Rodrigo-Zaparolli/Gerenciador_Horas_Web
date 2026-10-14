import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/data/services/recoverable_draft.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'project_email_modal_test.dart' show MemoryEmailStore;

void main() {
  setUp(() => LocalUserState.memory = {});
  tearDown(() => LocalUserState.memory = null);
  for (final action in [
    'Manter e fechar', 'Descartar e fechar', 'Continuar editando'
  ]) {
    testWidgets('close choice: $action', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryEmailStore();
      final project = ProjectModel(id: '123', id2: '', client: 'Cliente',
          serviceType: 'Enterprise', stage: '', task: '', status: 'TRAB',
          startDate: DateTime(2026, 10, 13), estimatedHours: '08:00',
          leader: '', hourType: 'Hs Cobradas');
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light,
          home: Builder(builder: (context) => Scaffold(body: TextButton(
              onPressed: () => showDialog<void>(context: context,
                  barrierDismissible: false,
                  builder: (_) => ProjectEmailModal(project: project, store: store)),
              child: const Text('Abrir'))))));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate((w) => w is TextField &&
          w.decoration?.labelText == 'Mensagem — editável');
      await tester.enterText(field, 'Mensagem nova');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('Manter as alterações?'), findsOneWidget);
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      if (action == 'Continuar editando') {
        expect(find.byType(ProjectEmailModal), findsOneWidget);
        expect(tester.widget<TextField>(field).controller!.text, 'Mensagem nova');
      } else {
        expect(find.byType(ProjectEmailModal), findsNothing);
        final recovery = RecoverableDraft.read('owner-a', 'email.123.initial');
        if (action == 'Manter e fechar') {
          expect(recovery?['body'], 'Mensagem nova');
        } else {
          expect(recovery, isNull);
        }
        expect(store.drafts, isEmpty);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
