import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/platform/beta_audio.dart';
import '../../domain/models/dashboard_models.dart';
import '../tasks/daily_hours_voice_command.dart' show dayHoursMinutes;
import '../tasks/theo_replies.dart' show spokenHours;
import 'beta_access.dart';
import 'beta_hologram.dart';
import 'beta_controls.dart';

String betaNormalize(String text) => text
    .toLowerCase()
    .trim()
    .replaceAll('á', 'a')
    .replaceAll('ã', 'a')
    .replaceAll('â', 'a')
    .replaceAll('ê', 'e')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ô', 'o')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
bool betaWake(String text) =>
    RegExp(r'^(?:(?:ola|oi|abrir|abre) (?:a )?)?beta$')
        .hasMatch(betaNormalize(text));
String betaHoursFingerprint(List<TimeLog> logs) {
  final rows = logs
      .map((l) => jsonEncode([
            l.id,
            l.targetId,
            l.date.toIso8601String(),
            l.startTime,
            l.endTime,
            l.taskName,
            l.description,
            l.typeHs,
            l.isRegistered
          ]))
      .toList()
    ..sort();
  return jsonEncode(rows);
}

class BetaAssistant extends StatefulWidget {
  const BetaAssistant(
      {super.key,
      required this.child,
      required this.owner,
      required this.loadDay,
      required this.openTasks,
      required this.canNavigate,
      this.accountIsCurrent,
      this.audioFactory,
      this.voiceTransport,
      required this.send});
  final Widget child;
  final String owner;
  final Future<List<TimeLog>> Function(DateTime) loadDay;
  final VoidCallback openTasks;
  final bool Function() canNavigate;
  final Future<String?> Function(List<TimeLog>) send;
  final bool Function()? accountIsCurrent;
  final BetaAudio Function(void Function(String, String), BetaTransport)?
      audioFactory;
  final BetaTransport? voiceTransport;
  @override
  State<BetaAssistant> createState() => _BetaAssistantState();
}

class _BetaAssistantState extends State<BetaAssistant> {
  late final BetaAudio _audio;
  final _input = TextEditingController();
  String _phase = 'asleep', _message = '', _status = 'Escuta desligada';
  bool _armed = false, _working = false, _speaking = false, _offered = false;
  int _turn = 0;
  DateTime? _day;
  List<TimeLog> _logs = [];
  String _snapshot = '';
  bool get _current {
    if (widget.accountIsCurrent != null) {
      return mounted && widget.accountIsCurrent!();
    }
    final user = FirebaseAuth.instance.currentUser;
    return mounted &&
        user?.uid == widget.owner &&
        BetaAccess.allows(uid: user?.uid, email: user?.email);
  }

