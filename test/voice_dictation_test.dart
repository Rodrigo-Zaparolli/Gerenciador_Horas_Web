import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:gerenciador_horas/core/platform/voice.dart';
import 'package:gerenciador_horas/shared/widgets/dictation_text.dart';
import 'package:gerenciador_horas/shared/widgets/voice_dictation_button.dart';

class FakeVoice implements VoiceClient {
  FakeVoice(this.onEvent, {this.supported = true});
  final VoiceEventHandler onEvent;
  @override
  final bool supported;
  bool started = false, disposed = false, stopped = false;
  @override
  void start() {
    started = true;
    onEvent('state', 'listening');
  }

  @override
  void stop() {
    stopped = true;
    onEvent('state', 'idle');
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  test('dictation inserts at caret, replaces selection and separates phrases',
      () {
    final controller = TextEditingController(text: 'Bom dia!');
    controller.selection = const TextSelection.collapsed(offset: 7);
    insertDictation(controller, 'pessoal');
    expect(controller.text, 'Bom dia pessoal!');
    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 7);
    insertDictation(controller, 'trabalho');
    expect(controller.text, 'Bom trabalho pessoal!');
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    insertDictation(controller, 'Tudo certo.');
    expect(controller.text, 'Bom trabalho pessoal! Tudo certo.');
    final before = controller.value;
    insertDictation(controller, '  ');
    expect(controller.value, before);
    controller.dispose();
  });
  test('rich comment retains its image, formatting and final newline', () {
    final controller = quill.QuillController(
        document: quill.Document.fromJson([
          {
            'insert': 'Projeto',
            'attributes': {'bold': true}
          },
          {'insert': '\n'},
          {
            'insert': {'image': 'data:image/png;base64,test'}
          },
          {'insert': '\n'},
        ]),
        selection: const TextSelection.collapsed(offset: 7));
    final edit = planDictation(
        controller.document.toPlainText(), controller.selection, 'concluído',
        maxOffset: controller.document.length - 1);
    controller.replaceText(edit.start, edit.length, edit.text, edit.selection);
    final delta = controller.document.toDelta().toJson();
    expect(
        controller.document.toPlainText(), startsWith('Projeto concluído\n'));
    expect(
        delta.any((op) =>
            op['insert'] is Map &&
            op['insert']['image'] == 'data:image/png;base64,test'),
        true);
    expect(delta.first['attributes'], {'bold': true});
    expect(controller.document.toPlainText().endsWith('\n'), true);
    controller.dispose();
  });
  testWidgets('microphone is opt-in and inserts only final recognition',
      (tester) async {
    final activity = VoiceActivity();
    final clients = <FakeVoice>[], texts = <String>[];
    FakeVoice factory(VoiceEventHandler callback) {
      final c = FakeVoice(callback);
      clients.add(c);
      return c;
    }

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: VoiceDictationButton(
                activity: activity,
                onText: texts.add,
                clientFactory: factory))));
    expect(clients.every((client) => !client.started), true);
    await tester.tap(find.text('Ditar por voz'));
    await tester.pump();
    final client = clients.last;
    expect(find.text('Parar ditado'), findsOneWidget);
    expect(activity.active, true);
    client.onEvent('interim', 'projeto');
    await tester.pump();
    expect(texts, isEmpty);
    expect(find.text('Reconhecendo: projeto'), findsOneWidget);
    client.onEvent('final', 'projeto concluído');
    expect(texts, ['projeto concluído']);
    await tester.tap(find.text('Parar ditado'));
    await tester.pump();
    expect(client.stopped, true);
    expect(activity.active, false);
    expect(find.text('Ditar por voz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(client.disposed, true);
    client.onEvent('final', 'late result');
    expect(texts, ['projeto concluído']);
  });
  testWidgets(
      'changing target or saving cancels microphone and ignores late results',
      (tester) async {
    final clients = <FakeVoice>[], texts = <String>[];
    FakeVoice factory(VoiceEventHandler callback) {
      final c = FakeVoice(callback);
      clients.add(c);
      return c;
    }

    Future<void> render(String target, bool enabled) =>
        tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: VoiceDictationButton(
                    sessionKey: target,
                    enabled: enabled,
                    onText: texts.add,
                    clientFactory: factory))));
    await render('initial', true);
    await tester.tap(find.text('Ditar por voz'));
    await tester.pump();
    final old = clients.last;
    await render('finalization', true);
    expect(old.disposed, true);
    old.onEvent('final', 'wrong model');
    expect(texts, isEmpty);
    await tester.tap(find.text('Ditar por voz'));
    await tester.pump();
    final current = clients.last;
    await render('finalization', false);
    expect(current.disposed, true);
    current.onEvent('final', 'after save');
    expect(texts, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('opening another dialog stops dictation before review',
      (tester) async {
    final clients = <FakeVoice>[], texts = <String>[];
    FakeVoice factory(VoiceEventHandler cb) {
      final client = FakeVoice(cb);
      clients.add(client);
      return client;
    }

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => Column(children: [
                      VoiceDictationButton(
                          onText: texts.add, clientFactory: factory),
                      TextButton(
                          onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  const AlertDialog(content: Text('Conferir'))),
                          child: const Text('Abrir revisão')),
                    ])))));
    await tester.tap(find.text('Ditar por voz'));
    await tester.pump();
    final client = clients.last;
    await tester.tap(find.text('Abrir revisão'));
    await tester.pumpAndSettle();
    expect(client.disposed, true);
    client.onEvent('final', 'late text');
    expect(texts, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'unsupported browser and permission errors keep the rest of editor usable',
      (tester) async {
    final field = TextEditingController();
    FakeVoice? active;
    FakeVoice factory(VoiceEventHandler cb) => active = FakeVoice(cb);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      TextField(controller: field),
      VoiceDictationButton(onText: (_) {}, clientFactory: factory)
    ]))));
    await tester.tap(find.text('Ditar por voz'));
    active!.onEvent('error',
        'Permita o microfone nas configurações deste site e tente novamente.');
    await tester.pump();
    expect(find.textContaining('Permita o microfone'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'continuo digitando');
    expect(field.text, 'continuo digitando');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: VoiceDictationButton(
                onText: (_) {},
                clientFactory: (cb) => FakeVoice(cb, supported: false)))));
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(find.text('Ditado indisponível neste navegador.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    field.dispose();
  });
}
