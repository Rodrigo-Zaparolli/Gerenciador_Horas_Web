import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cloud and local copies belong to the signed-in app account.
class EdeskCredentialsService {
  EdeskCredentialsService({FlutterSecureStorage? storage,
    String? Function()? uidProvider,
    Future<Map<String, dynamic>?> Function(String)? readRemote,
    Future<void> Function(String, Map<String, String>)? writeRemote,
    Future<void> Function(String)? deleteRemote,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _uidProvider = uidProvider ?? _currentUid,
       _readRemote = readRemote ?? _readCloud,
       _writeRemote = writeRemote ?? _writeCloud,
       _deleteRemote = deleteRemote ?? _deleteCloud;

  final FlutterSecureStorage _storage;
  final String? Function() _uidProvider;
  final Future<Map<String, dynamic>?> Function(String) _readRemote;
  final Future<void> Function(String, Map<String, String>) _writeRemote;
  final Future<void> Function(String) _deleteRemote;
  static String? _owner;
  static Map<String, String>? _cached;
  static DateTime? _loaded;
  static Future<Map<String, String>?>? _pending;
  static int _revision = 0;

  static String? _currentUid() => Firebase.apps.isEmpty
      ? null : FirebaseAuth.instance.currentUser?.uid;
  static DocumentReference<Map<String, dynamic>> _document(String uid) =>
      FirebaseFirestore.instance.doc('users/$uid/configuracoes/edesk_credenciais');
  static Future<Map<String, dynamic>?> _readCloud(String uid) async =>
      (await _document(uid).get(const GetOptions(source: Source.server))).data();
  static Future<void> _writeCloud(String uid, Map<String, String> data) =>
      _document(uid).set({...data, 'updatedAt': FieldValue.serverTimestamp()});
  static Future<void> _deleteCloud(String uid) => _document(uid).delete();
  String _key(String uid) => 'edesk_credentials_v2_$uid';

  String? _activeOwner() {
    final uid = _uidProvider();
    if (_owner != uid) {
      _revision++;
      _owner = uid;
      _cached = null;
      _loaded = null;
      _pending = null;
    }
    return uid;
  }

  void _checkOwner(String uid) {
    if (_uidProvider() != uid) {
      throw StateError('A conta mudou. Abra novamente as credenciais do E-Desk.');
    }
  }

  Map<String, String>? _valid(Map? data) {
    final email = data?['email'], senha = data?['senha'];
    if (email is! String || senha is! String || email.trim().isEmpty || senha.isEmpty) return null;
    return {'email': email.trim(), 'senha': senha};
  }

  void _remember(String uid, Map<String, String>? data) {
    _checkOwner(uid);
    _owner = uid;
    _cached = data == null ? null : Map.of(data);
    _loaded = DateTime.now();
  }

  Future<void> _cacheLocal(String uid, Map<String, String> data) async {
    try {
      await _storage.write(key: _key(uid), value: jsonEncode(data))
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // A browser cache failure cannot undo an acknowledged cloud save.
    }
  }

  Future<void> salvar({required String email, required String senha}) async {
    final uid = _activeOwner();
    if (uid == null) throw StateError('Entre na sua conta para salvar as credenciais.');
    final data = _valid({'email': email, 'senha': senha});
    if (data == null) throw ArgumentError('Informe o e-mail e a senha do E-Desk.');
    await _writeRemote(uid, data).timeout(const Duration(seconds: 15));
    _checkOwner(uid);
    _revision++;
    _pending = null;
    _remember(uid, data);
    await _cacheLocal(uid, data);
    _checkOwner(uid);
  }

  Future<Map<String, String>?> _load(String uid) async {
    final revision = _revision;
    Map<String, String>? result;
    try {
      result = _valid(await _readRemote(uid).timeout(const Duration(seconds: 8)));
    } catch (_) {
      _checkOwner(uid);
      if (revision != _revision) return _cached == null ? null : Map.of(_cached!);
      try {
        final raw = await _storage.read(key: _key(uid)).timeout(const Duration(seconds: 3));
        if (raw != null) result = _valid(jsonDecode(raw) as Map);
      } catch (_) {}
      _checkOwner(uid);
      if (revision != _revision) return _cached == null ? null : Map.of(_cached!);
      if (result == null) {
        throw StateError('Não foi possível carregar as credenciais salvas. Verifique a conexão e tente novamente.');
      }
      _remember(uid, result);
      return Map.of(result);
    }
    _checkOwner(uid);
    if (revision != _revision) return _cached == null ? null : Map.of(_cached!);
    if (result != null) {
      await _cacheLocal(uid, result);
    } else {
      await _storage.delete(key: _key(uid)).timeout(const Duration(seconds: 3));
    }
    _checkOwner(uid);
    if (revision != _revision) return _cached == null ? null : Map.of(_cached!);
    _remember(uid, result);
    return result == null ? null : Map.of(result);
  }

  Future<Map<String, String>?> ler() async {
    final uid = _activeOwner();
    if (uid == null) return null;
    if (_loaded != null && DateTime.now().difference(_loaded!) < const Duration(seconds: 30)) {
      return _cached == null ? null : Map.of(_cached!);
    }
    final pending = _pending ??= _load(uid);
    try {
      final data = await pending;
      _checkOwner(uid);
      return data == null ? null : Map.of(data);
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  Future<String?> lerEmail() async => (await ler())?['email'];
  Future<String?> lerSenha() async => (await ler())?['senha'];
  Future<bool> possuiCredenciais() async => await ler() != null;

  Future<void> apagar() async {
    final uid = _activeOwner();
    if (uid == null) throw StateError('Entre na sua conta para remover as credenciais.');
    await _deleteRemote(uid).timeout(const Duration(seconds: 15));
    _checkOwner(uid);
    _revision++;
    _pending = null;
    await _storage.delete(key: _key(uid)).timeout(const Duration(seconds: 3));
    _remember(uid, null);
  }
}
