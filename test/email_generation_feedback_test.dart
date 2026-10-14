import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'project_email_modal_test.dart' show MemoryEmailStore;

void main() {
  setUp(() => LocalUserState.memory = {});
  tearDown(() => LocalUserState.memory = null);
  testWidgets('missing data blocks generation with a visible list', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final project = ProjectModel(id: '123', id2: '', client: 'Cliente',
        serviceType: 'Enterprise', stage: '', task: '', status: 'TRAB',
        startDate: DateTime(2026, 10, 13), estimatedHours: '08:00',
        leader: '', hourType: 'Hs Cobradas');
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light,
        home: Scaffold(body: ProjectEmailModal(project: project,
            store: MemoryEmailStore()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gerar e-mail para Outlook'));
    await tester.pumpAndSettle();
    expect(find.text('O e-mail ainda não foi gerado'), findsOneWidget);
    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.textContaining('• Consultor')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.textContaining('• Nome do sistema')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
