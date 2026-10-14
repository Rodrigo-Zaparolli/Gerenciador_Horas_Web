import 'package:gerenciador_horas/core/theme/app_visuals.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'dart:async';

import 'package:flutter/material.dart';

class ControleProjetosWidget extends StatefulWidget {
  final bool agrupar;
  final bool ordenarPrioridade;
  final bool somenteAtivos;
  final bool filtroAtivo;

// Tipo de serviço selecionado
  final String tipoServicoSelecionado;

// Lista dinâmica vinda do cadastro de trabalho
  final List<String> tiposServicoOpcoes;

// Período
  final DateTime? dataInicio;
  final DateTime? dataFim;

  final Set<String>? expandedProjectIds;

  final VoidCallback onNewProject;
  final VoidCallback onSynchronize;
  final VoidCallback onFilter;
  final VoidCallback? onReset;
  final VoidCallback onManual;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback? onFolder;

  final ValueChanged<bool?> onAgruparChanged;
  final ValueChanged<bool?> onOrdenarPrioridadeChanged;
  final ValueChanged<bool?> onSomenteAtivosChanged;

// Callbacks dos filtros
  final ValueChanged<String?> onTipoServicoChanged;
  final ValueChanged<DateTime?> onDataInicioChanged;
  final ValueChanged<DateTime?> onDataFimChanged;

  const ControleProjetosWidget({
    super.key,
    required this.agrupar,
    required this.ordenarPrioridade,
    required this.somenteAtivos,
    required this.filtroAtivo,
    required this.tipoServicoSelecionado,
    required this.tiposServicoOpcoes,
    this.dataInicio,
    this.dataFim,
    this.expandedProjectIds,
    required this.onNewProject,
    required this.onSynchronize,
    required this.onFilter,
    this.onReset,
    required this.onManual,
    required this.onStart,
    required this.onPause,
    required this.onStop,
    this.onFolder,
    required this.onAgruparChanged,
    required this.onOrdenarPrioridadeChanged,
    required this.onSomenteAtivosChanged,
    required this.onTipoServicoChanged,
    required this.onDataInicioChanged,
    required this.onDataFimChanged,

// Mantidos para compatibilidade com a chamada existente.
    required String filtroProjetos,
    required Null Function(String? value) onFiltroProjetosChanged,
  });

  @override
  State<ControleProjetosWidget> createState() => _ControleProjetosWidgetState();
}

class _ControleProjetosWidgetState extends State<ControleProjetosWidget> {
  late Timer _timer;
  late DateTime _now;

// Mantém a resposta visual imediata do dropdown.
  late String _tipoServicoLocal;

  static Color get _background => AppPalette.surface;
  static Color get _fieldBackground => AppPalette.field;
  static Color get _accent => AppPalette.accent;
  static Color get _green => AppPalette.primary;
  static Color get _textPrimary => AppPalette.text;
  static Color get _textSecondary => AppPalette.secondary;

  @override
  void initState() {
    super.initState();

    _now = DateTime.now();
    _tipoServicoLocal = widget.tipoServicoSelecionado;

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) return;

        setState(() {
          _now = DateTime.now();
        });
      },
    );
  }

  @override
  void didUpdateWidget(covariant ControleProjetosWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.tipoServicoSelecionado != _tipoServicoLocal) {
      _tipoServicoLocal = widget.tipoServicoSelecionado;
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

// ==============================================================
// FORMATAÇÃO
// ==============================================================

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatClock(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}:'
        '${date.second.toString().padLeft(2, '0')}';
  }

