import '../../core/platform/native_file_transport.dart';
import 'integration_downloads.dart';
import '../../shared/widgets/integration_download_panel.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../core/platform/app_reload.dart';
import 'edesk_operation_history.dart';

/// Tracks only live executions, never historic pending/uncertain results.
class EdeskActivity {
  static int active = 0;
  static Future<T> track<T>(Future<T> Function() action) async {
    active++;
    try {
      return await action();
    } finally {
      active--;
    }
  }
}

class WebReleaseMonitor extends StatefulWidget {
  const WebReleaseMonitor(
      {super.key,
      required this.child,
      this.releaseLoader,
      this.notesLoader,
      this.integrationLoader,
      this.installedIntegrationLoader,
      this.openIntegrationDownload,
      this.installedRelease,
      this.synchronize,
      this.reload,
      this.checkInterval = const Duration(seconds: 30)});
  final Widget child;
  final Future<String?> Function()? releaseLoader;
  final Future<List<String>> Function()? notesLoader;
  final Future<IntegrationDownloads?> Function()? integrationLoader;
  final Future<String?> Function()? installedIntegrationLoader;
  final Future<bool> Function(Uri)? openIntegrationDownload;
  final String? installedRelease;
  final VoidCallback? synchronize;
  final VoidCallback? reload;
  final Duration checkInterval;
  @override
  State<WebReleaseMonitor> createState() => _WebReleaseMonitorState();
}

class _WebReleaseMonitorState extends State<WebReleaseMonitor> {
  static const installed = String.fromEnvironment('WEB_RELEASE');
  Timer? _timer;
  StreamSubscription<User?>? _auth;
  bool _checking = false;
  String? _dismissed;
  String? _dismissedIntegration;
  DateTime? _lastCheck;

  @override
  void initState() {
    super.initState();
    if (widget.synchronize == null) {
      _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
        unawaited(EdeskOperationHistory.flush(user?.uid));
      });
    }
    _timer = Timer.periodic(widget.checkInterval, (_) {
      if (widget.synchronize != null) {
        widget.synchronize!();
      } else {
        unawaited(EdeskOperationHistory.flush(
            FirebaseAuth.instance.currentUser?.uid));
      }
      unawaited(_check());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final currentRelease = widget.installedRelease ?? installed;
    if ((!kIsWeb && widget.releaseLoader == null) ||
        currentRelease.isEmpty ||
        _checking ||
        !mounted ||
        EdeskActivity.active != 0 ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (_lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < const Duration(minutes: 5)) {
      return;
    }
    _checking = true;
    _lastCheck = DateTime.now();
    try {
      String? release;
      List<String> notes = [];
      IntegrationDownloads? integration;
      if (widget.releaseLoader != null) {
        release = await widget.releaseLoader!();
        notes = await widget.notesLoader?.call() ?? [];
        integration = await widget.integrationLoader?.call();
      } else {
        final response = await http
            .get(Uri.base.resolve('web-release.json').replace(queryParameters: {
              'check': DateTime.now().millisecondsSinceEpoch.toString()
            }))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) return;
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          integration = IntegrationDownloads.fromJson(decoded['integration']);
        }
        if (decoded is Map && decoded['changes'] is List) {
          notes = (decoded['changes'] as List)
              .whereType<String>()
              .map((text) => text.trim())
              .where((text) => text.isNotEmpty)
              .toList();
        }
        release = decoded is Map && decoded['release'] is String
            ? decoded['release'] as String
            : null;
      }
      final webUpdate = release != null &&
          release.isNotEmpty &&
          release != currentRelease &&
          release != _dismissed;
      String? nativeVersion;
      if (integration != null && integration.version != _dismissedIntegration) {
        try {
          if (widget.installedIntegrationLoader != null) {
            nativeVersion = await widget.installedIntegrationLoader!();
          } else if (kIsWeb) {
            final health = await nativeFileRequest(
                {'action': 'health', 'interactive': false});
            final data = health['data'];
            if (health['status'] == 200 &&
                data is Map &&
                data['service'] == 'gerenciador-horas-edesk' &&
                data['mode'] == 'local' &&
                data['busy'] != true) {
              nativeVersion = data['integrationPackageVersion']?.toString();
            }
          }
        } catch (_) {
          // Unknown/offline is not evidence of an outdated installation.
        }
      }
      final nativeNumber = int.tryParse(
          RegExp(r'(\d+)$').firstMatch(nativeVersion ?? '')?.group(1) ?? '');
      final nativeUpdate = integration != null &&
          nativeNumber != null &&
          nativeNumber < int.parse(integration.version) &&
          integration.version != _dismissedIntegration;
      if ((!webUpdate && !nativeUpdate) || !mounted) return;
      if (EdeskActivity.active != 0 ||
          ModalRoute.of(context)?.isCurrent != true) {
        // This release has not been shown. Retry on the next safe tick,
        // rather than hiding it for the five-minute network-check interval.
        _lastCheck = null;
        return;
      }
      final update = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
                title: Text(webUpdate
                    ? 'Nova versão disponível'
                    : 'Atualizar integração E-Desk'),
                content: SizedBox(
                  width: 440,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!webUpdate) ...[
                          Text(
                              'Integra\u00e7\u00e3o ativa v$nativeNumber; dispon\u00edvel v${integration!.version}.'),
                          const SizedBox(height: 8),
                        ],
                        if (webUpdate && notes.isNotEmpty) ...[
                          const Text('O que mudou nesta versão:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          for (final note in notes)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text('• $note'),
                            ),
                          const SizedBox(height: 12),
                        ] else if (webUpdate)
                          const Text('Uma nova versão do app está disponível.'),
                        if (integration != null)
                          IntegrationDownloadPanel(
                              downloads: integration,
                              openDownload: widget.openIntegrationDownload),
                        if (webUpdate)
                          const Text(
                              'Os textos dos comentários e e-mails têm recuperação local. '
                              'Salve alterações em outros formulários e selecione novamente os anexos após atualizar.'),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Depois')),
                  if (webUpdate)
                    FilledButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: const Text('Atualizar app')),
                ],
              ));
      if (!mounted) return;
      if (nativeUpdate) _dismissedIntegration = integration.version;
      if (webUpdate && update == true && EdeskActivity.active == 0) {
        (widget.reload ?? reloadApp)();
      } else {
        _dismissed = release;
      }
    } catch (_) {
      // A failed request must not suppress a subsequent online check.
      _lastCheck = null;
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
