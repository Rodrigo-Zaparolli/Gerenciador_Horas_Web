import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

const defaultEdeskApiUrl = String.fromEnvironment('EDESK_API_URL',
    defaultValue: 'http://127.0.0.1:8765');

bool _privateIpv4(String host) {
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 ||
      parts.any((part) => part == null || part < 0 || part > 255)) return false;
  return parts[0] == 10 ||
      parts[0] == 192 && parts[1] == 168 ||
      parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31;
}

String normalizeEdeskUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.scheme != 'https' &&
          !(uri.scheme == 'http' &&
              (uri.host == 'localhost' ||
                  uri.host == '127.0.0.1' ||
                  _privateIpv4(uri.host))))) {
    throw const FormatException(
        'Use um endereço HTTPS ou o IPv4 privado do computador central.');
  }
  return uri.toString().replaceFirst(RegExp(r'/+$'), '');
}

class EdeskEndpointSettings {
  EdeskEndpointSettings(
      {String? Function()? uidProvider,
      Future<Map<String, dynamic>?> Function(String uid)? read,
      Future<void> Function(String uid, Map<String, dynamic> value)? write})
      : uidProvider = uidProvider ?? _uid,
        read = read ?? _read,
        write = write ?? _write;

  final String? Function() uidProvider;
  final Future<Map<String, dynamic>?> Function(String uid) read;
  final Future<void> Function(String uid, Map<String, dynamic> value) write;
  String? _owner, _url;
  DateTime? _loaded;
  static String? _uid() =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
  static DocumentReference<Map<String, dynamic>> _document(String uid) =>
      FirebaseFirestore.instance
          .doc('users/$uid/configuracoes/edesk_integracao');
  static Future<Map<String, dynamic>?> _read(String uid) async =>
      (await _document(uid).get()).data();
  static Future<void> _write(String uid, Map<String, dynamic> value) =>
      _document(uid).set(value);

  Future<String> currentUrl({bool refresh = false}) async {
    final uid = uidProvider();
    if (uid == null) return defaultEdeskApiUrl;
    if (!refresh &&
        _owner == uid &&
        _url != null &&
        _loaded != null &&
        DateTime.now().difference(_loaded!) < const Duration(seconds: 20))
      return _url!;
    final settings = await read(uid).timeout(const Duration(seconds: 8));
    if (uidProvider() != uid)
      throw StateError('A conta mudou durante a configuração.');
    final url = settings?['mode'] == 'central'
        ? normalizeEdeskUrl(settings?['url'] as String? ?? '')
        : normalizeEdeskUrl(defaultEdeskApiUrl);
    _owner = uid;
    _url = url;
    _loaded = DateTime.now();
    return url;
  }

  Future<void> save({String? centralUrl}) async {
    final uid = uidProvider();
    if (uid == null)
      throw StateError('Entre na sua conta para configurar a integração.');
    final url = centralUrl == null
        ? normalizeEdeskUrl(defaultEdeskApiUrl)
        : normalizeEdeskUrl(centralUrl);
    await write(uid, {
      'mode': centralUrl == null ? 'local' : 'central',
      if (centralUrl != null) 'url': url
    });
    if (uidProvider() != uid)
      throw StateError('A conta mudou durante a configuração.');
    _owner = uid;
    _url = url;
    _loaded = DateTime.now();
  }
}

final edeskEndpointSettings = EdeskEndpointSettings();
