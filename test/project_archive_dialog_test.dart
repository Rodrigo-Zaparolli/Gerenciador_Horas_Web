import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/archive_destination_store.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_archive_dialog.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_archive_service.dart';

class FakeArchiveService extends ProjectArchiveService {
  @override
  String? uid = 'owner';
  @override
  String? get email => 'rodrigozaparolli79@gmail.com';
  @override
  bool get allowed => uid == 'owner';
  final changes = StreamController<void>.broadcast();
  @override
  Stream<void> get accountChanges => changes.stream;
  final calls = <String>[];
  String? selectedRoot;
  String? prepareError;
  int checks = 0, applies = 0;
  bool failApply = false;
  Completer<void>? prepareWait;
  @override
  Future<ArchiveDestination?> loadDestination(String owner) async =>
      const ArchiveDestination(r'C:\Finalizados');
  @override
  Future<void> saveDestination(String owner, ArchiveDestination value) async {}
  @override
  Future<void> checkCompleted(String owner, String projectId) async {
    checks++;
  }

  @override
  Future<Map<String, dynamic>> call(String action,
      {String? reference,
      String? destination,
      String? excelReference,
      String? sourceReference,
      String? operation}) async {
    calls.add(action);
    if (action == 'pick-folder')
      return {'reference': r'C:\Clientes\2261144 - Orquinare'};
    if (action == 'authorize') {
      prepareError = null;
      return {'authorized': true};
    }
    if (action == 'project-move-prepare') {
      selectedRoot = sourceReference;
      if (prepareWait != null) await prepareWait!.future;
      if (prepareError != null) throw StateError(prepareError!);
      return {
        'source': sourceReference ?? reference,
        'target': r'C:\Finalizados\2261144 - Orquinare',
        'operation': 'prepared',
        'excelInside': true,
        'alreadyMoved': false
      };
    }
    if (action == 'project-move-commit') return {'moved': true};
    throw StateError(action);
  }

  @override
  Future<void> applyMove(String projectId, Map<String, dynamic> result) async {
    applies++;
    if (failApply) throw StateError('conexão');
  }
}

void main() {
  Future<void> open(WidgetTester tester, FakeArchiveService service,
      {bool documents = false, bool settle = true}) async {
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(service.changes.close);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => ProjectArchiveDialog(
                            projectId: 'project',
                            folder: documents
                                ? r'C:\Clientes\2261144 - Orquinare\Documentos'
                                : r'C:\Clientes\2261144 - Orquinare',
                            excel:
                                r'C:\Clientes\2261144 - Orquinare\Documentos\Projeto.xlsm',
                            service: service)),
                    child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets(
      'Documents requires selecting the project root; automatic preview never moves',
      (tester) async {
    final service = FakeArchiveService();
    await open(tester, service, documents: true);
    expect(service.calls, isEmpty);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.text('Selecionar pasta inteira do projeto'));
    await tester.pumpAndSettle();
    expect(service.selectedRoot, r'C:\Clientes\2261144 - Orquinare');
    expect(service.calls, ['pick-folder', 'project-move-prepare']);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar e mover'));
    await tester.pumpAndSettle();
    expect(service.calls.where((v) => v == 'project-move-commit').length, 1);
    expect(service.applies, 1);
    expect(find.byType(ProjectArchiveDialog), findsNothing);
  });

  testWidgets(
      'Opening with a project folder automatically checks and shows progress',
      (tester) async {
    final service = FakeArchiveService()..prepareWait = Completer<void>();
    await open(tester, service, settle: false);
    expect(find.text('Conferindo pasta, planilha e destino…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    service.prepareWait!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(service.calls, ['project-move-prepare']);
  });

  testWidgets(
      'Missing authorization can be recovered and automatically checked',
      (tester) async {
    final service = FakeArchiveService()..prepareError = 'Selecione novamente';
    await open(tester, service);
    expect(find.text('Autorizar vínculos neste PC'), findsOneWidget);
    await tester.tap(find.text('Autorizar vínculos neste PC'));
    await tester.pumpAndSettle();
    expect(service.calls.where((v) => v == 'authorize').length, 3);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(service.calls.contains('project-move-commit'), isFalse);
  });

  testWidgets('Cloud failure retries links without moving again',
      (tester) async {
    final service = FakeArchiveService()..failApply = true;
    await open(tester, service);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar e mover'));
    await tester.pumpAndSettle();
    service.failApply = false;
    await tester.tap(find.text('Atualizar vínculos'));
    await tester.pumpAndSettle();
    expect(service.calls.where((v) => v == 'project-move-commit').length, 1);
    expect(service.applies, 2);
  });

  testWidgets('Account change blocks a prepared move', (tester) async {
    final service = FakeArchiveService();
    await open(tester, service);
    service.uid = 'other';
    service.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(service.calls.contains('project-move-commit'), isFalse);
  });
}
