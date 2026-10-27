import 'package:flutter/material.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/tabela_projetos_widget.dart';
import 'package:gerenciador_horas/features/projects/widgets/project_reference_field.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/project_link_edit.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'received_work_store_test.dart' show ImportAuth, ImportDatabase;

ProjectModel project(String id, String folder, String excel) =>
    ProjectModel.fromJson({
      'id': id,
      'client': id == '2262248' ? 'MESARO' : 'ORQUINARE',
      'serviceType': 'Consultoria',
      'status': 'INI_PRO',
      'folderPath': folder,
      'excelLink': excel,
      'estimatedHours': '19:00',
    });
void main() {
  testWidgets(
      'actual dashboard editor saves new spreadsheet instead of old Orquinare link',
      (tester) async {
    tester.view.physicalSize = const Size(2200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = ImportDatabase();
    final service = FirebaseService(database: db, auth: ImportAuth());
    final original =
        project('2262248', r'C:\Clientes\Mesaro', r'C:\Desktop\Orquinare.xlsm');
    const path = 'users/owner/projects/2262248';
    db.documents[path] = original.toJson();
    final horizontal = ScrollController(), vertical = ScrollController();
    addTearDown(horizontal.dispose);
    addTearDown(vertical.dispose);
    ProjectModel? published;
    await tester.pumpWidget(MaterialApp(
        // Keep the test font's wide glyphs inside the legacy table headers.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(.5)),
          child: child!),
        home: Scaffold(
            body: TabelaProjetosWidget(
      projects: [original],
      statusList: const ['INI_PRO', 'TRAB'],
      expandedProjectIds: {},
      selectedTargetId: null,
      timeLogs: [],
      activeTimerTargetId: null,
      activeStartTime: null,
      timerState: TimerState.stopped,
      secondsElapsed: 0,
      showPostStopButton: false,
      horizontalController: horizontal,
      verticalController: vertical,
      onSelectTarget: (_) {},
      onToggleExpand: (_) {},
      onEditProject: (p) => published = p,
      onDeleteProject: (_) {},
      onAddSubTask: (_) {},
      onProjectStatusChanged: (_, __) async {},
      onSubTaskStatusChanged: (_, __) {},
      onEditSubTask: (_, __) {},
      onDeleteSubTask: (_, __) {},
      onStartTimer: (_) {},
      onPauseTimer: () {},
      onStopTimer: () {},
      onManualTime: (_) {},
      onEditLog: (_) {},
      onDeleteLog: (_) {},
      onRegisterLog: (_) {},
      onMarkTaskCompleted: (_) {},
      formatDuration: (_) => '00:00',
      firebaseService: service,
    ))));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.byTooltip('Editar Trabalho'));
    await tester.tap(find.byTooltip('Editar Trabalho'));
    await tester.pump(const Duration(milliseconds: 400));
    final referenceField = find.byWidgetPredicate((w) =>
        w is ProjectReferenceField &&
        w.decoration.labelText == 'Arquivo / Link');
    expect(referenceField, findsOneWidget);
    tester.widget<ProjectReferenceField>(referenceField).controller.text =
        r'C:\Clientes\Mesaro\Mesaro.xlsm';
    await tester.pump();
    expect(original.excelLink, r'C:\Desktop\Orquinare.xlsm');
    await tester.tap(find.text('Salvar altera\u00e7\u00f5es'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(db.documents[path]!['excelLink'], r'C:\Clientes\Mesaro\Mesaro.xlsm');
    expect(published?.excelLink, r'C:\Clientes\Mesaro\Mesaro.xlsm');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
  const mesaroFolder = r'C:\Clientes\2262248 - Mesaro\Documentos';
  const oldExcel = r'C:\Users\rodri\Desktop\Orquinare Planejados.xlsm';
  const mesaroExcel = r'C:\Clientes\2262248 - Mesaro\Documentos\Mesaro.xlsm';
  test(
      'editing Mesaro replaces its selected paths and leaves Orquinare untouched after reopen',
      () async {
    final db = ImportDatabase();
    final service = FirebaseService(database: db, auth: ImportAuth());
    final original = project('2262248', mesaroFolder, oldExcel);
    final other =
        project('2261144', r'C:\Clientes\2261144 - Orquinare', oldExcel);
    db.documents['users/owner/projects/2262248'] = original.toJson();
    db.documents['users/owner/projects/2261144'] = other.toJson();
    final edit = ProjectLinkEdit(original);
    edit.draft.excelLink = mesaroExcel;
    await edit.save(service);
    expect(db.documents['users/owner/projects/2262248']!['excelLink'],
        mesaroExcel);
    expect(
        db.documents['users/owner/projects/2261144']!['excelLink'], oldExcel);
    expect(original.excelLink, oldExcel);
    final reopened =
        ProjectModel.fromJson(db.documents['users/owner/projects/2262248']!);
    expect(reopened.folderPath, mesaroFolder);
    expect(reopened.excelLink, mesaroExcel);
    // A later task/status save from stale UI cannot undo the selected paths.
    original.status = 'TRAB';
    await service.salvarProjeto(original);
    expect(db.documents['users/owner/projects/2262248']!['excelLink'],
        mesaroExcel);
  });
  test(
      'folder and spreadsheet changes both persist; explicit removal stays removed',
      () async {
    final db = ImportDatabase();
    final service = FirebaseService(database: db, auth: ImportAuth());
    final original = project('2262248', 'old-folder', oldExcel);
    db.documents['users/owner/projects/2262248'] = original.toJson();
    final edit = ProjectLinkEdit(original);
    edit.draft.folderPath = mesaroFolder;
    edit.draft.excelLink = mesaroExcel;
    await edit.save(service);
    final remove = ProjectLinkEdit(edit.draft);
    remove.draft.folderPath = null;
    remove.draft.excelLink = null;
    await remove.save(service);
    final data = db.documents['users/owner/projects/2262248']!;
    expect(data['folderPath'], isNull);
    expect(data['excelLink'], isNull);
  });
  test('concurrent edit rejects the save and keeps original project isolated',
      () async {
    final db = ImportDatabase();
    final service = FirebaseService(database: db, auth: ImportAuth());
    final original = project('2262248', mesaroFolder, oldExcel);
    const path = 'users/owner/projects/2262248';
    db.documents[path] = original.toJson();
    final edit = ProjectLinkEdit(original);
    edit.draft.excelLink = mesaroExcel;
    db.beforeTransaction =
        () => db.documents[path]!['excelLink'] = 'changed-in-other-editor';
    await expectLater(edit.save(service), throwsStateError);
    expect(original.excelLink, oldExcel);
    expect(db.documents[path]!['excelLink'], 'changed-in-other-editor');
  });
}
