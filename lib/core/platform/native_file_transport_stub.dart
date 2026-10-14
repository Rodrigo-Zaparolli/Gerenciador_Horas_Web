import 'dart:convert';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>> nativeFileRequest(
    Map<String, dynamic> args) async {
  try {
    final health = args['action'] == 'health';
    final uri = Uri.parse(
        'http://127.0.0.1:8765/${health ? 'healthz' : 'api/local-files'}');
    final result = await (health
            ? http.get(uri)
            : http.post(uri,
                headers: {
                  'Authorization': 'Bearer ${args['token']}',
                  'Content-Type': 'application/json'
                },
                body: jsonEncode({
                  'action': args['action'],
                  'reference': args['reference'],
                  'name': args['name'],
                  'range': args['range']
                })))
        .timeout(Duration(seconds: health ? 5 : 600));
    return {
      'status': result.statusCode,
      'data': jsonDecode(utf8.decode(result.bodyBytes))
    };
  } catch (_) {
    return {
      'error': 'connection',
      'message':
          'Não foi possível conectar à abertura local. Execute Iniciar abertura local.cmd neste computador.'
    };
  }
}
