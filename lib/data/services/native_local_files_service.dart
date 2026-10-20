import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../core/platform/native_file_transport.dart';
import '../../core/platform/local_user_state.dart';

class NativeFilesException implements Exception {
  final String message;
  final String? code;
  const NativeFilesException(this.message, {this.code});
  bool get needsSetup =>
      const {'connection', 'permission', 'timeout', 'update'}.contains(code);
  @override
  String toString() => message;
}

class NativeLocalFiles {
  static bool get preferred => Firebase.apps.isNotEmpty &&
      LocalUserState.read(FirebaseAuth.instance.currentUser?.uid, 'native-local-files')?['preferred'] == true;
  static Future<bool> available() async {
    try {
      final result =
          await nativeFileRequest({'action': 'health', 'interactive': false})
              .timeout(const Duration(milliseconds: 1500));
      final data = result['data'];
      return result['status'] == 200 &&
          data is Map &&
          data['service'] == 'gerenciador-horas-edesk' &&
          data['nativeFiles'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> call(String action,
      {String? reference, String? name, String? range,
      String? revision, List<Map<String, dynamic>>? changes}) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null) {
      throw const NativeFilesException('Entre novamente na sua conta.');
    }
    // The preview endpoint is authoritative. A health flag must not block a
    // supported operation or hide the actual file/Excel/permission error.
    // Allow the user to answer the browser's device-access permission prompt.
    final result = await nativeFileRequest({
      'action': action,
      'token': token,
      'reference': reference,
      'name': name,
      'range': range,
      if (revision != null) 'revision': revision,
      if (changes != null) 'changes': changes,
      'interactive': true
    });
    if (FirebaseAuth.instance.currentUser?.uid != user!.uid) {
      throw const NativeFilesException('A conta mudou. Selecione novamente.');
    }
    if (result['error'] != null) {
      throw NativeFilesException(
          result['message']?.toString() ??
              'Não foi possível acessar a integração local.',
          code: result['error']?.toString());
    }
    final data = result['data'];
    if (data is! Map<String, dynamic>) {
      throw const NativeFilesException(
          'Resposta inválida da integração local.');
    }
    if (result['status'] != 200) {
      if (action.startsWith('excel-editor-') && data['message'] == 'Ação local inválida.') {
        throw const NativeFilesException('Atualize a integração local para usar o editor da planilha.');
      }
      if (action == 'preview' &&
          result['status'] == 400 &&
          data['message'] == 'Ação local inválida.') {
        throw const NativeFilesException(
            'A integração ativa não possui o espelho do Excel. Atualize e reinicie a abertura local neste computador.');
      }
      throw NativeFilesException(
          data['message']?.toString() ?? 'Não foi possível abrir o arquivo.');
    }
    if (data['cancelled'] != true) {
      LocalUserState.write(user.uid, 'native-local-files', {'preferred': true});
    }
    return data;
  }

  static Future<Uint8List> read(String reference) async => base64Decode(
      (await call('read', reference: reference))['base64'] as String);
}
