import 'dart:convert';
import 'dart:js_interop';

@JS('projectLocalFilesCall')
external JSPromise<JSString> _call(JSString value);

Future<Map<String, dynamic>> browserFilesCall(Map<String, dynamic> args) async {
  final result = jsonDecode((await _call(jsonEncode(args).toJS).toDart).toDart)
      as Map<String, dynamic>;
  if (result['error'] != null) throw StateError(result['error'].toString());
  return result;
}
