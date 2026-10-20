import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/archive_destination_store.dart';
import 'package:gerenciador_horas/features/projects/dialogs/archive_destination_dialog.dart';

class MemoryDestinationStore implements ArchiveDestinationStore {
  @override
  String? currentUserId = 'owner';
  @override
  String? currentEmail = 'rodrigozaparolli79@gmail.com';
  final values = <String, ArchiveDestination>{};
  int writes = 0;
  @override
  Future<ArchiveDestination?> load(String uid) async => values[uid];
  @override
  Future<void> save(String uid, ArchiveDestination destination) async {
    if (currentUserId != uid) throw StateError('Conta mudou');
    writes++;
    values[uid] = destination;
  }
}

void main() {
  const selected =
      'desktop-folder://local/owner/12345678-1234-1234-1234-123456789012/C%3A%5CFinalizados';
  test(
      'Windows paths, account-specific suggestion and legacy preference remain valid',
      () {
    expect(ArchiveDestination.suggestion(' RODRIGOZAPAROLLI79@GMAIL.COM '),
        ArchiveDestination.ownerPath);
    expect(ArchiveDestination.suggestion('other@company.com'), '');
    expect(
        ArchiveDestination.fromData({'destination': selected}, 'owner')!.path,
        r'C:\Finalizados');
    expect(
        ArchiveDestination.fromData({'destination': selected}, 'other')!
            .reference,
        isNull);
    expect(
        ArchiveDestination.fromData({'destination': r'C:\Legacy'}, 'owner')!
            .destination,
        r'C:\Legacy');
    for (final path in [
      'relative',
      'https://example.com',
      'C:folder',
      'C:\\folder\nwrong'
    ]) {
      expect(ArchiveDestination.validPath(path), isFalse);
    }
    expect(ArchiveDestination.validPath(r'\\server\share\Finalizados'), isTrue);
    expect(
        () => const ArchiveDestination(r'C:\Different', reference: selected)
            .toData(),
        throwsArgumentError);
  });

  Future<void> open(WidgetTester tester, MemoryDestinationStore store) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) => ArchiveDestinationDialog(
                            store: store, pickFolder: () async => selected)),
                    child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Owner path is prefilled and typed destination is saved only for that account',
      (tester) async {
    final store = MemoryDestinationStore();
    await open(tester, store);
    expect(find.text(ArchiveDestination.ownerPath), findsOneWidget);
    await tester.enterText(find.byType(TextField), r'C:\Novo destino');
    await tester.tap(find.text('Salvar destino'));
    await tester.pumpAndSettle();
    expect(store.values['owner']!.destination, r'C:\Novo destino');
    expect(store.values['owner']!.reference, isNull);
    expect(store.values['other'], isNull);
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text(r'C:\Novo destino'), findsOneWidget);
  });

  testWidgets(
      'Windows selection saves its native reference, editing it clears authorization',
      (tester) async {
    final store = MemoryDestinationStore();
    await open(tester, store);
    await tester.tap(find.text('Selecionar pasta no Windows'));
    await tester.pumpAndSettle();
    expect(find.text(r'C:\Finalizados'), findsOneWidget);
    await tester.tap(find.text('Salvar destino'));
    await tester.pumpAndSettle();
    expect(store.values['owner']!.reference, selected);
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), r'C:\Outro local');
    await tester.tap(find.text('Salvar destino'));
    await tester.pumpAndSettle();
    expect(store.values['owner']!.destination, r'C:\Outro local');
    expect(store.values['owner']!.reference, isNull);
  });

  testWidgets(
      'Another account has no owner default; invalid path and account switch never save',
      (tester) async {
    final store = MemoryDestinationStore()
      ..currentUserId = 'other'
      ..currentEmail = 'other@company.com';
    await open(tester, store);
    expect(find.text(ArchiveDestination.ownerPath), findsNothing);
    await tester.enterText(find.byType(TextField), 'relative');
    await tester.tap(find.text('Salvar destino'));
    await tester.pumpAndSettle();
    expect(store.writes, 0);
    await tester.enterText(find.byType(TextField), r'C:\Finalizados');
    store.currentUserId = 'changed';
    await tester.tap(find.text('Salvar destino'));
    await tester.pumpAndSettle();
    expect(store.writes, 0);
  });
}