  @override
  void initState() {
    super.initState();
    _audio = (widget.audioFactory ?? createBetaAudio)(_event, _request);
    BetaControls.requests.addListener(_headerRequest);
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)BetaControls.state.value=const BetaControlState();
    });
  }

  void _headerRequest() {
    if (_current && !_working) unawaited(_activate());
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    BetaControls.state.value =
        BetaControlState(armed: _armed, busy: _working, status: _status);
  }

  @override
  void dispose() {
    _turn++;
    BetaControls.requests.removeListener(_headerRequest);
    _audio.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<String> _request(String raw) async {
    if (!_current) throw StateError('A conta mudou.');
    if (widget.voiceTransport != null) return widget.voiceTransport!(raw);
    final token = await FirebaseAuth.instance.currentUser!.getIdToken();
    if (!_current || token == null) throw StateError('Entre novamente.');
    final client = http.Client();
    try {
      final response = await client
          .post(Uri.parse('http://127.0.0.1:8765/api/beta-voice'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token'
              },
              body: raw)
          .timeout(const Duration(seconds: 90));
      if (!_current) throw StateError('A conta mudou.');
      if (response.statusCode != 200) {
        if (response.statusCode == 404)
          throw StateError(
              'Atualize a integração para v60 e execute Preparar voz Beta.cmd.');
        final body = jsonDecode(response.body);
        throw StateError(body['message']?.toString() ??
            'Verifique a integração local da BETA.');
      }
      return response.body;
    } finally {
      client.close();
    }
  }

  void _event(String type, String value) {
    if (!_current) return;
    if (type == 'text' && _armed && !_working && !_speaking) {
      unawaited(_command(value));
    }
    if (type == 'state') setState(() => _status = 'Estou ouvindo');
    if (type == 'error') {
      setState(() {
        _armed = false;
        _status = value;
      });
    }
  }

  void _resume() {
    if (_current && _armed && !_speaking && !_working) _audio.listen(_phase);
  }

  Future<void> _say(String text) async {
    if (!_current) return;
    final turn = _turn;
    setState(() {
      _message = text;
      _speaking = true;
      _status = 'Preparando voz Dora…';
    });
    _audio.stop();
    try {
      await _audio.speak(text);
    } catch (error) {
      if (_current && turn == _turn) {
        setState(() => _status = error is StateError
            ? error.message.toString()
            : 'Não consegui reproduzir a voz local. Confira se a integração v60 está ativa e se Preparar voz Beta.cmd foi executado.');
      }
    } finally {
      if (_current && turn == _turn) {
        setState(() => _speaking = false);
        _resume();
      }
    }
  }

  Future<void> _activate() async {
    if (_armed) {
      _audio.stop();
      setState(() {
        _armed = false;
        _speaking = false;
        _status = 'Escuta desligada';
      });
      return;
    }
    setState(() => _status = 'Verificando voz local…');
    try {
      final status =
          jsonDecode(await _request(jsonEncode({'action': 'status'})));
      if (!_current) return;
      if (status['ready'] != true) {
        throw StateError(
            'Prepare a voz local com scripts/setup_beta_voice.ps1.');
      }
      setState(() => _armed = true);
      _resume();
    } catch (error) {
      if (_current) {
        setState(() => _status = 'Não consegui ativar a BETA. $error');
      }
    }
  }

  Future<void> _prepare() async {
    if (!widget.canNavigate()) {
      await _say(
          'Conclua ou feche a edição aberta antes de conferir as horas.');
      return;
    }
    final turn = _turn;
    setState(() {
      _working = true;
      _phase = 'loading';
      _logs = [];
      _offered = false;
    });
    _audio.stop();
    widget.openTasks();
    try {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final logs = await widget.loadDay(day);
      if (!_current || turn != _turn) return;
      final valid = logs
          .where((l) => l.isRegistered && DateUtils.isSameDay(l.date, day))
          .toList();
      if (valid.isEmpty) {
        setState(() => _phase = 'ready');
        await _say('Não encontrei apontamentos registrados hoje para enviar.');
        return;
      }
      _day = day;
      _logs = valid;
      _snapshot = betaHoursFingerprint(valid);
      setState(() => _phase = 'choose');
      await _say(
          'Encontrei ${valid.length} apontamentos. Você prefere que eu leia as horas ou vai fazer a conferência visual na tela?');
    } catch (_) {
      if (_current && turn == _turn) {
        setState(() => _phase = 'ready');
        await _say(
            'Não consegui carregar todas as horas de hoje. Nenhum envio foi feito. Tente novamente.');
      }
    } finally {
      if (_current && turn == _turn) {
        setState(() => _working = false);
        _resume();
      }
    }
  }

  Future<void> _review(bool read) async {
    setState(() => _phase = 'review');
    if (!read) {
      await _say(
          'Confira os apontamentos na tela. Quando terminar, diga: pode enviar.');
      return;
    }
    final turn = _turn;
    setState(() => _working = true);
    try {
      for (final log in _logs) {
        if (!_current || turn != _turn) return;
        await _say(
            '${log.projectName ?? log.targetId}. ${log.taskName ?? ''}. Das ${log.startTime} às ${log.endTime}. ${spokenHours(dayHoursMinutes(log))}. ${log.description ?? ''}');
      }
      if (_current && turn == _turn) {
        await _say(
            'Total de ${spokenHours(_logs.fold(0, (sum, l) => sum + dayHoursMinutes(l)))}. Para autorizar o envio, diga: pode enviar.');
      }
    } finally {
      if (_current && turn == _turn) {
        setState(() => _working = false);
        _resume();
      }
    }
  }

  Future<void> _send() async {
    if (_phase != 'review' || _logs.isEmpty || _day == null) return;
    final turn = _turn;
    setState(() {
      _working = true;
      _phase = 'sending';
      _status = 'Verificando apontamentos antes do envio…';
    });
    _audio.stop();
    try {
      final fresh = await widget.loadDay(_day!);
      if (!_current || turn != _turn) return;
      if (!DateUtils.isSameDay(_day, DateTime.now()) ||
          betaHoursFingerprint(fresh) != _snapshot) {
        setState(() {
          _phase = 'ready';
          _logs = [];
        });
        await _say(
            'Os apontamentos ou a data mudaram. Vamos conferir novamente antes de enviar.');
        return;
      }
      final result = await widget.send(_logs);
      if (!_current || turn != _turn) return;
      setState(() => _phase = 'ready');
      _logs = [];
      await _say(result ?? 'O envio foi cancelado.');
      if (_current && turn == _turn) {
        await _say('Qualquer coisa, é só me chamar.');
        if (_current && turn == _turn) setState(() => _phase = 'asleep');
      }
    } catch (_) {
      if (_current && turn == _turn) {
        setState(() => _phase = 'ready');
        _logs = [];
        await _say(
            'Não consegui confirmar o envio completo. Confira o resultado do E-Desk na tela antes de tentar novamente.');
        if (_current && turn == _turn) {
          await _say('Qualquer coisa, é só me chamar.');
          if (_current && turn == _turn) setState(() => _phase = 'asleep');
        }
      }
    } finally {
      if (_current && turn == _turn) {
        setState(() => _working = false);
        _resume();
      }
    }
  }

  Future<void> _command(String raw) async {
    if (!_current || _working || _speaking) return;
    final text = betaNormalize(raw);
    if (betaWake(text)) {
      setState(() {
        _phase = 'ready';
        _logs = [];
        _offered = false;
      });
      final hour = DateTime.now().hour;
      await _say(
          '${hour < 12 ? 'Bom dia' : hour < 18 ? 'Boa tarde' : 'Boa noite'}, Rodrigo. O que vamos fazer?');
      return;
    }
    if (_phase == 'asleep') {
      _resume();
      return;
    }
    if (['fechar beta', 'cancelar', 'cancelar envio'].contains(text)) {
      if (text == 'fechar beta') {
        final turn = _turn;
        await _say('Qualquer coisa, é só me chamar.');
        if (!_current || turn != _turn) return;
      }
      _turn++;
      _audio.stop();
      setState(() {
        _phase = text == 'fechar beta' ? 'asleep' : 'ready';
        _logs = [];
        _offered = false;
      });
      _resume();
      return;
    }
    if (text == 'enviar horas do dia' ||
        text == 'enviar as horas do dia' ||
        text == 'enviar horas de hoje' ||
        text == 'enviar minhas horas de hoje' ||
        (_phase == 'ready' &&
            _offered &&
            ['sim', 'pode conferir', 'quero'].contains(text))) {
      await _prepare();
      return;
    }
    if (['choose', 'review'].contains(_phase)) {
      if ([
        'pode ler',
        'leia',
        'ler as horas',
        'leia as horas',
        'por voz',
        'leitura por voz'
      ].contains(text)) {
        await _review(true);
        return;
      }
      if ([
        'conferencia visual',
        'conferir na tela',
        'vou conferir na tela',
        'na tela',
        'visual'
      ].contains(text)) {
        await _review(false);
        return;
      }
      if (_phase == 'review' &&
          ['pode enviar', 'confirmar envio'].contains(text)) {
        await _send();
        return;
      }
      await _say(_phase == 'choose'
          ? 'Quer que eu leia ou prefere conferir na tela?'
          : 'Para confirmar o envio, diga: pode enviar. Ou diga cancelar.');
      return;
    }
    _offered = true;
    await _say(
        'Por enquanto, posso ajudar com as horas de hoje. Quer que eu confira os apontamentos?');
  }

  void _stopReading() {
    _turn++;
    _audio.stop();
    setState(() {
      _working = false;
      _speaking = false;
      _status = 'Confira os registros na tela.';
    });
    _resume();
  }

  @override
  Widget build(BuildContext context) {
    // The assistant has no visible panel before the wake word.
    if (_phase == 'asleep') return widget.child;
    final width = MediaQuery.sizeOf(context).width;
    return Stack(children: [
      widget.child,
      Positioned(
          right: 20,
          bottom: 16,
          child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: width < 440 ? width - 40 : 360,
                  maxHeight: MediaQuery.sizeOf(context).height * .82),
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                    Material(
                        color: const Color(0xff102438),
                        elevation: 8,
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: Colors.cyan.withValues(alpha: .3)),
                                borderRadius: BorderRadius.circular(18)),
                            child: DefaultTextStyle(
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    height: 1.5),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Container(
                                            width: 7,
                                            height: 7,
                                            decoration: const BoxDecoration(
                                                color: Colors.cyanAccent,
                                                shape: BoxShape.circle)),
                                        const SizedBox(width: 8),
                                        const Text('BETA',
                                            style: TextStyle(
                                                fontSize: 13,
                                                letterSpacing: 2,
                                                fontWeight: FontWeight.w600)),
                                        const Spacer(),
                                        IconButton(
                                            tooltip: 'Recolher BETA',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: _working || _speaking
                                                ? null
                                                : () => _command('fechar beta'),
                                            icon: const Icon(Icons.remove,
                                                color: Colors.white70,
                                                size: 18))
                                      ]),
                                      Text(_message),
                                      const SizedBox(height: 8),
                                      Text(_status,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.cyanAccent)),
                                      if (_logs.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Text(
                                            '${_logs.length} apontamentos · ${spokenHours(_logs.fold(0, (sum, l) => sum + dayHoursMinutes(l)))}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        SizedBox(
                                            height: 150,
                                            child: ListView(children: [
                                              for (final log in _logs)
                                                Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(vertical: 6),
                                                    child: Text(
                                                        '${log.projectName ?? log.targetId} · ${log.taskName ?? ''}\n${log.startTime}–${log.endTime} · ${log.description ?? ''}'))
                                            ]))
                                      ],
                                      if (!_working && !_speaking) ...[
                                        Wrap(spacing: 8, children: [
                                          if (_phase == 'choose') ...[
                                            TextButton(
                                                onPressed: () =>
                                                    _command('pode ler'),
                                                child:
                                                    const Text('Ler por voz')),
                                            TextButton(
                                                onPressed: () => _command(
                                                    'conferir na tela'),
                                                child: const Text(
                                                    'Conferir na tela'))
                                          ],
                                          if (_phase == 'review')
                                            FilledButton(
                                                onPressed: () =>
                                                    _command('pode enviar'),
                                                child:
                                                    const Text('Pode enviar')),
                                          if (_phase == 'ready')
                                            TextButton(
                                                onPressed: () => _command(
                                                    'enviar horas do dia'),
                                                child: const Text(
                                                    'Enviar horas do dia'))
                                        ]),
                                        TextField(
                                            controller: _input,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12),
                                            decoration: const InputDecoration(
                                                hintText:
                                                    'Ou digite sua resposta…',
                                                hintStyle: TextStyle(
                                                    color: Colors.white54)),
                                            onSubmitted: (value) {
                                              _input.clear();
                                              unawaited(_command(value));
                                            })
                                      ],
                                      if (_speaking && _phase != 'sending')
                                        TextButton(
                                            onPressed: _stopReading,
                                            child: const Text('Parar voz')),
                                    ])))),
                    const SizedBox(height: 4),
                    IgnorePointer(
                        child: SizedBox(
                            width: 180,
                            height: 150,
                            child: FittedBox(
                                child: BetaHologram(speaking: _speaking)))),
                  ]))))
    ]);
  }
}