// ==============================================================
// SELEÇÃO DE DATA
// ==============================================================

  Future<void> _selecionarData(
    BuildContext context,
    bool isInicio,
  ) async {
    final DateTime initialDate =
        (isInicio ? widget.dataInicio : widget.dataFim) ?? DateTime.now();

    int diaTemp = initialDate.day;
    int mesTemp = initialDate.month;
    int anoTemp = initialDate.year;

    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (BuildContext dialogContext) {
        AppAppearance.watch(dialogContext);

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            AppAppearance.watch(context);
            return AlertDialog(
              backgroundColor: _background,
              elevation: 18,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: AppPalette.text.withValues(alpha: 0.12),
                ),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              title: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.calendar_today_outlined,
                      color: _green,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isInicio
                          ? 'Selecionar Data Inicial'
                          : 'Selecionar Data Final',
                      style: TextStyle(
                        color: AppPalette.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 300,
                height: 110,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // DIA
                    Expanded(
                      child: _dateDropdown(
                        label: 'Dia',
                        value: diaTemp,
                        items: List.generate(
                          31,
                          (index) => index + 1,
                        ),
                        onChanged: (value) {
                          if (value != null) {
                            setStateDialog(() {
                              diaTemp = value;
                            });
                          }
                        },
                      ),
                    ),

                    Padding(
                      padding: EdgeInsets.only(top: 18),
                      child: Text(
                        '/',
                        style: TextStyle(
                          color: AppPalette.secondary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    // MÊS
                    Expanded(
                      child: _dateDropdown(
                        label: 'Mês',
                        value: mesTemp,
                        items: List.generate(
                          12,
                          (index) => index + 1,
                        ),
                        onChanged: (value) {
                          if (value != null) {
                            setStateDialog(() {
                              mesTemp = value;
                            });
                          }
                        },
                      ),
                    ),

                    Padding(
                      padding: EdgeInsets.only(top: 18),
                      child: Text(
                        '/',
                        style: TextStyle(
                          color: AppPalette.secondary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    // ANO
                    Expanded(
                      child: _dateDropdown(
                        label: 'Ano',
                        value: anoTemp,
                        items: List.generate(
                          16,
                          (index) => 2020 + index,
                        ),
                        onChanged: (value) {
                          if (value != null) {
                            setStateDialog(() {
                              anoTemp = value;
                            });
                          }
                        },
                        formatValue: (value) => value.toString(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(null);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: _textSecondary,
                  ),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: AppPalette.onPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    try {
                      final novaData = DateTime(
                        anoTemp,
                        mesTemp,
                        diaTemp,
                      );

                      Navigator.of(dialogContext).pop(novaData);
                    } catch (_) {
                      Navigator.of(dialogContext).pop(null);
                    }
                  },
                  child: const Text(
                    'Confirmar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != null) {
      if (isInicio) {
        widget.onDataInicioChanged(picked);
      } else {
        widget.onDataFimChanged(picked);
      }

      widget.onFilter();
    }
  }

// ==============================================================
// DROPDOWN DE DATA DO MODAL
// ==============================================================

  Widget _dateDropdown({
    required String label,
    required int value,
    required List<int> items,
    required ValueChanged<int?> onChanged,
    String Function(int value)? formatValue,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppPalette.secondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        DropdownButton<int>(
          value: value,
          dropdownColor: _background,
          underline: const SizedBox.shrink(),
          icon: Icon(
            Icons.keyboard_arrow_down,
            color: _textSecondary,
            size: 16,
          ),
          style: TextStyle(
            color: AppPalette.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          items: items.map((item) {
            return DropdownMenuItem<int>(
              value: item,
              child: Text(
                formatValue?.call(item) ?? item.toString().padLeft(2, '0'),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

// ==============================================================
// BUILD
// ==============================================================

  void _limparFiltros() {
    setState(() => _tipoServicoLocal = 'Todos os Serviços');
    if (widget.onReset != null) {
      widget.onReset!();
      return;
    }
    widget.onTipoServicoChanged(null);
    widget.onDataInicioChanged(null);
    widget.onDataFimChanged(null);
    widget.onFilter();
  }

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final listaServicos = <String>{
      'Todos os Serviços',
      ...widget.tiposServicoOpcoes.where((item) => item.trim().isNotEmpty),
    }.toList();
    if (!listaServicos.contains(_tipoServicoLocal)) {
      _tipoServicoLocal = listaServicos.first;
    }
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: AppVisuals.cardPadding,
      decoration: AppVisuals.card,
      child: DefaultTextStyle.merge(
        style: const TextStyle(height: 1.2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.calendar_today_outlined, color: _green, size: 16),
              const SizedBox(width: 7),
              Expanded(
                  child: Text(_formatDate(_now),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: _textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600))),
              Icon(Icons.access_time, color: _textSecondary, size: 14),
              const SizedBox(width: 5),
              Text(_formatClock(_now).substring(0, 5),
                  style: TextStyle(color: _textSecondary, fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            Text('Filtrar projetos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppPalette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Tipo de serviço',
                style: TextStyle(color: _textSecondary, fontSize: 11)),
            const SizedBox(height: 4),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: _fieldDecoration(),
              child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                value: _tipoServicoLocal,
                isExpanded: true,
                isDense: true,
                dropdownColor: _background,
                icon: Icon(Icons.keyboard_arrow_down,
                    color: _textSecondary, size: 20),
                style: TextStyle(color: _textPrimary, fontSize: 12),
                items: listaServicos
                    .map((tipo) => DropdownMenuItem<String>(
                          value: tipo,
                          child: Text(
                              tipo == 'Todos os Serviços'
                                  ? 'Todos os serviços'
                                  : tipo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _tipoServicoLocal = value);
                  widget.onTipoServicoChanged(
                      value == 'Todos os Serviços' ? null : value);
                  widget.onFilter();
                },
              )),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                  child: _dataField(context,
                      label: 'Data inicial',
                      date: widget.dataInicio,
                      isInicio: true)),
              const SizedBox(width: 8),
              Expanded(
                  child: _dataField(context,
                      label: 'Data final',
                      date: widget.dataFim,
                      isInicio: false)),
            ]),
            SizedBox(
                height: 24,
                child: TextButton(
                  onPressed: _limparFiltros,
                  style: TextButton.styleFrom(
                      foregroundColor: _textSecondary,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Text('Limpar filtros',
                      style: TextStyle(
                          fontSize: 11, decoration: TextDecoration.underline)),
                )),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                  child: SizedBox(
                      height: AppVisuals.buttonHeight,
                      child: ElevatedButton.icon(
                        onPressed: widget.onNewProject,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: AppPalette.onPrimary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8))),
                        icon: const Icon(Icons.add, size: 19),
                        label: const Text('Novo trabalho',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 32,
                  height: AppVisuals.buttonHeight,
                  child: IconButton(
                    onPressed: () {
                      widget.expandedProjectIds?.clear();
                      widget.onSynchronize();
                    },
                    style: IconButton.styleFrom(
                        foregroundColor: _textSecondary,
                        padding: EdgeInsets.zero,
                        side: BorderSide(color: AppPalette.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                    tooltip: 'Sincronizar',
                    icon: const Icon(Icons.sync, size: 20),
                  )),
            ]),
          ],
        ),
      ),
    );
  }

  BoxDecoration _fieldDecoration() => BoxDecoration(
        color: _fieldBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      );

  Widget _dataField(
    BuildContext context, {
    required String label,
    required DateTime? date,
    required bool isInicio,
  }) {
    final value = date == null ? 'dd/mm/aaaa' : _formatDate(date);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: _textSecondary, fontSize: 11)),
      const SizedBox(height: 4),
      Tooltip(
          message: '$label: $value',
          child: InkWell(
            onTap: () => _selecionarData(context, isInicio),
            borderRadius: BorderRadius.circular(8),
            child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: _fieldDecoration(),
                child: Row(children: [
                  Icon(Icons.calendar_today_outlined,
                      color: _textSecondary, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color:
                                  date == null ? _textSecondary : _textPrimary,
                              fontSize: 11))),
                ])),
          )),
    ]);
  }
}
