import 'dart:convert';
import 'dart:js_interop';

@JS('nativeLocalFilesRequest')
external JSPromise<JSString> _request(JSString value);

Future<Map<String, dynamic>> nativeFileRequest(
        Map<String, dynamic> args) async =>
    jsonDecode((await _request(jsonEncode(args).toJS).toDart).toDart)
        as Map<String, dynamic>;
