import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

@JS('edeskExtensionCall')
external JSPromise<JSString> _call(JSString value);

Future<Map<String, dynamic>> edeskExtensionCall(String path,
    {Map<String, dynamic>? body, String? uid}) async {
  // The extension uses the browser's E-Desk session, never app passwords/tokens.
  final clean = body == null ? null : jsonDecode(jsonEncode(body));
  if (clean is Map && clean['request'] is Map) {
    (clean['request'] as Map).remove('edeskCredenciais');
  }
  final result = jsonDecode(
      (await _call(jsonEncode({'path': path, 'body': clean, 'uid': uid}).toJS)
              .toDart)
          .toDart) as Map<String, dynamic>;
  if (result['error'] != null) throw StateError(result['error'].toString());
  return result;
}

Future<bool> edeskExtensionAvailable() async {
  try {
    final result = await edeskExtensionCall('/healthz')
        .timeout(const Duration(milliseconds: 1000));
    return result['mode'] == 'extension';
  } catch (_) {
    return false;
  }
}
