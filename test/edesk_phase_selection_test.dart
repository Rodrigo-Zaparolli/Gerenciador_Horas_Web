import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/widgets/edesk_phase_send_button.dart';

void main() {
  test('Envio selecionado usa somente as fases marcadas, na ordem do projeto',
      () {
    final phases = ['Contato', 'Consultoria', 'Treinamento', 'Acompanhamento'];
    final indices = edeskPhaseIndices(phases.length, {3, 1}, all: false);
    expect(indices.map((index) => phases[index]).toList(),
        ['Consultoria', 'Acompanhamento']);
    expect(edeskPhaseIndices(phases.length, {}, all: true), [0, 1, 2, 3]);
    expect(() => edeskPhaseIndices(4, {}, all: false), throwsStateError);
    expect(() => edeskPhaseIndices(4, {4}, all: false), throwsStateError);
    expect(() => edeskPhaseIndices(0, {}, all: true), throwsStateError);
  });

  testWidgets(
      'Menu envia todas sem seleção e desabilita opção selecionadas vazia',
      (tester) async {
    bool? all;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EdeskPhaseSendButton(
                total: 4,
                selectedCount: 0,
                busy: false,
                onSend: (value) => all = value))));
    await tester.tap(find.text('Enviar fases ao E-Desk'));
    await tester.pumpAndSettle();
    final selected = tester.widget<PopupMenuItem<bool>>(find.byWidgetPredicate(
        (w) => w is PopupMenuItem<bool> && w.value == false));
    expect(selected.enabled, isFalse);
    await tester.tap(find.text('Enviar todas as fases (4)'));
    await tester.pumpAndSettle();
    expect(all, isTrue);
  });

  testWidgets('Menu distingue envio selecionado e bloqueia envio em andamento',
      (tester) async {
    bool? all;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EdeskPhaseSendButton(
                total: 4,
                selectedCount: 2,
                busy: false,
                onSend: (value) => all = value))));
    await tester.tap(find.text('Enviar fases ao E-Desk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar selecionadas (2)'));
    await tester.pumpAndSettle();
    expect(all, isFalse);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EdeskPhaseSendButton(
                total: 4,
                selectedCount: 2,
                busy: true,
                onSend: (value) => all = value))));
    expect(
        tester
            .widget<PopupMenuButton<bool>>(find.byType(PopupMenuButton<bool>))
            .enabled,
        isFalse);
    expect(tester.takeException(), isNull);
  });
}
