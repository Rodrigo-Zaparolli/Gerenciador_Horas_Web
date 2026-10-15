import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:convert';
import 'package:gerenciador_horas/core/platform/voice_web.dart';
import 'package:gerenciador_horas/core/platform/speech_web.dart';

void expect(Object? actual, Object? expected) {
  if (jsonEncode(actual) != jsonEncode(expected)) {
    throw StateError('Expected $expected, received $actual');
  }
}

Future<void> main() async {
  JSFunction? callback;
  int? stopped, cancelled;
  globalContext.setProperty(
      'projectVoiceSupported'.toJS, (() => true.toJS).toJS);
  globalContext.setProperty(
      'projectVoiceStart'.toJS,
      ((JSFunction cb) {
        callback = cb;
        cb.callAsFunction(null, '{"type":"state","value":"listening"}'.toJS);
        return 7.toJS;
      }).toJS);
  globalContext.setProperty(
      'projectVoiceStop'.toJS,
      ((JSNumber id) {
        stopped = id.toDartInt;
      }).toJS);
  globalContext.setProperty(
      'projectVoiceCancel'.toJS,
      ((JSNumber id) {
        cancelled = id.toDartInt;
      }).toJS);
  final events = <String>[];
  final client = createVoiceClient((type, value) => events.add('$type:$value'));
  expect(client.supported, true);
  client.start();
  callback!.callAsFunction(
      null, '{"type":"final","value":"Olá, implantação concluída."}'.toJS);
  expect(events, ['state:listening', 'final:Olá, implantação concluída.']);
  client.stop();
  expect(stopped, 7);
  client.dispose();
  expect(cancelled, 7);
  callback!.callAsFunction(
      null, '{"type":"final","value":"resultado atrasado"}'.toJS);
  expect(events.length, 2);
  globalContext.setProperty(
      'projectVoiceSupported'.toJS, (() => false.toJS).toJS);
  final unsupported = createVoiceClient((_, __) {});
  expect(unsupported.supported, false);
  unsupported.dispose();
  await exerciseSpeech();
  globalContext.setProperty('voiceAdapterPassed'.toJS, true.toJS);
}

Future<void> exerciseSpeech() async {
  globalContext.setProperty(
      'projectSpeechSupported'.toJS, (() => true.toJS).toJS);
  var nextId = 8;
  JSFunction? callback;
  int? cancelled;
  globalContext.setProperty(
      'projectSpeechSpeak'.toJS,
      ((JSString text, JSFunction cb) {
        callback = cb;
        final id = ++nextId;
        if (id == 9) cb.callAsFunction(null, true.toJS);
        return id.toJS;
      }).toJS);
  globalContext.setProperty(
      'projectSpeechCancel'.toJS,
      ((JSNumber id) {
        cancelled = id.toDartInt;
      }).toJS);
  final client = createSpeechClient();
  expect(await client.speak('Olá'), true);
  final pending = client.speak('Segunda fala');
  final late = callback!;
  client.cancel();
  expect(cancelled, 10);
  expect(await pending, false);
  final next = client.speak('Terceira fala');
  late.callAsFunction(null, true.toJS);
  callback!.callAsFunction(null, true.toJS);
  expect(await next, true);
  final disposed = client.speak('Descartar');
  client.dispose();
  expect(await disposed, false);
  expect(cancelled, 12);
  expect(await client.speak('Não falar'), false);
}
