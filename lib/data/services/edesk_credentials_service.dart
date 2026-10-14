import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EdeskCredentialsService {
  EdeskCredentialsService({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _emailKey = 'edesk_email';
  static const String _passwordKey = 'edesk_password';

  Future<void> salvar({
    required String email,
    required String senha,
  }) async {
    await _storage.write(
      key: _emailKey,
      value: email.trim(),
    );

    await _storage.write(
      key: _passwordKey,
      value: senha,
    );
  }

  Future<String?> lerEmail() async {
    return _storage.read(
      key: _emailKey,
    );
  }

  Future<String?> lerSenha() async {
    return _storage.read(
      key: _passwordKey,
    );
  }

  Future<Map<String, String>?> ler() async {
    final email = await lerEmail();
    final senha = await lerSenha();

    if (email == null ||
        email.trim().isEmpty ||
        senha == null ||
        senha.isEmpty) {
      return null;
    }

    return {
      'email': email.trim(),
      'senha': senha,
    };
  }

  Future<bool> possuiCredenciais() async {
    final dados = await ler();
    return dados != null;
  }

  Future<void> apagar() async {
    await _storage.delete(
      key: _emailKey,
    );

    await _storage.delete(
      key: _passwordKey,
    );
  }
}
