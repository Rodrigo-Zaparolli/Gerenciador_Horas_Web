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
  static bool get preferred =>
      Firebase.apps.isNotEmpty &&
      LocalUserState.read(FirebaseAuth.instance.currentUser?.uid,
              'native-local-files')?['preferred'] ==
          true;
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
      {String? reference,
      String? name,
      String? range,
      String? revision,
      String? serviceType,
      Map<String, String>? sheetNames,
      String? destination,
      String? sourceReference,
      String? excelReference,
      String? operation,
      List<Map<String, dynamic>>? changes}) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null) {
      throw const NativeFilesException('Entre novamente na sua conta.');
    }
    final kind = serviceType?.toLowerCase() ?? '';
    if (action == 'excel-editor-sheets' || sheetNames != null) {
      final health =
          await nativeFileRequest({'action': 'health', 'interactive': true})
              .timeout(const Duration(seconds: 4));
      if (FirebaseAuth.instance.currentUser?.uid != user!.uid) {
        throw const NativeFilesException('A conta mudou.');
      }
      if (health['status'] != 200 ||
          health['data'] is! Map ||
          (health['data'] as Map)['nativeSpreadsheetSheetNames'] != true) {
        throw const NativeFilesException(
            'Atualize e reinicie a integração local v34 para configurar os nomes das abas.');
      }
    }
    if (action == 'project-move-prepare') {
      final health =
          await nativeFileRequest({'action': 'health', 'interactive': true})
              .timeout(const Duration(seconds: 4));
      if (FirebaseAuth.instance.currentUser?.uid != user!.uid) {
        throw const NativeFilesException('A conta mudou.');
      }
      final data = health['data'];
      if (health['status'] != 200 ||
          data is! Map ||
          data['projectRootMove'] != true ||
          data['verifiedProjectMove'] != true) {
        throw const NativeFilesException(
            'Atualize e reinicie a integração local v32 para conferir e mover a pasta inteira com todos os arquivos. Nenhum arquivo foi movido.');
      }
    }
    if (action == 'excel-editor-write' &&
        (kind.contains('professional') || kind.contains('profissional'))) {
      final health =
          await nativeFileRequest({'action': 'health', 'interactive': true})
              .timeout(const Duration(seconds: 4));
      if (FirebaseAuth.instance.currentUser?.uid != user!.uid) {
        throw const NativeFilesException('A conta mudou.');
      }
      final capabilities = health['data'];
      if (health['status'] != 200 ||
          capabilities is! Map ||
          capabilities['nativeSpreadsheetLayouts'] is! List ||
          !(capabilities['nativeSpreadsheetLayouts'] as List)
              .contains('professional-maker')) {
        throw const NativeFilesException(
            'Atualize e reinicie a integração local v25 para editar a planilha Professional/Maker. Nenhuma alteração foi enviada.');
      }
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
      if (serviceType != null) 'serviceType': serviceType,
      if (sheetNames != null) 'sheetNames': sheetNames,
      if (destination != null) 'destination': destination,
      if (sourceReference != null) 'sourceReference': sourceReference,
      if (excelReference != null) 'excelReference': excelReference,
      if (operation != null) 'operation': operation,
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
      if (action == 'excel-editor-preview' &&
          data['message'] == 'Ação local inválida.') {
        throw const NativeFilesException(
            'Atualize e reinicie a integração local v28 para calcular a prévia da porcentagem.');
      }
      if (action == 'authorize' && data['message'] == 'Ação local inválida.') {
        throw const NativeFilesException(
            'Atualize e reinicie a integração local v26 para autorizar os vínculos nesta janela.');
      }
      if (action.startsWith('project-move-') &&
          data['message'] == 'Ação local inválida.') {
        throw const NativeFilesException(
            'Atualize e reinicie a integração local para a versão project-destinations-24 para mover pastas de projetos finalizados.');
      }
      if (action.startsWith('excel-editor-') &&
          data['message'] == 'Ação local inválida.') {
        throw const NativeFilesException(
            'Atualize a integração local para usar o editor da planilha.');
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
