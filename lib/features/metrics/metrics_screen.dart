import 'package:gerenciador_horas/domain/models/work_duration.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';
import 'package:gerenciador_horas/domain/models/monthly_hours.dart';

class MetricsScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  final TimeLogStore timeLogStore;
  final String userName;

  const MetricsScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required this.timeLogStore,
    required this.userName,
  });

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends State<MetricsScreen> {
  // ================================================================
  // CONFIGURAÇÕES
  // ================================================================

  static final int _ano = DateTime.now().year;
  Timer? _jornadaDebounce;

  final List<String> _meses = const [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  // ================================================================
  // CONTROLLERS
  // ================================================================

  late TextEditingController _horasDiaController;
  late TextEditingController _dataInicioController;

  late List<int> _diasUteisCalculados;

  late List<TextEditingController> _metaControllers;
  late List<TextEditingController> _cobradasControllers;
  late List<TextEditingController> _investimentoControllers;
  late List<TextEditingController> _naoCobradasControllers;
  late List<TextEditingController> _internasControllers;
  late List<TextEditingController> _outrasControllers;
  late List<TextEditingController> _naoInformadasControllers;

  bool _isLoadingFirebase = true;

  // ================================================================
  // CORES DO GRÁFICO
  // ================================================================

  Color _metaColor = CoresApp.secundaria;

  Color _cadastradasColor = CoresDashboard.graficoHoras;

  Color _cobradasColor = CoresDashboard.graficoProjetos;
  Color _demaisColor = CoresDashboard.graficoAndamento;

  final List<Color> _paletaCores = [
    CoresApp.primaria,
    CoresApp.secundaria,
    CoresApp.sucesso,
    CoresApp.aviso,
    CoresApp.erro,
    CoresDashboard.graficoHoras,
    CoresDashboard.graficoProjetos,
    CoresDashboard.graficoConcluidos,
    CoresDashboard.graficoAtrasados,
    CoresDashboard.graficoAndamento,
    CoresApp.destaqueAmarelo,
    CoresApp.destaqueVerde,
  ];

  // ================================================================
  // FIREBASE
  // ================================================================

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? get _preferenciasRef {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      return null;
    }

    return _firestore
        .collection('users')
        .doc(userId)
        .collection('metrics_preferences')
        .doc('config');
  }

  // ================================================================
  // INIT
  // ================================================================

  @override
  void initState() {
    super.initState();

    _dataInicioController = TextEditingController(
      text: '01/01/$_ano',
    );

    _horasDiaController = TextEditingController(
      text: '08:20',
    );

    _diasUteisCalculados = List.generate(12, (_) => 0);

    _recalcularDiasUteis();

    final metasIniciais = List.generate(
        12, (i) => '${_ano == 2026 ? MonthlyHours.defaultGoals[i] : 0}:00');

    _metaControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: metasIniciais[i],
      ),
    );

    _cobradasControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: _calcularHorasPorTipo(
          i + 1,
          'Hs Cobradas',
        ),
      ),
    );

    _investimentoControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: _calcularHorasPorTipo(
          i + 1,
          'Hs Investimento',
        ),
      ),
    );

    _naoCobradasControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: _calcularHorasPorTipo(
          i + 1,
          'Hs Não cobradas',
        ),
      ),
    );

    _internasControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: _calcularHorasPorTipo(
          i + 1,
          'Hs Internas',
        ),
      ),
    );

    _outrasControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: _calcularHorasPorTipo(
          i + 1,
          'Outras',
        ),
      ),
    );

    _naoInformadasControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: _calcularHorasPorTipo(
          i + 1,
          'Hs Não Informadas',
        ),
      ),
    );

    widget.timeLogStore.addListener(
      _atualizarValoresComLogs,
    );

    _horasDiaController.addListener(_salvarJornada);
    _carregarMetasDoFirebase();
  }

  // ================================================================
  // FIREBASE - CARREGAR
  // ================================================================

  Future<void> _carregarMetasDoFirebase() async {
    try {
      final resultados = await Future.wait([
        widget.timeLogStore.carregarMetasAnuais(_ano),
        _carregarCoresDoFirebase(),
      ]);

      final metasMap = resultados[0] as Map<String, dynamic>?;

      if (metasMap != null && mounted) {
        setState(() {
          for (int i = 0; i < 12; i++) {
            final mesKey = (i + 1).toString();

            final valorSalvo = metasMap[mesKey]?.toString();

            if (valorSalvo != null && valorSalvo.isNotEmpty) {
              _metaControllers[i].text = valorSalvo;
            }
          }
        });
      }
    } catch (e) {
      debugPrint(
        'Erro ao carregar preferências das métricas: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFirebase = false;
        });
      }
    }
  }

  Future<void> _carregarCoresDoFirebase() async {
    try {
      final ref = _preferenciasRef;

      if (ref == null) {
        return;
      }

      final snapshot = await ref.get();

      if (!snapshot.exists) {
        return;
      }

      final data = snapshot.data();

      if (data == null || !mounted) {
        return;
      }

      setState(() {
        if (data['horasDia'] is String)
          _horasDiaController.text = data['horasDia'];
        if (data['metaColor'] is int) {
          _metaColor = Color(data['metaColor']);
        }

        if (data['cadastradasColor'] is int) {
          _cadastradasColor = Color(data['cadastradasColor']);
        }

        if (data['cobradasColor'] is int) {
          _cobradasColor = Color(data['cobradasColor']);
        }

        if (data['demaisColor'] is int) {
          _demaisColor = Color(data['demaisColor']);
        }
      });
    } catch (e) {
      debugPrint(
        'Erro ao carregar cores das métricas: $e',
      );
    }
  }

  void _salvarJornada() {
    if (_isLoadingFirebase) return;
    _jornadaDebounce?.cancel();
    final value = _horasDiaController.text.trim();
    final valid = RegExp(r'^\d{1,3}:[0-5]\d$').hasMatch(value);
    if (!valid) return;
    final ref = _preferenciasRef;
    if (ref == null) return;
    _jornadaDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        await ref.set({'horasDia': value}, SetOptions(merge: true));
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Não foi possível salvar a jornada. Tente novamente.')));
      }
    });
  }

  Future<void> _salvarCoresNoFirebase() async {
    try {
      final ref = _preferenciasRef;

      if (ref == null) {
        return;
      }

      await ref.set(
        {
          'metaColor': _metaColor.toARGB32(),
          'cadastradasColor': _cadastradasColor.toARGB32(),
          'cobradasColor': _cobradasColor.toARGB32(),
          'demaisColor': _demaisColor.toARGB32(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint(
        'Erro ao salvar cores das métricas: $e',
      );
    }
  }

  // ================================================================
  // CORES - MODAL
  // ================================================================

  void _abrirModalPersonalizacao() {
    Color tempMetaColor = _metaColor;
    Color tempCobradasColor = _cobradasColor;
    Color tempDemaisColor = _demaisColor;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return StatefulBuilder(
          builder: (
            context,
            setModalState,
          ) {
            AppAppearance.watch(context);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: Container(
                width: 430,
                constraints: const BoxConstraints(
                  maxWidth: 430,
                ),
                decoration: BoxDecoration(
                  color: CoresDashboard.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: AppPalette.text.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 35,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        20,
                        18,
                        12,
                        15,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: CoresApp.destaque.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.palette_rounded,
                              color: CoresApp.destaque,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Personalizar gráfico',
                                  style: TextStyle(
                                    color: CoresApp.textoPrincipal,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Escolha as cores dos indicadores.',
                                  style: TextStyle(
                                    color: CoresApp.textoSecundario,
                                    fontSize: 8.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Fechar',
                            onPressed: () => Navigator.of(
                              dialogContext,
                            ).pop(),
                            icon: Icon(
                              Icons.close_rounded,
                              color: CoresApp.textoSecundario,
                              size: 19,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: AppPalette.text.withValues(alpha: 0.06),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        20,
                        17,
                        20,
                        8,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppPalette.text.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Row(
                          children: [
                            _buildPreviewBar(
                              'Meta',
                              tempMetaColor,
                            ),
                            _buildPreviewBar(
                              'Cobradas',
                              tempCobradasColor,
                            ),
                            _buildPreviewBar(
                              'Demais',
                              tempDemaisColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        20,
                        8,
                        20,
                        12,
                      ),
                      child: Column(
                        children: [
                          _buildModalColorRow(
                            label: 'Meta',
                            description: 'Objetivo mensal',
                            icon: Icons.track_changes_rounded,
                            color: tempMetaColor,
                            setColor: (color) {
                              setModalState(() {
                                tempMetaColor = color;
                              });
                            },
                          ),
                          const SizedBox(height: 9),
                          _buildModalColorRow(
                            label: 'Cobradas',
                            description: 'Horas cobradas',
                            icon: Icons.business_center_rounded,
                            color: tempCobradasColor,
                            setColor: (color) {
                              setModalState(() {
                                tempCobradasColor = color;
                              });
                            },
                          ),
                          const SizedBox(height: 9),
                          _buildModalColorRow(
                            label: 'Demais',
                            description: 'Horas restantes',
                            icon: Icons.more_time_rounded,
                            color: tempDemaisColor,
                            setColor: (color) {
                              setModalState(() {
                                tempDemaisColor = color;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: AppPalette.text.withValues(alpha: 0.06),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              setModalState(() {
                                tempMetaColor = CoresApp.secundaria;
                                tempCobradasColor =
                                    CoresDashboard.graficoProjetos;
                                tempDemaisColor =
                                    CoresDashboard.graficoAndamento;
                              });
                            },
                            icon: const Icon(
                              Icons.restart_alt_rounded,
                              size: 15,
                            ),
                            label: const Text(
                              'Restaurar padrão',
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: CoresApp.textoSecundario,
                              textStyle: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.of(
                              dialogContext,
                            ).pop(),
                            child: const Text(
                              'Cancelar',
                            ),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton.icon(
                            onPressed: () async {
                              setState(() {
                                _metaColor = tempMetaColor;
                                _cobradasColor = tempCobradasColor;
                                _demaisColor = tempDemaisColor;
                              });

                              await _salvarCoresNoFirebase();

                              if (dialogContext.mounted) {
                                Navigator.of(
                                  dialogContext,
                                ).pop();
                              }
                            },
                            icon: const Icon(
                              Icons.check_rounded,
                              size: 15,
                            ),
                            label: const Text(
                              'Aplicar',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CoresApp.destaque,
                              foregroundColor: AppPalette.onPrimary,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 17,
                                vertical: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPreviewBar(
    String label,
    Color color,
  ) {
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 38,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color,
                  color.withValues(alpha: 0.48),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: CoresApp.textoSecundario,
              fontSize: 7,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalColorRow({
    required String label,
    required String description,
    required IconData icon,
    required Color color,
    required ValueChanged<Color> setColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: AppPalette.text.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppPalette.text.withValues(alpha: 0.055),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              color: color,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                    fontSize: 7.5,
                  ),
                ),
              ],
            ),
          ),
          _buildModalPalette(
            color,
            setColor,
          ),
        ],
      ),
    );
  }

  Widget _buildModalPalette(
    Color currentColor,
    ValueChanged<Color> onSelected,
  ) {
    return SizedBox(
      width: 170,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 5,
        runSpacing: 5,
        children: _paletaCores.map((color) {
          final selected = color.toARGB32() == currentColor.toARGB32();

          return GestureDetector(
            onTap: () => onSelected(color),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              width: selected ? 19 : 16,
              height: selected ? 19 : 16,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(
                        color: Colors.white,
                        width: 1.5,
                      )
                    : Border.all(
                        color: AppPalette.text.withValues(alpha: 0.08),
                      ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.45),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
              child: selected
                  ? Icon(
                      Icons.check_rounded,
                      color: AppPalette.text,
                      size: 11,
                    )
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  // ================================================================
  // ATUALIZAÇÃO DOS LOGS
  // ================================================================

  void _atualizarValoresComLogs() {
    if (!mounted) return;

    setState(() {
      for (int i = 1; i <= 12; i++) {
        _cobradasControllers[i - 1].text = _calcularHorasPorTipo(
          i,
          'Hs Cobradas',
        );

        _investimentoControllers[i - 1].text = _calcularHorasPorTipo(
          i,
          'Hs Investimento',
        );

        _naoCobradasControllers[i - 1].text = _calcularHorasPorTipo(
          i,
          'Hs Não cobradas',
        );

        _internasControllers[i - 1].text = _calcularHorasPorTipo(
          i,
          'Hs Internas',
        );

        _outrasControllers[i - 1].text = _calcularHorasPorTipo(
          i,
          'Outras',
        );

        _naoInformadasControllers[i - 1].text = _calcularHorasPorTipo(
          i,
          'Hs Não Informadas',
        );
      }
    });
  }

  // ================================================================
  // CÁLCULOS
  // ================================================================

  double _calcularHorasCadastradasDouble(
    int mes,
  ) {
    double totalHoras = 0.0;

    for (final log in widget.timeLogStore.logs) {
      if (log.date.month == mes && log.date.year == _ano) {
        totalHoras += WorkDuration.minutes(log) / 60;
      }
    }

    return totalHoras;
  }

  String _calcularHorasCadastradas(
    int mes,
  ) {
    return _formatDoubleToTime(
      _calcularHorasCadastradasDouble(
        mes,
      ),
    );
  }

  String _calcularHorasPorTipo(
    int mes,
    String tipoHs,
  ) {
    double totalHoras = 0.0;

    for (final log in widget.timeLogStore.logs) {
      if (log.date.month != mes || log.date.year != _ano) {
        continue;
      }

      String? rawType;

      try {
        rawType = (log as dynamic).hourType ??
            (log as dynamic).typeHs ??
            (log as dynamic).type ??
            (log as dynamic).tipo ??
            (log as dynamic).category;
      } catch (_) {
        rawType = log.typeHs;
      }

      final logType = (rawType ?? '').trim().toLowerCase();

      final targetType = tipoHs.trim().toLowerCase();

      bool match = false;

      String normalize(String s) {
        return s
            .toLowerCase()
            .replaceAll('horas', 'h')
            .replaceAll('hs', 'h')
            .replaceAll('á', 'a')
            .replaceAll('ã', 'a')
            .replaceAll('é', 'e')
            .replaceAll('í', 'i')
            .replaceAll('ó', 'o')
            .replaceAll('ú', 'u')
            .replaceAll('ç', 'c')
            .replaceAll(
              RegExp(r'[^a-z0-9]'),
              '',
            );
      }

      final normLog = normalize(logType);
      final normTarget = normalize(targetType);

      if (normLog.isEmpty) {
        if (normTarget.contains('informadas')) {
          match = true;
        }
      } else {
        if (normTarget.contains('cobradas') && !normTarget.contains('nao')) {
          if (normLog.contains('cobradas') && !normLog.contains('nao')) {
            match = true;
          }
        } else if (normTarget.contains('naocobradas')) {
          if (normLog.contains('naocobradas') ||
              normLog.contains('naocobrada')) {
            match = true;
          }
        } else if (normTarget.contains('investimento')) {
          if (normLog.contains('investimento')) {
            match = true;
          }
        } else if (normTarget.contains('internas')) {
          if (normLog.contains('internas') || normLog.contains('interna')) {
            match = true;
          }
        } else if (normTarget.contains('outras')) {
          if (normLog.contains('outras') || normLog.contains('outra')) {
            match = true;
          }
        } else if (normTarget.contains('informadas')) {
          if (normLog.contains('informadas') ||
              normLog.contains('desconhecido')) {
            match = true;
          }
        }
      }

      if (match) {
        totalHoras += WorkDuration.minutes(log) / 60;
      }
    }

    return _formatDoubleToTime(
      totalHoras,
    );
  }

  void _recalcularDiasUteis() {
    int ano = _ano;

    try {
      final parts = _dataInicioController.text.split('/');

      if (parts.length == 3) {
        ano = int.parse(parts[2]);
      }
    } catch (_) {}

    for (int month = 1; month <= 12; month++) {
      _diasUteisCalculados[month - 1] = _calcularDiasUteis(
        ano,
        month,
      );
    }
  }

  int _calcularDiasUteis(
    int year,
    int month,
  ) {
    final totalDays = DateTime(
      year,
      month + 1,
      0,
    ).day;

    int count = 0;

    for (int day = 1; day <= totalDays; day++) {
      final date = DateTime(
        year,
        month,
        day,
      );

      if (date.weekday != DateTime.saturday &&
          date.weekday != DateTime.sunday) {
        count++;
      }
    }

    return count;
  }

  double _parseTimeToDouble(
    String timeStr,
  ) {
    try {
      final parts = timeStr.split(':');

      final hours = double.parse(parts[0]);

      final minutes = parts.length > 1 ? double.parse(parts[1]) / 60 : 0.0;

      return hours + minutes;
    } catch (_) {
      return 0.0;
    }
  }

  double _getCobradasSum(
    int index,
  ) {
    return _parseTimeToDouble(
      _cobradasControllers[index].text,
    );
  }

  double _getCadastradasSum(
    int index,
  ) {
    return _calcularHorasCadastradasDouble(
      index + 1,
    );
  }

  double _getDemaisSum(
    int index,
  ) {
    final cadastradas = _getCadastradasSum(index);

    final cobradas = _getCobradasSum(index);

    final demais = cadastradas - cobradas;

    return demais < 0 ? 0.0 : demais;
  }

  double _getRealizadoSum(
    int index,
  ) {
    return _parseTimeToDouble(
          _cobradasControllers[index].text,
        ) +
        _parseTimeToDouble(
          _investimentoControllers[index].text,
        ) +
        _parseTimeToDouble(
          _naoCobradasControllers[index].text,
        ) +
        _parseTimeToDouble(
          _internasControllers[index].text,
        ) +
        _parseTimeToDouble(
          _outrasControllers[index].text,
        ) +
        _parseTimeToDouble(
          _naoInformadasControllers[index].text,
        );
  }

  String _formatDoubleToTime(
    double value,
  ) {
    final totalMinutes = (value * 60).round();

    final hours = totalMinutes ~/ 60;

    final minutes = totalMinutes % 60;

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  // ================================================================
  // RESUMO ANUAL
  // ================================================================

  double _getMetaAnual() {
    double total = 0.0;

    for (final controller in _metaControllers) {
      total += _parseTimeToDouble(
        controller.text,
      );
    }

    return total;
  }

  double _getCadastradasAnual() {
    double total = 0.0;

    for (int i = 0; i < 12; i++) {
      total += _getCadastradasSum(i);
    }

    return total;
  }

  double _getCobradasAnual() {
    double total = 0.0;

    for (int i = 0; i < 12; i++) {
      total += _getCobradasSum(i);
    }

    return total;
  }

  double _getRealizadoAnual() {
    double total = 0.0;

    for (int i = 0; i < 12; i++) {
      total += _getRealizadoSum(i);
    }

    return total;
  }

  // ================================================================
  // EFICIÊNCIA ANUAL
  // ================================================================

  double _getEfficiency() {
    final meta = _getMetaAnual();
    final cobradas = _getCobradasAnual();

    if (meta <= 0) {
      return 0.0;
    }

    return (cobradas / meta) * 100;
  }

  String _getEfficiencyText() {
    final percentual = _getEfficiency();

    return '${percentual.toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  // ================================================================
  // EFICIÊNCIA - CÁLCULOS DOS PERÍODOS
  // ================================================================

  double _getEfficiencyForMonths(
    int startMonth,
    int endMonth,
  ) {
    double meta = 0.0;
    double cobradas = 0.0;

    for (int mes = startMonth; mes <= endMonth; mes++) {
      final index = mes - 1;

      meta += _parseTimeToDouble(
        _metaControllers[index].text,
      );

      cobradas += _getCobradasSum(index);
    }

    if (meta <= 0) {
      return 0.0;
    }

    return (cobradas / meta) * 100;
  }

  double _getCobradasForMonths(
    int startMonth,
    int endMonth,
  ) {
    double total = 0.0;

    for (int mes = startMonth; mes <= endMonth; mes++) {
      total += _getCobradasSum(mes - 1);
    }

    return total;
  }

  double _getRealizadoForMonths(
    int startMonth,
    int endMonth,
  ) {
    double total = 0.0;

    for (int mes = startMonth; mes <= endMonth; mes++) {
      total += _getRealizadoSum(mes - 1);
    }

    return total;
  }

  String _formatPercentage(
    double value,
  ) {
    return '${value.toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  // ================================================================
  // MODAL DE EFICIÊNCIA
  // ================================================================

  void _abrirModalEficiencia() {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        final size = MediaQuery.of(dialogContext).size;

        final modalWidth = size.width > 980 ? 900.0 : size.width * 0.94;

        final modalHeight = size.height > 820 ? 700.0 : size.height * 0.88;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          child: Container(
            width: modalWidth,
            height: modalHeight,
            decoration: BoxDecoration(
              color: CoresDashboard.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppPalette.text.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  _buildEfficiencyModalHeader(
                    dialogContext,
                  ),
                  _buildEfficiencyTabs(),
                  Divider(
                    height: 1,
                    color: AppPalette.text.withValues(alpha: 0.06),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _EfficiencyMonthlyTab(
                          state: this,
                        ),
                        _EfficiencyQuarterlyTab(
                          state: this,
                        ),
                        _EfficiencySemiannualTab(
                          state: this,
                        ),
                        _EfficiencyAnnualTab(
                          state: this,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEfficiencyModalHeader(
    BuildContext dialogContext,
  ) {
    final eficiencia = _getEfficiency();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        22,
        20,
        14,
        17,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _demaisColor,
                  _demaisColor.withValues(alpha: 0.52),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _demaisColor.withValues(alpha: 0.22),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              Icons.speed_rounded,
              color: AppPalette.text,
              size: 25,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Análise de eficiência',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Horas cobradas em relação à meta.',
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: _demaisColor.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: _demaisColor.withValues(alpha: 0.15),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$_ano',
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                    fontSize: 6.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatPercentage(eficiencia),
                  style: TextStyle(
                    color: _demaisColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Fechar',
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            icon: Icon(
              Icons.close_rounded,
              color: CoresApp.textoSecundario,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEfficiencyTabs() {
    return Container(
      height: 47,
      margin: const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppPalette.text.withValues(alpha: 0.045),
        ),
      ),
      child: TabBar(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: CoresApp.destaque,
        unselectedLabelColor: CoresApp.textoSecundario,
        labelStyle: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
        ),
        indicator: BoxDecoration(
          color: Color(0x1419C37D),
          borderRadius: BorderRadius.all(
            Radius.circular(10),
          ),
        ),
        tabs: [
          Tab(
            icon: Icon(
              Icons.calendar_month_rounded,
              size: 16,
            ),
            text: 'Mensal',
          ),
          Tab(
            icon: Icon(
              Icons.view_week_rounded,
              size: 16,
            ),
            text: 'Trimestral',
          ),
          Tab(
            icon: Icon(
              Icons.date_range_rounded,
              size: 16,
            ),
            text: 'Semestral',
          ),
          Tab(
            icon: Icon(
              Icons.auto_graph_rounded,
              size: 16,
            ),
            text: 'Anual',
          ),
        ],
      ),
    );
  }

  Widget _buildEfficiencyContent(
    List<_EfficiencyPeriodData> periods,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        20,
        18,
        20,
        22,
      ),
      children: [
        LayoutBuilder(
          builder: (
            context,
            constraints,
          ) {
            AppAppearance.watch(context);

            final compact = constraints.maxWidth < 650;

            return compact
                ? Column(
                    children: [
                      for (int i = 0; i < periods.length; i++) ...[
                        _buildEfficiencyPeriodCard(
                          periods[i],
                        ),
                        if (i < periods.length - 1) const SizedBox(height: 9),
                      ],
                    ],
                  )
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: periods.map(
                      (period) {
                        return SizedBox(
                          width: (constraints.maxWidth - 10) / 2,
                          child: _buildEfficiencyPeriodCard(
                            period,
                          ),
                        );
                      },
                    ).toList(),
                  );
          },
        ),
      ],
    );
  }

  Widget _buildEfficiencyPeriodCard(
    _EfficiencyPeriodData period,
  ) {
    final percentual = period.efficiency.clamp(
      0.0,
      100.0,
    );

    final progress = percentual / 100;

    final color = _getEfficiencyColor(
      period.efficiency,
    );

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppPalette.text.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  period.icon,
                  color: color,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      period.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      period.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 7.5,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatPercentage(period.efficiency),
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: AppPalette.text.withValues(alpha: 0.055),
              valueColor: AlwaysStoppedAnimation<Color>(
                color,
              ),
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: _buildEfficiencyInfo(
                  label: 'COBRADAS',
                  value: _formatDoubleToTime(
                    period.cobradas,
                  ),
                  color: _cobradasColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildEfficiencyInfo(
                  label: 'REALIZADO',
                  value: _formatDoubleToTime(
                    period.realizado,
                  ),
                  color: _cadastradasColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEfficiencyInfo({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: CoresApp.textoSecundario,
              fontSize: 5.8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.45,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Color _getEfficiencyColor(
    double efficiency,
  ) {
    if (efficiency >= 80) {
      return CoresApp.sucesso;
    }

    if (efficiency >= 60) {
      return CoresApp.aviso;
    }

    return CoresApp.erro;
  }

  // ================================================================
  // DECORAÇÃO
  // ================================================================

  BoxDecoration _cardDecoration({
    Color? color,
    double radius = 18,
  }) {
    return BoxDecoration(
      color: color ?? CoresDashboard.card.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: CoresApp.textoPrincipal.withValues(alpha: 0.065),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.14),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  // ================================================================
  // KPI
  // ================================================================

  Widget _buildKpiItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    final child = Container(
      constraints: const BoxConstraints(
        minHeight: 70,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CoresApp.textoSecundario,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.65,
                        ),
                      ),
                    ),
                    if (onTap != null)
                      Icon(
                        Icons.open_in_new_rounded,
                        color: color.withValues(alpha: 0.65),
                        size: 10,
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return child;
    }

    return Tooltip(
      message: 'Clique para ver a análise de eficiência',
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: child,
        ),
      ),
    );
  }

  // ================================================================
  // CABEÇALHO
  // ================================================================

  Widget _buildPageHeader() {
    final meta = _getMetaAnual();
    final realizado = _getRealizadoAnual();
    final cobradas = _getCobradasAnual();

    final kpis = [
      _buildKpiItem(
        icon: Icons.track_changes_rounded,
        label: 'META ANUAL',
        value: _formatDoubleToTime(meta),
        color: _metaColor,
      ),
      _buildKpiItem(
        icon: Icons.timer_rounded,
        label: 'REALIZADO',
        value: _formatDoubleToTime(realizado),
        color: _cadastradasColor,
      ),
      _buildKpiItem(
        icon: Icons.business_center_rounded,
        label: 'COBRADO',
        value: _formatDoubleToTime(cobradas),
        color: _cobradasColor,
      ),
      _buildKpiItem(
        icon: Icons.speed_rounded,
        label: 'EFICIÊNCIA',
        value: _getEfficiencyText(),
        color: _demaisColor,
        onTap: _abrirModalEficiencia,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          AppAppearance.watch(context);

          final compact = constraints.maxWidth < 1050;

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTitleArea(),
                const SizedBox(height: 15),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kpis
                      .map(
                        (item) => SizedBox(
                          width: 190,
                          child: item,
                        ),
                      )
                      .toList(),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                flex: 4,
                child: _buildTitleArea(),
              ),
              const SizedBox(width: 22),
              Expanded(
                flex: 7,
                child: Row(
                  children: [
                    for (int i = 0; i < kpis.length; i++) ...[
                      if (i > 0) const SizedBox(width: 7),
                      Expanded(
                        child: kpis[i],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTitleArea() {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                CoresApp.destaque,
                CoresApp.destaque.withValues(alpha: 0.55),
              ],
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: CoresApp.destaque.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            Icons.analytics_rounded,
            color: AppPalette.text,
            size: 27,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Métricas de desempenho',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.45,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: CoresApp.destaque.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$_ano',
                      style: TextStyle(
                        color: CoresApp.destaque,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'Visão geral da produtividade, metas e distribuição das horas.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 9.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================================================================
  // JORNADA
  // ================================================================

  Widget _buildJornadaConfigCard() {
    final totalDias = _diasUteisCalculados.fold<int>(
      0,
      (sum, val) => sum + val,
    );

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _cardDecoration(radius: 15),
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          AppAppearance.watch(context);

          final compact = constraints.maxWidth < 800;

          final campos = [
            SizedBox(
              width: 145,
              child: _buildModernInput(
                controller: _dataInicioController,
                label: 'Data inicial',
                icon: Icons.event_rounded,
                onChanged: (_) {
                  _recalcularDiasUteis();
                  setState(() {});
                },
              ),
            ),
            SizedBox(
              width: 135,
              child: _buildModernInput(
                controller: _horasDiaController,
                label: 'Horas / dia',
                icon: Icons.schedule_rounded,
              ),
            ),
            _buildInfoBadge(
              icon: Icons.work_history_rounded,
              label: 'DIAS ÚTEIS',
              value: '$totalDias',
              color: CoresApp.sucesso,
            ),
          ];

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitleSmall(
                  icon: Icons.settings_rounded,
                  title: 'Configuração da jornada',
                  subtitle: 'Parâmetros utilizados nos cálculos anuais.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: campos,
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: _buildSectionTitleSmall(
                  icon: Icons.settings_rounded,
                  title: 'Configuração da jornada',
                  subtitle: 'Parâmetros utilizados nos cálculos anuais.',
                ),
              ),
              ...campos.map(
                (widget) => Padding(
                  padding: const EdgeInsets.only(left: 9),
                  child: widget,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitleSmall({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CoresApp.destaque.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            icon,
            color: CoresApp.destaque,
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 8.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBadge({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: color.withValues(alpha: 0.13),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 17,
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 6.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(
          color: CoresApp.textoPrincipal,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: CoresApp.textoSecundario,
            fontSize: 8,
          ),
          prefixIcon: Icon(
            icon,
            color: CoresApp.destaque,
            size: 15,
          ),
          filled: true,
          fillColor: CoresApp.textoPrincipal.withValues(alpha: 0.035),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 9,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: CoresApp.textoPrincipal.withValues(alpha: 0.07),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: CoresApp.textoPrincipal.withValues(alpha: 0.07),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: CoresApp.destaque,
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  // ================================================================
  // GRÁFICO PREMIUM
  // ================================================================

  Widget _buildChartCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.insights_rounded,
            title: 'Desempenho mensal',
            subtitle:
                'Compare as horas cobradas e demais horas com a meta mensal.',
            trailing: _buildCustomizeButton(),
          ),
          const SizedBox(height: 15),
          _buildLegend(),
          const SizedBox(height: 12),
          SizedBox(
            height: 350,
            child: _buildRobustChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildRobustChart() {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        AppAppearance.watch(context);

        final valores = <double>[];

        for (int i = 0; i < 12; i++) {
          valores.add(
            _parseTimeToDouble(
              _metaControllers[i].text,
            ),
          );

          valores.add(
            _getCobradasSum(i),
          );

          valores.add(
            _getDemaisSum(i),
          );
        }

        double maiorValor = valores.fold<double>(
          0.0,
          (max, value) => value > max ? value : max,
        );

        if (maiorValor < 50) {
          maiorValor = 50;
        }

        final maxValor = maiorValor * 1.18;

        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppPalette.text.withValues(alpha: 0.045),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _buildChartBackground(),
                ),
                Positioned.fill(
                  left: 48,
                  right: 10,
                  top: 14,
                  bottom: 43,
                  child: _buildChartGrid(maxValor),
                ),
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 48,
                        child: _buildYAxis(maxValor),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            right: 8,
                            top: 12,
                            bottom: 8,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: List.generate(
                              12,
                              (index) {
                                return Expanded(
                                  child: _buildProfessionalMonthColumn(
                                    index,
                                    maxValor,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 48,
                  right: 10,
                  bottom: 42,
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppPalette.text.withValues(alpha: 0.02),
                          AppPalette.text.withValues(alpha: 0.14),
                          AppPalette.text.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChartBackground() {
    return Stack(
      children: [
        Positioned(
          top: -80,
          right: -50,
          child: Container(
            width: 220,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  CoresApp.destaque.withValues(alpha: 0.075),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -100,
          left: -50,
          child: Container(
            width: 220,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _cobradasColor.withValues(alpha: 0.045),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChartGrid(
    double maxValor,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(
        5,
        (index) {
          return Row(
            children: [
              Expanded(
                child: Container(
                  height: 1,
                  color: AppPalette.text.withValues(
                    alpha: index == 4 ? 0.085 : 0.028,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildYAxis(
    double maxValor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        top: 14,
        bottom: 43,
        right: 8,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          5,
          (index) {
            final percentual = 1 - (index / 4);
            final valor = maxValor * percentual;

            return Text(
              _formatDoubleToTime(valor),
              style: TextStyle(
                color: CoresApp.textoSecundario.withValues(
                  alpha: index == 4 ? 0.85 : 0.60,
                ),
                fontSize: 6.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
              ),
            );
          },
        ),
      ),
    );
  }

  // ================================================================
  // COLUNA MENSAL
  // ================================================================

  Widget _buildProfessionalMonthColumn(
    int index,
    double maxValor,
  ) {
    final meta = _parseTimeToDouble(
      _metaControllers[index].text,
    );

    final realizado = _getCadastradasSum(index);
    final cobradas = _getCobradasSum(index);
    final demais = _getDemaisSum(index);

    final currentMonth =
        DateTime.now().year == _ano && DateTime.now().month == index + 1;

    final maxBarHeight = 238.0;

    double barHeight(
      double value,
    ) {
      if (value <= 0) {
        return 3;
      }

      final result = (value / maxValor) * maxBarHeight;

      return result.clamp(
        4.0,
        maxBarHeight,
      );
    }

    final percentualMensal = meta <= 0 ? 0.0 : (realizado / meta) * 100;

    // EFICIÊNCIA = HORAS COBRADAS ÷ META × 100
    final eficienciaMensal = meta <= 0 ? 0.0 : (cobradas / meta) * 100;

    final isBestMonth = _isBestMonth(index);

    return Tooltip(
      waitDuration: const Duration(milliseconds: 180),
      showDuration: const Duration(seconds: 4),
      preferBelow: false,
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppPalette.text.withValues(alpha: 0.09),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      textStyle: TextStyle(
        color: AppPalette.text,
        fontSize: 9,
        height: 1.45,
      ),
      message: '${_meses[index].toUpperCase()}\n'
          'Meta: ${_metaControllers[index].text}h\n'
          'Cobradas: ${_formatDoubleToTime(cobradas)}h\n'
          'Demais: ${_formatDoubleToTime(demais)}h\n'
          'Atingimento: ${percentualMensal.toStringAsFixed(1)}%\n'
          'Eficiência: ${eficienciaMensal.toStringAsFixed(1)}%',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(
          horizontal: 1,
          vertical: 3,
        ),
        padding: const EdgeInsets.only(
          top: 4,
          bottom: 2,
        ),
        decoration: BoxDecoration(
          color: currentMonth
              ? CoresApp.destaque.withValues(alpha: 0.045)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: currentMonth
              ? Border.all(
                  color: CoresApp.destaque.withValues(alpha: 0.13),
                )
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              height: 17,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isBestMonth)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        Icons.workspace_premium_rounded,
                        size: 8,
                        color: CoresApp.destaqueAmarelo,
                      ),
                    ),
                  if (currentMonth)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: CoresApp.destaque.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'ATUAL',
                        style: TextStyle(
                          color: CoresApp.destaque,
                          fontSize: 5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.25,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned.fill(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildProfessionalBar(
                          value: cobradas,
                          height: barHeight(cobradas),
                          color: _cobradasColor,
                          width: 18,
                          isMain: true,
                        ),
                        const SizedBox(width: 4),
                        _buildProfessionalBar(
                          value: demais,
                          height: barHeight(demais),
                          color: _demaisColor,
                          width: 11,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 3,
                    right: 3,
                    bottom: _calculateMetaLinePosition(
                      meta,
                      maxValor,
                      maxBarHeight,
                    ),
                    child: _buildMetaLine(meta),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: currentMonth
                    ? CoresApp.destaque.withValues(alpha: 0.13)
                    : AppPalette.text.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _meses[index].substring(0, 3).toUpperCase(),
                style: TextStyle(
                  color: currentMonth
                      ? CoresApp.destaque
                      : CoresApp.textoSecundario,
                  fontSize: 6.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _calculateMetaLinePosition(
    double meta,
    double maxValor,
    double maxBarHeight,
  ) {
    if (meta <= 0) {
      return 0;
    }

    final position = (meta / maxValor) * maxBarHeight;

    return position.clamp(
      2.0,
      maxBarHeight - 2,
    );
  }

  Widget _buildMetaLine(
    double meta,
  ) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _metaColor.withValues(alpha: 0.05),
                  _metaColor,
                  _metaColor.withValues(alpha: 0.05),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _metaColor.withValues(alpha: 0.35),
                  blurRadius: 5,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 2),
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: _metaColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _metaColor.withValues(alpha: 0.45),
                blurRadius: 5,
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isBestMonth(
    int index,
  ) {
    double maior = -1;
    int melhorIndex = -1;

    for (int i = 0; i < 12; i++) {
      final realizado = _getCadastradasSum(i);

      if (realizado > maior) {
        maior = realizado;
        melhorIndex = i;
      }
    }

    return melhorIndex == index && maior > 0;
  }

  Widget _buildProfessionalBar({
    required double value,
    required double height,
    required Color color,
    required double width,
    bool isMain = false,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: 0,
        end: height,
      ),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (
        context,
        animatedHeight,
        child,
      ) {
        AppAppearance.watch(context);

        return Container(
          width: width,
          height: animatedHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(
                  Colors.white,
                  color,
                  0.10,
                )!,
                color,
                color.withValues(alpha: 0.46),
              ],
              stops: const [
                0.0,
                0.18,
                1.0,
              ],
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(6),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(
                  alpha: isMain ? 0.30 : 0.16,
                ),
                blurRadius: isMain ? 10 : 7,
                spreadRadius: isMain ? 0.4 : 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        );
      },
    );
  }

  // ================================================================
  // LEGENDA
  // ================================================================

  Widget _buildLegend() {
    return Wrap(
      spacing: 18,
      runSpacing: 7,
      children: [
        _buildLegendItem(
          'Meta',
          _metaColor,
          isLine: true,
        ),
        _buildLegendItem(
          'Cobradas',
          _cobradasColor,
        ),
        _buildLegendItem(
          'Demais',
          _demaisColor,
        ),
      ],
    );
  }

  Widget _buildLegendItem(
    String label,
    Color color, {
    bool isLine = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLine)
          SizedBox(
            width: 12,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.30),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color,
                  color.withValues(alpha: 0.55),
                ],
              ),
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.20),
                  blurRadius: 5,
                ),
              ],
            ),
          ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: CoresApp.textoSecundario,
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildCustomizeButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _abrirModalPersonalizacao,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: CoresApp.destaque.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: CoresApp.destaque.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                color: CoresApp.destaque,
                size: 13,
              ),
              SizedBox(width: 5),
              Text(
                'PERSONALIZAR',
                style: TextStyle(
                  color: CoresApp.destaque,
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // SECTION HEADER
  // ================================================================

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CoresApp.destaque.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            icon,
            color: CoresApp.destaque,
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 8.5,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  // ================================================================
  // TABELA
  // ================================================================

  Widget _buildPlanningTable() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: _cardDecoration(
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTableHeader(),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1420,
                child: _buildTable(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CoresApp.destaque.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            Icons.table_chart_rounded,
            color: CoresApp.destaque,
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Planejamento anual',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Metas mensais e distribuição das horas ao longo de $_ano.',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 8.5,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: CoresApp.destaque.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_rounded,
                color: CoresApp.destaque,
                size: 12,
              ),
              SizedBox(width: 5),
              Text(
                'EDITÁVEL',
                style: TextStyle(
                  color: CoresApp.destaque,
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.1),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1),
        5: FlexColumnWidth(1),
        6: FlexColumnWidth(1),
        7: FlexColumnWidth(1),
        8: FlexColumnWidth(1),
        9: FlexColumnWidth(1),
        10: FlexColumnWidth(1),
        11: FlexColumnWidth(1),
        12: FlexColumnWidth(1),
        13: FlexColumnWidth(1),
      },
      border: TableBorder(
        horizontalInside: BorderSide(
          color: Colors.black.withValues(alpha: 0.07),
        ),
        verticalInside: BorderSide(
          color: Colors.black.withValues(alpha: 0.045),
        ),
      ),
      children: [
        _buildTableHeaderRow(),
        _buildTableSubHeaderRow(),
        _buildDiasUteisRow(),
        _buildMetaRow(),
        _buildRealizadoRow(),
        _buildHorasRow(
          'Hs Cobradas',
          _cobradasControllers,
        ),
        _buildHorasRow(
          'Hs Investimento',
          _investimentoControllers,
        ),
        _buildHorasRow(
          'Hs Não cobradas',
          _naoCobradasControllers,
        ),
        _buildHorasRow(
          'Hs Internas',
          _internasControllers,
        ),
        _buildHorasRow(
          'Outras',
          _outrasControllers,
        ),
        _buildHorasRow(
          'Hs Não Informadas',
          _naoInformadasControllers,
        ),
      ],
    );
  }

  TableRow _buildTableHeaderRow() {
    return TableRow(
      decoration: BoxDecoration(
        color: CoresDashboard.cabecalhoTabela,
      ),
      children: [
        _buildCellText(
          'Data Início / Jornada',
          isHeader: true,
          color: Colors.white,
          alignLeft: true,
        ),
        _buildCellInput(
          _horasDiaController,
          isHeader: true,
          bgColor: AppPalette.text.withValues(alpha: 0.12),
        ),
        ...List.generate(
          12,
          (i) => _buildCellText(
            _meses[i],
            isHeader: true,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  TableRow _buildTableSubHeaderRow() {
    return TableRow(
      decoration: BoxDecoration(
        color: CoresDashboard.cabecalhoTabela.withValues(alpha: 0.94),
      ),
      children: [
        _buildCellInput(
          _dataInicioController,
          bgColor: const Color(0xFFFFF2CC),
          onChanged: (_) {
            _recalcularDiasUteis();
            setState(() {});
          },
        ),
        _buildCellText(
          '',
          isHeader: true,
        ),
        ...List.generate(
          12,
          (i) => _buildCellText(
            '${i + 1}',
            isHeader: true,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  TableRow _buildDiasUteisRow() {
    return TableRow(
      children: [
        _buildCellText(
          'Dias Úteis',
          alignLeft: true,
          isBold: true,
        ),
        _buildCellText(
          '${_diasUteisCalculados.fold<int>(
            0,
            (sum, val) => sum + val,
          )}',
          isBold: true,
        ),
        ...List.generate(
          12,
          (i) => _buildCellText(
            '${_diasUteisCalculados[i]}',
          ),
        ),
      ],
    );
  }

  TableRow _buildMetaRow() {
    return TableRow(
      decoration: const BoxDecoration(
        color: Color(0xFFFFF8DF),
      ),
      children: [
        _buildCellText(
          'Meta',
          alignLeft: true,
          isBold: true,
        ),
        _buildCellText(
          _formatDoubleToTime(
            _metaControllers.fold<double>(
              0,
              (sum, item) =>
                  sum +
                  _parseTimeToDouble(
                    item.text,
                  ),
            ),
          ),
          isBold: true,
        ),
        ...List.generate(
          12,
          (i) => _buildCellInput(
            _metaControllers[i],
            isBold: true,
            onChanged: (val) {
              final mesKey = (i + 1).toString();

              widget.timeLogStore.salvarMetaMensal(
                _ano,
                mesKey,
                val,
              );

              setState(() {});
            },
          ),
        ),
      ],
    );
  }

  TableRow _buildRealizadoRow() {
    return TableRow(
      decoration: BoxDecoration(
        color: CoresApp.destaque.withValues(alpha: 0.035),
      ),
      children: [
        _buildCellText(
          'Hs Totais Realizadas',
          alignLeft: true,
          isBold: true,
        ),
        _buildCellText(
          _formatDoubleToTime(
            List.generate(
              12,
              (i) => _getRealizadoSum(i),
            ).fold<double>(
              0,
              (a, b) => a + b,
            ),
          ),
          isBold: true,
        ),
        ...List.generate(
          12,
          (i) => _buildCellText(
            _formatDoubleToTime(
              _getRealizadoSum(i),
            ),
            isBold: true,
          ),
        ),
      ],
    );
  }

  TableRow _buildHorasRow(
    String titulo,
    List<TextEditingController> controllers,
  ) {
    return TableRow(
      children: [
        _buildCellText(
          titulo,
          alignLeft: true,
        ),
        _buildCellText(
          _formatDoubleToTime(
            controllers.fold<double>(
              0,
              (sum, item) =>
                  sum +
                  _parseTimeToDouble(
                    item.text,
                  ),
            ),
          ),
        ),
        ...List.generate(
          12,
          (i) => _buildCellInput(
            controllers[i],
          ),
        ),
      ],
    );
  }

  Widget _buildCellText(
    String text, {
    bool isHeader = false,
    bool alignLeft = false,
    bool isBold = false,
    Color? color,
  }) {
    return Container(
      height: 39,
      padding: const EdgeInsets.symmetric(
        horizontal: 5,
        vertical: 6,
      ),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color ?? Colors.black87,
          fontSize: 10,
          fontWeight: isHeader || isBold ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildCellInput(
    TextEditingController controller, {
    bool isHeader = false,
    Color? bgColor,
    bool isBold = false,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      height: 39,
      color: bgColor,
      padding: const EdgeInsets.symmetric(
        horizontal: 2,
        vertical: 2,
      ),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
          color: isHeader ? AppPalette.text : Colors.black87,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            vertical: 8,
          ),
        ),
        onChanged: (val) {
          if (onChanged != null) {
            onChanged(val);
          } else {
            setState(() {});
          }
        },
      ),
    );
  }

  // ================================================================
  // DISPOSE
  // ================================================================

  @override
  void dispose() {
    widget.timeLogStore.removeListener(
      _atualizarValoresComLogs,
    );

    _dataInicioController.dispose();
    // A edição pendente termina de salvar mesmo ao sair da tela.
    _horasDiaController.dispose();

    for (int i = 0; i < 12; i++) {
      _metaControllers[i].dispose();
      _cobradasControllers[i].dispose();
      _investimentoControllers[i].dispose();
      _naoCobradasControllers[i].dispose();
      _internasControllers[i].dispose();
      _outrasControllers[i].dispose();
      _naoInformadasControllers[i].dispose();
    }

    super.dispose();
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_isLoadingFirebase) {
      return Scaffold(
        backgroundColor: CoresDashboard.fundo,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: Cabecalho(
          selectedIndex: widget.selectedIndex,
          onSelectTab: widget.onSelectTab,
          searchQuery: '',
          onSearchChanged: (val) {},
          userName: widget.userName,
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: Colors.transparent,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: CoresApp.fundo.withValues(alpha: 0.80),
            ),
          ),
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                18,
                18,
                18,
                30,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPageHeader(),
                  const SizedBox(height: 13),
                  _buildJornadaConfigCard(),
                  const SizedBox(height: 13),
                  _buildChartCard(),
                  const SizedBox(height: 13),
                  _buildPlanningTable(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================================================================
// MODELO DA ANÁLISE DE EFICIÊNCIA
// ==================================================================

class _EfficiencyPeriodData {
  final String title;
  final String subtitle;
  final double cobradas;
  final double realizado;
  final double efficiency;
  final IconData icon;

  const _EfficiencyPeriodData({
    required this.title,
    required this.subtitle,
    required this.cobradas,
    required this.realizado,
    required this.efficiency,
    required this.icon,
  });
}

// ==================================================================
// ABA MENSAL
// ==================================================================

class _EfficiencyMonthlyTab extends StatelessWidget {
  final _MetricsScreenState state;

  const _EfficiencyMonthlyTab({
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final periods = List.generate(
      12,
      (index) {
        final mes = index + 1;

        final cobradas = state._getCobradasForMonths(
          mes,
          mes,
        );

        final realizado = state._getRealizadoForMonths(
          mes,
          mes,
        );

        final efficiency = state._getEfficiencyForMonths(
          mes,
          mes,
        );

        return _EfficiencyPeriodData(
          title: state._meses[index].substring(0, 1).toUpperCase() +
              state._meses[index].substring(1),
          subtitle: 'Mês $mes de ${_MetricsScreenState._ano}',
          cobradas: cobradas,
          realizado: realizado,
          efficiency: efficiency,
          icon: Icons.calendar_month_rounded,
        );
      },
    );

    return state._buildEfficiencyContent(
      periods,
    );
  }
}

// ==================================================================
// ABA TRIMESTRAL
// ==================================================================

class _EfficiencyQuarterlyTab extends StatelessWidget {
  final _MetricsScreenState state;

  const _EfficiencyQuarterlyTab({
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final periods = <_EfficiencyPeriodData>[];

    const ranges = [
      (1, 3),
      (4, 6),
      (7, 9),
      (10, 12),
    ];

    for (int i = 0; i < ranges.length; i++) {
      final start = ranges[i].$1;
      final end = ranges[i].$2;

      final cobradas = state._getCobradasForMonths(
        start,
        end,
      );

      final realizado = state._getRealizadoForMonths(
        start,
        end,
      );

      final efficiency = state._getEfficiencyForMonths(
        start,
        end,
      );

      periods.add(
        _EfficiencyPeriodData(
          title: 'T${i + 1}',
          subtitle: '${state._meses[start - 1]} – '
              '${state._meses[end - 1]}',
          cobradas: cobradas,
          realizado: realizado,
          efficiency: efficiency,
          icon: Icons.view_week_rounded,
        ),
      );
    }

    return state._buildEfficiencyContent(
      periods,
    );
  }
}

// ==================================================================
// ABA SEMESTRAL
// ==================================================================

class _EfficiencySemiannualTab extends StatelessWidget {
  final _MetricsScreenState state;

  const _EfficiencySemiannualTab({
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final periods = <_EfficiencyPeriodData>[];

    const ranges = [
      (1, 6),
      (7, 12),
    ];

    for (int i = 0; i < ranges.length; i++) {
      final start = ranges[i].$1;
      final end = ranges[i].$2;

      final cobradas = state._getCobradasForMonths(
        start,
        end,
      );

      final realizado = state._getRealizadoForMonths(
        start,
        end,
      );

      final efficiency = state._getEfficiencyForMonths(
        start,
        end,
      );

      periods.add(
        _EfficiencyPeriodData(
          title: i == 0 ? '1º semestre' : '2º semestre',
          subtitle: '${state._meses[start - 1]} – '
              '${state._meses[end - 1]}',
          cobradas: cobradas,
          realizado: realizado,
          efficiency: efficiency,
          icon: Icons.date_range_rounded,
        ),
      );
    }

    return state._buildEfficiencyContent(
      periods,
    );
  }
}

// ==================================================================
// ABA ANUAL
// ==================================================================

class _EfficiencyAnnualTab extends StatelessWidget {
  final _MetricsScreenState state;

  const _EfficiencyAnnualTab({
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final cobradas = state._getCobradasAnual();

    final realizado = state._getRealizadoAnual();

    final efficiency = state._getEfficiency();

    final period = _EfficiencyPeriodData(
      title: 'Eficiência anual',
      subtitle: 'Resultado consolidado de '
          '${_MetricsScreenState._ano}',
      cobradas: cobradas,
      realizado: realizado,
      efficiency: efficiency,
      icon: Icons.auto_graph_rounded,
    );

    final efficiencyColor = state._getEfficiencyColor(
      efficiency,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        20,
        18,
        20,
        22,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppPalette.text.withValues(alpha: 0.025),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: efficiencyColor.withValues(
                alpha: 0.14,
              ),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 70,
                height: 70,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: efficiencyColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: efficiencyColor.withValues(alpha: 0.18),
                  ),
                ),
                child: Icon(
                  Icons.speed_rounded,
                  color: efficiencyColor,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'EFICIÊNCIA DE ${_MetricsScreenState._ano}',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                state._formatPercentage(
                  efficiency,
                ),
                style: TextStyle(
                  color: efficiencyColor,
                  fontSize: 31,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Cobradas ÷ Meta × 100',
                style: TextStyle(
                  color: CoresApp.textoSecundario.withValues(alpha: 0.75),
                  fontSize: 8,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _AnnualValueCard(
                      title: 'HORAS COBRADAS',
                      value: state._formatDoubleToTime(
                        period.cobradas,
                      ),
                      color: state._cobradasColor,
                      icon: Icons.business_center_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AnnualValueCard(
                      title: 'HORAS REALIZADAS',
                      value: state._formatDoubleToTime(
                        period.realizado,
                      ),
                      color: state._cadastradasColor,
                      icon: Icons.timer_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==================================================================
// CARD DE VALOR ANUAL
// ==================================================================

class _AnnualValueCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _AnnualValueCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: color.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              color: color,
              size: 16,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                    fontSize: 6,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.35,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
