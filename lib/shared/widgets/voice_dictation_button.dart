import 'package:flutter/material.dart';
import '../../core/platform/voice.dart';
import '../../core/theme/app_palette.dart';

class VoiceActivity {
  bool active = false;
}

class VoiceDictationButton extends StatefulWidget {
  const VoiceDictationButton(
      {super.key,
      required this.onText,
      this.enabled = true,
      this.activity,
      this.sessionKey,
      this.clientFactory});
  final ValueChanged<String> onText;
  final bool enabled;
  final VoiceActivity? activity;
  final Object? sessionKey;
  final VoiceClientFactory? clientFactory;
  @override
  State<VoiceDictationButton> createState() => _VoiceDictationButtonState();
}

class _VoiceDictationButtonState extends State<VoiceDictationButton> {
  VoiceClient? _client;
  String _state = 'idle', _interim = '', _error = '';
  int _generation = 0;
  late bool _supported;
  bool get _active => _state != 'idle';
  VoiceClientFactory get _factory => widget.clientFactory ?? createVoiceClient;
  @override
  void initState() {
    super.initState();
    _checkSupport();
  }

  void _checkSupport() {
    final probe = _factory((_, __) {});
    _supported = probe.supported;
    probe.dispose();
  }

  @override
  void didUpdateWidget(VoiceDictationButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || oldWidget.sessionKey != widget.sessionKey) _cancel();
    if (oldWidget.clientFactory != widget.clientFactory) {
      _cancel();
      _checkSupport();
    }
  }

  void _cancel() {
    _generation++;
    _client?.dispose();
    _client = null;
    _state = 'idle';
    _interim = '';
    widget.activity?.active = false;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  void _toggle() {
    if (_active) {
      _client?.stop();
      return;
    }
    _cancel();
    final generation = _generation;
    setState(() => _error = '');
    _client = _factory((type, value) {
      if (!mounted || !widget.enabled || generation != _generation) return;
      if (ModalRoute.of(context)?.isCurrent == false) {
        setState(_cancel);
        return;
      }
      if (type == 'final') {
        widget.onText(value);
        return;
      }
      setState(() {
        if (type == 'state') {
          _state = value;
          if (value == 'idle') _interim = '';
        }
        if (type == 'interim') _interim = value;
        if (type == 'error') {
          _error = value;
          _state = 'idle';
          _interim = '';
        }
      });
      widget.activity?.active = _active;
    });
    try {
      _client!.start();
    } catch (_) {
      setState(() {
        _cancel();
        _error = 'Não foi possível iniciar o microfone. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (!currentRoute && _active) _cancel();
    final hint = !_supported
        ? 'Ditado indisponível neste navegador.'
        : _state == 'starting'
            ? 'Aguardando o microfone…'
            : _state == 'stopping'
                ? 'Concluindo ditado…'
                : _active
                    ? 'Ouvindo em português…'
                    : 'Áudio pode ser processado online pelo navegador.';
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
              spacing: 8,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Tooltip(
                    message:
                        'Ditado em português do Brasil. O navegador pode enviar o áudio para processamento online. Revise o texto antes de enviar.',
                    child: OutlinedButton.icon(
                        onPressed: widget.enabled &&
                                currentRoute &&
                                _supported &&
                                _state != 'stopping'
                            ? _toggle
                            : null,
                        icon: Icon(
                            _active
                                ? Icons.stop_circle_outlined
                                : Icons.mic_none,
                            size: 17),
                        label: Text(_active ? 'Parar ditado' : 'Ditar por voz'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor:
                                _active ? AppPalette.danger : AppPalette.accent,
                            visualDensity: VisualDensity.compact))),
                Text(hint,
                    style:
                        TextStyle(color: AppPalette.secondary, fontSize: 10)),
              ]),
          if (_interim.isNotEmpty)
            Semantics(
                liveRegion: true,
                child: Text('Reconhecendo: $_interim',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: AppPalette.secondary, fontSize: 11))),
          if (_error.isNotEmpty)
            Semantics(
                liveRegion: true,
                child: Text(_error,
                    style: TextStyle(color: AppPalette.danger, fontSize: 11))),
        ]);
  }
}
