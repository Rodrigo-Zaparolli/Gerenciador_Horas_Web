import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:convert';
import '../lib/core/platform/voice_web.dart';

void expect(Object? actual, Object? expected) {
  if (jsonEncode(actual) != jsonEncode(expected)) {
    throw StateError('Expected $expected, received $actual');
  }
}

void main() {
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
  globalContext.setProperty('voiceAdapterPassed'.toJS, true.toJS);
}
