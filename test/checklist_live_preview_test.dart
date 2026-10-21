import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/checklist_live_preview.dart';
import 'package:gerenciador_horas/features/projects/dialogs/checklist_status_preview.dart';

void main() {
  testWidgets(
      'Changing account clears the data and rejects a reply already in flight',
      (tester) async {
    final reply = Completer<Map<String, dynamic>>();
    final preview = ChecklistLivePreview(calculate: () => reply.future);
    addTearDown(preview.dispose);
    preview.activate();
    await tester.pump(const Duration(milliseconds: 800));
    preview.clear();
    reply.complete({'total': .9});
    await tester.pump();
    expect(preview.data, isNull);
    expect(preview.error, isNull);
    expect(preview.stale, true);
  });

  testWidgets('Rapid edits produce one calculation of the latest values',
      (tester) async {
    var value = 0, calls = 0;
    final preview = ChecklistLivePreview(calculate: () async {
      calls++;
      return {'total': value};
    });
    addTearDown(preview.dispose);
    preview.activate();
    for (value = 1; value < 4; value++) {
      preview.invalidate();
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(calls, 1);
    expect(preview.data!['total'], 4);
    expect(preview.stale, false);
  });

  testWidgets(
      'Old replies are discarded and queued edits never overlap calculations',
      (tester) async {
    final replies = [
      Completer<Map<String, dynamic>>(),
      Completer<Map<String, dynamic>>()
    ];
    var calls = 0;
    final preview =
        ChecklistLivePreview(calculate: () => replies[calls++].future);
    addTearDown(preview.dispose);
    preview.activate();
    await tester.pump(const Duration(milliseconds: 800));
    preview.invalidate();
    preview.invalidate();
    await tester.pump(const Duration(milliseconds: 800));
    expect(calls, 1);
    expect(preview.stale, true);
    replies[0].complete({'total': .2});
    await tester.pump();
    expect(calls, 2);
    expect(preview.data, isNull);
    replies[1].complete({'total': .7});
    await tester.pump();
    expect(preview.data!['total'], .7);
    expect(preview.updating, false);
  });

  testWidgets(
      'Save waits for an active calculation and invalidates its response',
      (tester) async {
    final reply = Completer<Map<String, dynamic>>();
    var calls = 0, readyToSave = false;
    final preview = ChecklistLivePreview(calculate: () {
      calls++;
      return calls == 1 ? reply.future : Future.value({'total': .8});
    });
    addTearDown(preview.dispose);
    preview.activate();
    await tester.pump(const Duration(milliseconds: 800));
    unawaited(preview.pauseAndWait().then((_) => readyToSave = true));
    expect(readyToSave, false);
    reply.complete({'total': .1});
    await tester.pump();
    expect(readyToSave, true);
    expect(preview.data, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    preview.resume(clear: true);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(calls, 2);
    expect(preview.data!['total'], .8);
  });

  testWidgets(
      'Failures retain a marked outdated value and support explicit retry',
      (tester) async {
    var fail = false;
    final preview = ChecklistLivePreview(calculate: () async {
      if (fail) throw StateError('Sem conexão');
      return {'total': .3};
    });
    addTearDown(preview.dispose);
    preview.activate();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    fail = true;
    preview.invalidate();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(preview.data!['total'], .3);
    expect(preview.error, contains('Sem conexão'));
    expect(preview.stale, true);
    fail = false;
    preview.refresh();
    await tester.pump();
    expect(preview.error, isNull);
    expect(preview.stale, false);
  });

  testWidgets('Disposal cancels queued calculations', (tester) async {
    var calls = 0;
    final preview = ChecklistLivePreview(calculate: () async {
      calls++;
      return {};
    });
    preview.activate();
    preview.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
  });

  testWidgets('Compact panel scrolls instead of overflowing', (tester) async {
    final preview = ChecklistLivePreview(
        calculate: () async => {
              'total': .6,
              'rows': [
                {'label': 'Implantação', 'percentage': .75, 'weight': .45}
              ]
            });
    addTearDown(preview.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                height: 110,
                child: ChecklistStatusPanel(
                    controller: preview, unsaved: true)))));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('60,0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
