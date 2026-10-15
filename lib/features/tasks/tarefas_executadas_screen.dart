import 'hours_send_selection.dart';
import 'task_history_month.dart';
import 'daily_hours_voice_command.dart';
import 'task_history_month_panel.dart';
import 'dart:async';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/domain/models/work_duration.dart';
import 'task_pdf_report.dart';
import 'task_log_edit_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/edesk_python.dart';
import 'package:gerenciador_horas/data/services/edesk_service.dart';
import 'package:printing/printing.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';
import 'package:gerenciador_horas/data/services/edesk_credentials_service.dart';

class TarefasScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  final TimeLogStore timeLogStore;

  const TarefasScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required this.timeLogStore,
    required String userName,
  });

  @override
  State<TarefasScreen> createState() => _TarefasScreenState();
}

class _TarefasScreenState extends State<TarefasScreen> {
  String? _filterOwner;
  String _lastFilterState = '';
  final _searchController = TextEditingController();
  String _lastQueryPeriod = '';
  void _applyQueryPeriod() {
    if (widget.selectedIndex != 5) return;
    final now = DateTime.now();
    DateTime? start, end;
    if (_filter == 'Hoje') { start = DateTime(now.year, now.month, now.day); end = start; }
    if (_filter == 'Esta semana') {
      start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      end = start.add(const Duration(days: 6));
    }
    if (_filter == 'Per\u00edodo') { start = _startDate; end = _endDate; }
    final signature = '${start?.toIso8601String()}/${end?.toIso8601String()}';
    if (_lastQueryPeriod == signature) return;
    _lastQueryPeriod = signature;
    unawaited(widget.timeLogStore.setHistoryPeriod(start, end));
  }
  @override
  void didUpdateWidget(covariant TarefasScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _lastQueryPeriod = '';
      _applyQueryPeriod();
    }
  }
  void _restoreFilters() {
    _filterOwner = FirebaseAuth.instance.currentUser?.uid;
    final data = LocalUserState.read(_filterOwner, 'filters.tasks');
    if (data == null) return;
    _filter = ['Todas', 'Hoje', 'Esta semana', 'Per\u00edodo'].contains(data['filter']) ? data['filter'] as String : 'Todas';
    _startDate = DateTime.tryParse(data['start']?.toString() ?? '');
    _endDate = DateTime.tryParse(data['end']?.toString() ?? '');
    if (_filter == 'Per\u00edodo' && (_startDate == null || _endDate == null)) _filter = 'Todas';
  }
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _applyQueryPeriod();
    if (_filterOwner == null || FirebaseAuth.instance.currentUser?.uid != _filterOwner) return;
    final data = {'filter': _filter, 'start': _startDate?.toIso8601String(), 'end': _endDate?.toIso8601String()};
    final encoded = jsonEncode(data);
    if (encoded == _lastFilterState) return;
    _lastFilterState = encoded;
    LocalUserState.write(_filterOwner, 'filters.tasks', data);
  }
  void _clearFilters() => setState(() {
    _filter = 'Todas'; _startDate = null; _endDate = null; _search = '';
    _searchController.clear();
  });

  final FirebaseService _firebaseService = FirebaseService();
  bool _enviandoEdesk = false;
  bool _preparandoHorasVoz = false;

  String _search = '';
  String _filter = 'Todas';

  DateTime? _startDate;
  DateTime? _endDate;

  final Set<String> _semanasExpandidas = {};
  final Set<int> _anosExpandidos = {};
  final Set<String> _mesesExpandidos = {};
  DateTime? _diaSelecionado;
  String _nivelHistoricoSelecionado = 'mes';
  int? _anoHistoricoSelecionado;
  int? _mesHistoricoSelecionado;
  DateTime? _semanaHistoricoSelecionada;
  bool _historicoInicializado = false;

  @override
  void initState() {
    super.initState();
    _restoreFilters();
    _applyQueryPeriod();
    widget.timeLogStore.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    widget.timeLogStore.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted && context.mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // FILTRO DE DATA
  // ============================================================

  Future<void> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(
              start: _startDate!,
              end: _endDate!,
            )
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)),
              end: now,
            ),
      builder: (context, child) {
        AppAppearance.watch(context);
        return child!;
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _filter = 'Período';
      });
    }
  }

  // ============================================================
  // REGISTROS
  // ============================================================

  List<TimeLog> get _registeredLogs {
    final query = _search.trim().toLowerCase();

    return widget.timeLogStore.logs.where((log) {
      if (!log.isRegistered) {
        return false;
      }

      if (_filter == 'Hoje') {
        final now = DateTime.now();

        if (log.date.year != now.year ||
            log.date.month != now.month ||
            log.date.day != now.day) {
          return false;
        }
      } else if (_filter == 'Esta semana') {
        final now = DateTime.now();

        final start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(
          Duration(days: now.weekday - 1),
        );

        final end = start.add(
          const Duration(days: 7),
        );

        if (log.date.isBefore(start) || !log.date.isBefore(end)) {
          return false;
        }
      } else if (_filter == 'Período' &&
          _startDate != null &&
          _endDate != null) {
        final normalizedLogDate = DateTime(
          log.date.year,
          log.date.month,
          log.date.day,
        );

        final normalizedStart = DateTime(
          _startDate!.year,
          _startDate!.month,
          _startDate!.day,
        );

        final normalizedEnd = DateTime(
          _endDate!.year,
          _endDate!.month,
          _endDate!.day,
          23,
          59,
          59,
        );

        if (normalizedLogDate.isBefore(normalizedStart) ||
            normalizedLogDate.isAfter(normalizedEnd)) {
          return false;
        }
      }

      if (query.isEmpty) {
        return true;
      }

      return log.targetId.toLowerCase().contains(query) ||
          (log.projectName ?? '').toLowerCase().contains(query) ||
          (log.taskName ?? '').toLowerCase().contains(query) ||
          (log.description ?? '').toLowerCase().contains(query) ||
          log.dateFormatted.contains(query);
    }).toList()
      ..sort(
        (a, b) => b.date.compareTo(a.date),
      );
  }

  Map<String, List<TimeLog>> get _groupedLogsByDate {
    final logs = _registeredLogs;
    final Map<String, List<TimeLog>> grouped = {};

    for (final log in logs) {
      final key = '${log.date.year}-${log.date.month}-${log.date.day}';

      grouped
          .putIfAbsent(
            key,
            () => [],
          )
          .add(log);
    }

    return grouped;
  }

  Map<String, List<TimeLog>> _groupLogsByWeek(
    List<TimeLog> logs,
  ) {
    final Map<String, List<TimeLog>> grouped = {};

    for (final log in logs) {
      final date = DateTime(
        log.date.year,
        log.date.month,
        log.date.day,
      );

      final weekStart = date.subtract(
        Duration(days: date.weekday - 1),
      );

      final key = '${weekStart.year}-${weekStart.month}-${weekStart.day}';

      grouped
          .putIfAbsent(
            key,
            () => [],
          )
          .add(log);
    }

    for (final list in grouped.values) {
      list.sort(
        (a, b) => b.date.compareTo(a.date),
      );
    }

    return grouped;
  }

  // ============================================================
  // DATAS
  // ============================================================

  DateTime _weekStart(DateTime date) {
    final normalized = DateTime(
      date.year,
      date.month,
      date.day,
    );

    return normalized.subtract(
      Duration(days: normalized.weekday - 1),
    );
  }

  String _weekKey(DateTime date) {
    final start = _weekStart(date);

    return '${start.year}-${start.month}-${start.day}';
  }

  String _formatWeekTitle(DateTime date) {
    final start = _weekStart(date);
    final end = start.add(
      const Duration(days: 6),
    );

    if (start.year == end.year && start.month == end.month) {
      return 'SEMANA '
          '${start.day.toString().padLeft(2, '0')}'
          ' — '
          '${end.day.toString().padLeft(2, '0')} '
          '${_monthShort(start.month)}';
    }

    if (start.year == end.year) {
      return 'SEMANA '
          '${start.day.toString().padLeft(2, '0')} '
          '${_monthShort(start.month)}'
          ' — '
          '${end.day.toString().padLeft(2, '0')} '
          '${_monthShort(end.month)}';
    }

    return 'SEMANA '
        '${_formatShortDate(start)}'
        ' — '
        '${_formatShortDate(end)}';
  }

  String _formatWeekRange(DateTime date) {
    final start = _weekStart(date);
    final end = start.add(
      const Duration(days: 6),
    );

    return '${_formatShortDate(start)} até '
        '${_formatShortDate(end)}';
  }

  String _formatShortDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatDateHeader(DateTime date) {
    const diasSemana = [
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo',
    ];

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${diasSemana[date.weekday - 1]}';
  }

  String _dayNameShort(int weekday) {
    const dias = [
      'SEG',
      'TER',
      'QUA',
      'QUI',
      'SEX',
      'SÁB',
      'DOM',
    ];

    return dias[weekday - 1];
  }

  String _formatarMinutos(int minutos) => WorkDuration.format(minutos);

  int _duracaoEmMinutos(TimeLog log) => WorkDuration.minutes(log);

  int _totalMinutos(List<TimeLog> logs) {
    int total = 0;

    for (final log in logs) {
      total += _duracaoEmMinutos(log);
    }

    return total;
  }

  Set<String> _projetosUnicos(List<TimeLog> logs) {
    return logs
        .map(
          (log) => (log.projectName ?? log.targetId).trim(),
        )
        .where(
          (name) => name.isNotEmpty,
        )
        .toSet();
  }

  String _monthShort(int month) {
    const months = [
      'JAN',
      'FEV',
      'MAR',
      'ABR',
      'MAI',
      'JUN',
      'JUL',
      'AGO',
      'SET',
      'OUT',
      'NOV',
      'DEZ',
    ];

    return months[month - 1];
  }

  // ============================================================
  // CABEÇALHO UNIFICADO
  // ============================================================

  Widget _buildUnifiedHeader({
    required int totalRegistros,
    required int totalProjetos,
    required String totalHoras,
    required int totalDias,
  }) {
    final stats = [
      _buildSummaryCard(
        icon: Icons.checklist_rounded,
        label: 'Tarefas',
        value: '$totalRegistros',
        description: 'registros',
        color: CoresApp.destaque,
      ),
      _buildSummaryCard(
        icon: Icons.folder_rounded,
        label: 'Projetos',
        value: '$totalProjetos',
        description: 'envolvidos',
        color: CoresApp.primaria,
      ),
      _buildSummaryCard(
        icon: Icons.schedule_rounded,
        label: 'Horas',
        value: totalHoras,
        description: 'registradas',
        color: CoresApp.secundaria,
      ),
      _buildSummaryCard(
        icon: Icons.calendar_month_rounded,
        label: 'Dias',
        value: '$totalDias',
        description: 'trabalhados',
        color: CoresApp.destaque,
      ),
    ];

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CoresApp.superficie.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CoresApp.borda.withValues(alpha: 0.75),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  CoresApp.primaria,
                  CoresApp.destaque,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                AppAppearance.watch(context);
                final width = constraints.maxWidth;

                final bool wide = width >= 1250;
                final bool medium = width >= 800 && width < 1250;

                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildUnifiedTitle(),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 7,
                        child: Row(
                          children: [
                            for (int i = 0; i < stats.length; i++) ...[
                              Expanded(
                                child: stats[i],
                              ),
                              if (i < stats.length - 1)
                                const SizedBox(width: 8),
                            ],
                            const SizedBox(width: 10),
                            _buildPdfActionButton(
                              compact: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                if (medium) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildUnifiedTitle(),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          for (int i = 0; i < stats.length; i++) ...[
                            Expanded(
                              child: stats[i],
                            ),
                            if (i < stats.length - 1) const SizedBox(width: 8),
                          ],
                          const SizedBox(width: 8),
                          _buildPdfActionButton(
                            compact: true,
                          ),
                        ],
                      ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildUnifiedTitle(),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final stat in stats)
                          SizedBox(
                            width: _getResponsiveStatWidth(width),
                            child: stat,
                          ),
                        _buildPdfActionButton(
                          compact: true,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TÍTULO
  // ============================================================

  Widget _buildUnifiedTitle() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 5,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                CoresApp.primaria,
                CoresApp.destaque,
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CoresApp.primaria.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: CoresApp.primaria.withValues(alpha: 0.22),
            ),
          ),
          child: Icon(
            Icons.task_alt_rounded,
            color: CoresApp.destaque,
            size: 24,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tarefas Executadas',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.25,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Apontamentos organizados por mês e semana',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CARD DE MÉTRICA
  // ============================================================

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required String description,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: 120,
        minHeight: 70,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: CoresApp.superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.9),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BOTÃO PDF
  // ============================================================

  Widget _buildPdfActionButton({
    required bool compact,
  }) {
    final enabled = widget.timeLogStore.logs.isNotEmpty;

    return Tooltip(
      message: 'Gerar relatório PDF',
      child: InkWell(
        onTap: enabled ? _abrirModalFiltroPdf : null,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: compact ? 68 : 70,
          constraints: const BoxConstraints(
            minWidth: 70,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: enabled
                ? CoresApp.primaria.withValues(alpha: 0.10)
                : CoresApp.fundo.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled
                  ? CoresApp.primaria.withValues(alpha: 0.30)
                  : CoresApp.borda.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: enabled
                      ? CoresApp.primaria.withValues(alpha: 0.12)
                      : CoresApp.borda.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.picture_as_pdf_rounded,
                  color: enabled
                      ? CoresApp.destaque
                      : CoresApp.textoSecundario.withValues(alpha: 0.5),
                  size: 17,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'PDF',
                style: TextStyle(
                  color: enabled
                      ? CoresApp.textoPrincipal
                      : CoresApp.textoSecundario.withValues(alpha: 0.5),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _getResponsiveStatWidth(double width) {
    if (width >= 700) {
      return 170;
    }

    if (width >= 500) {
      return 160;
    }

    if (width >= 360) {
      return 145;
    }

    return width;
  }

  // ============================================================
  // BARRA DE FILTROS
  // ============================================================

  Widget _buildFiltersBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: CoresApp.superficie.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CoresApp.borda.withValues(alpha: 0.7),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          AppAppearance.watch(context);
          final bool compact = constraints.maxWidth < 760;

          if (compact) {
            return Column(
              children: [
                SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar tarefa, projeto ou ID...',
                      hintStyle: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 12,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: CoresApp.textoSecundario,
                        size: 18,
                      ),
                      filled: true,
                      fillColor: CoresApp.fundo,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: CoresApp.borda.withValues(alpha: 0.6),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(8),
                        ),
                        borderSide: BorderSide(
                          color: CoresApp.primaria,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (value) {
                      setState(() => _search = value);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterDropdown(),
                      IconButton(tooltip: 'Limpar filtros', onPressed: _clearFilters, icon: const Icon(Icons.clear)),
                      const SizedBox(width: 8),
                      _buildFilterButton(
                        icon: Icons.date_range_rounded,
                        label: 'Período',
                        active: _filter == 'Período',
                        onPressed: () => _pickDateRange(context),
                      ),
                      if (_filter == 'Período' &&
                          _startDate != null &&
                          _endDate != null) ...[
                        const SizedBox(width: 8),
                        _buildPeriodBadge(),
                      ],
                    ],
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar tarefa, projeto ou ID...',
                      hintStyle: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 12,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: CoresApp.textoSecundario,
                        size: 18,
                      ),
                      filled: true,
                      fillColor: CoresApp.fundo,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: CoresApp.borda.withValues(alpha: 0.6),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(8),
                        ),
                        borderSide: BorderSide(
                          color: CoresApp.primaria,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (value) {
                      setState(() => _search = value);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildFilterDropdown(),
              IconButton(tooltip: 'Limpar filtros', onPressed: _clearFilters, icon: const Icon(Icons.clear)),
              const SizedBox(width: 8),
              _buildFilterButton(
                icon: Icons.date_range_rounded,
                label: 'Período',
                active: _filter == 'Período',
                onPressed: () => _pickDateRange(context),
              ),
              if (_filter == 'Período' &&
                  _startDate != null &&
                  _endDate != null) ...[
                const SizedBox(width: 8),
                _buildPeriodBadge(),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterDropdown() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
      ),
      decoration: BoxDecoration(
        color: CoresApp.fundo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CoresApp.borda.withValues(alpha: 0.6),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _filter == 'Período' ? 'Todas' : _filter,
          dropdownColor: CoresApp.superficie,
          borderRadius: BorderRadius.circular(9),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: CoresApp.textoSecundario,
            size: 18,
          ),
          style: TextStyle(
            color: CoresApp.textoPrincipal,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          items: const [
            DropdownMenuItem(
              value: 'Todas',
              child: Text('Todas'),
            ),
            DropdownMenuItem(
              value: 'Hoje',
              child: Text('Hoje'),
            ),
            DropdownMenuItem(
              value: 'Esta semana',
              child: Text('Esta semana'),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _filter = value ?? 'Todas';

              if (_filter != 'Período') {
                _startDate = null;
                _endDate = null;
              }
            });
          },
        ),
      ),
    );
  }

  Widget _buildFilterButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool active = false,
  }) {
    final color = active ? CoresApp.primaria : CoresApp.textoSecundario;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
        ),
        decoration: BoxDecoration(
          color: active ? CoresApp.primaria.withValues(alpha: 0.12) : CoresApp.fundo,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? CoresApp.primaria.withValues(alpha: 0.4) : CoresApp.borda,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color:
                    active ? CoresApp.textoPrincipal : CoresApp.textoSecundario,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodBadge() {
    if (_filter != 'Período' || _startDate == null || _endDate == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
      ),
      decoration: BoxDecoration(
        color: CoresApp.primaria.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CoresApp.primaria.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.date_range_rounded,
            color: CoresApp.destaque,
            size: 15,
          ),
          const SizedBox(width: 6),
          Text(
            '${_formatShortDate(_startDate!)} — '
            '${_formatShortDate(_endDate!)}',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () {
              setState(() {
                _filter = 'Todas';
                _startDate = null;
                _endDate = null;
              });
            },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                color: CoresApp.textoSecundario,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MODAL DETALHES DO DIA
  // ============================================================

  void _abrirModalDetalhesDia(
    String tituloData,
    String duracaoTotal,
    List<TimeLog> logsDoDia,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        AppAppearance.watch(context);
        return AlertDialog(
          backgroundColor: CoresApp.superficie,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: CoresApp.borda.withValues(alpha: 0.6),
            ),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CoresApp.primaria.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.calendar_today_rounded,
                  color: CoresApp.destaque,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tituloData,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${logsDoDia.length} tarefa(s) registrada(s)',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: CoresApp.primaria.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  duracaoTotal,
                  style: TextStyle(
                    color: CoresApp.destaque,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            height: 420,
            child: ListView.builder(
              itemCount: logsDoDia.length,
              itemBuilder: (context, index) {
                final log = logsDoDia[index];

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CoresApp.fundo,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: CoresApp.borda.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CoresApp.primaria.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: CoresApp.destaque,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${log.taskName ?? log.targetId} '
                              '(${log.projectName ?? 'Proj'})',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            if (log.description != null &&
                                log.description!.trim().isNotEmpty) ...[
                              Text(
                                log.description!,
                                style: TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 11.5,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                            ],
                            Text(
                              '${log.startTime} até ${log.endTime}   •   '
                              '${log.durationFormatted}',
                              style: TextStyle(
                                color: CoresApp.destaque,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Editar',
                        icon: Icon(
                          Icons.edit_outlined,
                          color: CoresApp.destaque,
                          size: 18,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _abrirModalEdicao(log);
                        },
                      ),
                      IconButton(
                        tooltip: 'Excluir',
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: CoresApp.erro,
                          size: 18,
                        ),
                        onPressed: () async {
                          final excluido =
                              await _excluirApontamentoComConfirmacao(log);

                          if (excluido && mounted && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.fundo,
                foregroundColor: AppPalette.foregroundOn(CoresApp.fundo),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                  side: BorderSide(
                    color: CoresApp.borda,
                  ),
                ),
                elevation: 0,
              ),
              onPressed: logsDoDia.isEmpty
                  ? null
                  : () {
                      Navigator.pop(context);

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && context.mounted) {
                          _enviarHorasDireto(logsDoDia);
                        }
                      });
                    },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.send_rounded,
                    size: 15,
                  ),
                  SizedBox(width: 6),
                  Text('E-Desk'),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.primaria,
                foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                elevation: 0,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

// ============================================================
// MODAL E-DESK
// ============================================================

  String _referenciaEdesk(TimeLog log) {
    final targetId = log.targetId.trim();

    if (targetId.isEmpty) {
      return 'Não identificada';
    }

    if (targetId.contains('_')) {
      final partes = targetId.split('_');

      if (partes.length >= 2) {
        final solicitacao = partes.first.trim();
        final idTrabalho = partes.sublist(1).join('_').trim();

        if (solicitacao.isNotEmpty && idTrabalho.isNotEmpty) {
          return '$solicitacao/$idTrabalho';
        }
      }
    }

    return targetId;
  }

// ============================================================
// EXTRAI SOLICITAÇÃO / ID DO TRABALHO
// ============================================================

  Map<String, String> _extrairReferenciaEdesk(TimeLog log) {
    final targetId = log.targetId.trim();

    if (targetId.isEmpty) {
      throw const EdeskException(
        'Não foi possível identificar o projeto/trabalho.',
      );
    }

    final partes = targetId.split('_');

    if (partes.length < 2) {
      throw EdeskException(
        'Referência E-Desk inválida: $targetId',
      );
    }

    final solicitacao = partes.first.trim();
    final idTrabalho = partes.sublist(1).join('_').trim();

    if (solicitacao.isEmpty || idTrabalho.isEmpty) {
      throw const EdeskException(
        'Não foi possível identificar a solicitação e o trabalho.',
      );
    }

    return {
      'solicitacao': solicitacao,
      'idTrabalho': idTrabalho,
    };
  }

// ============================================================
// MODAL PRINCIPAL DE CONFERÊNCIA E-DESK
// ============================================================

  Future<void> _enviarHorasDireto(List<TimeLog> logs, {bool fromVoice = false, bool speakResult = false}) async {
    if (_enviandoEdesk || (_preparandoHorasVoz && !fromVoice) || logs.isEmpty) return;
    final sendOwner = FirebaseAuth.instance.currentUser?.uid;
    if (sendOwner == null) return;
    setState(() => _enviandoEdesk = true);
    try {
      if (!fromVoice) {
        final selection = await selectHoursForSend(context, logs,
            canSend: () => mounted && FirebaseAuth.instance.currentUser?.uid == sendOwner);
        if (!mounted || FirebaseAuth.instance.currentUser?.uid != sendOwner || selection == null || selection.isEmpty) return;
        logs = selection;
      }
      final draftsSelecionados = logs
          .map((log) => _EdeskDraft(
                log: log,
                taskName: log.taskName ?? '',
                description: log.description ?? '',
                startTime: log.startTime,
                endTime: log.endTime,
              ))
          .toList();
      for (final draft in draftsSelecionados) {
        if (draft.taskName.trim().isEmpty ||
            draft.description.trim().isEmpty ||
            _calcularMinutos(draft.startTime, draft.endTime) <= 0) {
          throw EdeskException(
              'Revise a tarefa, o descritivo e o horário de ${_referenciaEdesk(draft.log)} antes de enviar.');
        }
      }
      final Map<String, List<_EdeskDraft>> grupos = {};

      for (final draft in draftsSelecionados) {
        final referencia = _extrairReferenciaEdesk(
          draft.log,
        );

        final chave = '${referencia['solicitacao']}_'
            '${referencia['idTrabalho']}';

        grupos.putIfAbsent(
          chave,
          () => <_EdeskDraft>[],
        );

        grupos[chave]!.add(draft);
      }

      if (grupos.isEmpty) {
        throw const EdeskException(
          'Nenhum trabalho válido foi encontrado.',
        );
      }

      final trabalhos = <Map<String, dynamic>>[];

      for (final grupo in grupos.values) {
        if (grupo.isEmpty) continue;

        final primeiro = grupo.first;

        final referencia = _extrairReferenciaEdesk(
          primeiro.log,
        );

        final solicitacao = referencia['solicitacao']!;
        final idTrabalho = referencia['idTrabalho']!;

        final horas = <Map<String, dynamic>>[];

        for (final draft in grupo) {
          final minutos = _calcularMinutos(
            draft.startTime,
            draft.endTime,
          );

          horas.add({
            'data': _formatarDataEdesk(
              draft.log.date,
            ),
            'inicio': draft.startTime,
            'fim': draft.endTime,
            'tipo': _normalizarTipoEdesk(
              draft.log.typeHs,
            ),
            'tarefa': draft.taskName.trim(),
            'descricao': draft.description.trim(),
            'projeto': draft.log.projectName ?? '',
            'targetId': draft.log.targetId,
            'duracaoMinutos': minutos,
            'horas': minutos / 60.0,
          });
        }

        trabalhos.add({
          'solicitacao': solicitacao,
          'idTrabalho': idTrabalho,
          'horas': horas,
        });
      }

      if (trabalhos.isEmpty) {
        throw const EdeskException(
          'Nenhum trabalho válido foi preparado para envio.',
        );
      }

      final credenciais = await EdeskCredentialsService().ler();

      if (!mounted || FirebaseAuth.instance.currentUser?.uid != sendOwner) return;

      final payload = {
        'url': 'https://promob.e-desk.com.br',
        'enviar': true,
        'trabalhos': trabalhos,
        'edeskCredenciais': credenciais == null
            ? null
            : {
                'email': credenciais['email'],
                'senha': credenciais['senha'],
              },
      };

      final requestJson = jsonEncode(payload);

      final resultado = await executarPythonEdesk(
        requestJson: requestJson,
        enviar: true,
        script: 'edesk_horas.py',
        speakResult: speakResult,
      );

      if (resultado.statusCode == 499) {
        return;
      }

      if (!resultado.confirmed) {
        throw EdeskException(
          resultado.message.isNotEmpty
              ? resultado.message
              : 'O Python não conseguiu '
                  'registrar as horas no E-Desk.',
        );
      }

      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(resultado.message),
        backgroundColor: CoresApp.primaria,
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao enviar horas para o E-Desk: $e'),
        backgroundColor: CoresApp.erro,
        duration: const Duration(seconds: 8),
      ));
    } finally {
      if (mounted && context.mounted) setState(() => _enviandoEdesk = false);
    }
  }

  String _formatarDataEdesk(dynamic date) {
    if (date == null) {
      return '';
    }

    if (date is DateTime) {
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    }

    final texto = date.toString().trim();

    if (texto.isEmpty) {
      return '';
    }

    if (RegExp(
      r'^\d{2}/\d{2}/\d{4}$',
    ).hasMatch(texto)) {
      return texto;
    }

    final iso = DateTime.tryParse(texto);

    if (iso != null) {
      return '${iso.day.toString().padLeft(2, '0')}/'
          '${iso.month.toString().padLeft(2, '0')}/'
          '${iso.year}';
    }

    return texto;
  }

  String _normalizarTipoEdesk(String? tipo) {
    final valor = tipo?.trim() ?? '';

    if (valor.isEmpty) {
      return '0';
    }

    if (RegExp(r'^\d+$').hasMatch(valor)) {
      return valor;
    }

    switch (valor.toLowerCase()) {
      case 'interno':
        return '0';

      case 'externo':
        return '1';

      case 'padrão':
      case 'padrao':
        return '3';

      default:
        return '0';
    }
  }

  int _calcularMinutos(String inicio, String fim) {
    final start = WorkDuration.clock(inicio), end = WorkDuration.clock(fim);
    return start != null && end != null && end > start ? end - start : 0;
  }

  InputDecoration _edeskInputDecoration(
    String label,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: CoresApp.textoSecundario,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(
          color: CoresApp.borda,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(
          color: CoresApp.primaria,
        ),
      ),
      filled: true,
      fillColor: CoresApp.superficie,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
    );
  }

  // Exclui um apontamento somente após confirmação do usuário.
  Future<bool> _excluirApontamentoComConfirmacao(TimeLog log) async {
    if (log.id.isEmpty) {
      return false;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return AlertDialog(
          backgroundColor: CoresApp.superficie,
          title: Text(
            'Excluir apontamento?',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Esta ação excluirá o apontamento do Firebase e não poderá ser desfeita.',
            style: TextStyle(color: CoresApp.textoSecundario),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Excluir'),
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                foregroundColor: AppPalette.foregroundOn(CoresApp.erro),
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return false;
    }

    await widget.timeLogStore.deleteFirebaseLog(log);
    return true;
  }

  void _abrirModalEdicao(TimeLog log) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TaskLogEditDialog(log: log, save: widget.timeLogStore.updateFirebaseLog),
    );
  }

  void _abrirModalFiltroPdf() {
    String filtroSelecionado = _filter;
    DateTime? inicioTemp = _startDate;
    DateTime? fimTemp = _endDate;

    showDialog(
      context: context,
      builder: (context) {
        AppAppearance.watch(context);
        return StatefulBuilder(
          builder: (context, setModalState) {
            AppAppearance.watch(context);
            return AlertDialog(
              backgroundColor: CoresApp.superficie,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: CoresApp.borda.withValues(alpha: 0.6),
                ),
              ),
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: CoresApp.primaria.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.picture_as_pdf_rounded,
                      color: CoresApp.destaque,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Configurar Relatório PDF',
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selecione o filtro base para o relatório:',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: filtroSelecionado == 'Período'
                          ? 'Período'
                          : filtroSelecionado,
                      dropdownColor: CoresApp.superficie,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 14,
                      ),
                      decoration: _edeskInputDecoration(
                        'Filtro',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Todas',
                          child: Text(
                            'Todas as tarefas',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Hoje',
                          child: Text(
                            'Apenas Hoje',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Esta semana',
                          child: Text(
                            'Esta Semana',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Período',
                          child: Text(
                            'Intervalo de Datas (Período)',
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setModalState(() {
                          filtroSelecionado = val ?? 'Todas';
                        });
                      },
                    ),
                    if (filtroSelecionado == 'Período') ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CoresApp.fundo,
                          foregroundColor: AppPalette.foregroundOn(CoresApp.fundo),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              10,
                            ),
                            side: BorderSide(
                              color: CoresApp.borda,
                            ),
                          ),
                          elevation: 0,
                        ),
                        icon: Icon(
                          Icons.date_range_rounded,
                          color: CoresApp.destaque,
                        ),
                        label: Text(
                          inicioTemp != null && fimTemp != null
                              ? '${_formatShortDate(inicioTemp!)} '
                                  'até '
                                  '${_formatShortDate(fimTemp!)}'
                              : 'Selecionar Datas',
                          style: const TextStyle(
                            fontSize: 13,
                          ),
                        ),
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            initialDateRange:
                                inicioTemp != null && fimTemp != null
                                    ? DateTimeRange(
                                        start: inicioTemp!,
                                        end: fimTemp!,
                                      )
                                    : null,
                            builder: (context, child) {
                              AppAppearance.watch(context);
                              return Theme(
                                data: ThemeData.dark().copyWith(
                                  colorScheme: ColorScheme.dark(
                                    primary: CoresApp.primaria,
                                    onPrimary: CoresApp.textoPrincipal,
                                    surface: CoresApp.superficie,
                                    onSurface: CoresApp.textoPrincipal,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );

                          if (picked != null) {
                            setModalState(() {
                              inicioTemp = picked.start;
                              fimTemp = picked.end;
                            });
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        10,
                      ),
                    ),
                  ),
                  icon: const Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 17,
                  ),
                  onPressed: () {
                    Navigator.pop(context);

                    _gerarPdfComFiltroEspecifico(
                      filtroSelecionado,
                      inicioTemp,
                      fimTemp,
                    );
                  },
                  label: const Text('Gerar PDF'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _gerarPdfComFiltroEspecifico(
    String filtroEscolhido,
    DateTime? inicio,
    DateTime? fim,
  ) async {
    try {
      final logsFiltrados = widget.timeLogStore.logs.where((log) {
        if (!log.isRegistered) {
          return false;
        }

        if (filtroEscolhido == 'Hoje') {
          final now = DateTime.now();

          if (log.date.year != now.year ||
              log.date.month != now.month ||
              log.date.day != now.day) {
            return false;
          }
        } else if (filtroEscolhido == 'Esta semana') {
          final now = DateTime.now();

          final start = DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(
            Duration(days: now.weekday - 1),
          );

          final end = start.add(
            const Duration(days: 7),
          );

          if (log.date.isBefore(start) || !log.date.isBefore(end)) {
            return false;
          }
        } else if (filtroEscolhido == 'Período' &&
            inicio != null &&
            fim != null) {
          final nLog = DateTime(
            log.date.year,
            log.date.month,
            log.date.day,
          );

          final nStart = DateTime(
            inicio.year,
            inicio.month,
            inicio.day,
          );

          final nEnd = DateTime(
            fim.year,
            fim.month,
            fim.day,
            23,
            59,
            59,
          );

          if (nLog.isBefore(nStart) || nLog.isAfter(nEnd)) {
            return false;
          }
        }

        return true;
      }).toList()
        ..sort(
          (a, b) => b.date.compareTo(a.date),
        );

      if (logsFiltrados.isEmpty) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Nenhum registro encontrado para o filtro selecionado.',
              ),
              backgroundColor: CoresApp.erro,
            ),
          );
        }

        return;
      }

      String periodoDescricao;

      switch (filtroEscolhido) {
        case 'Hoje':
          periodoDescricao = 'Hoje: ${_formatShortDate(DateTime.now())}';
          break;

        case 'Esta semana':
          final now = DateTime.now();

          final semanaInicio = DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(
            Duration(days: now.weekday - 1),
          );

          final semanaFim = semanaInicio.add(
            const Duration(days: 6),
          );

          periodoDescricao = 'Esta semana: '
              '${_formatShortDate(semanaInicio)} até '
              '${_formatShortDate(semanaFim)}';

          break;

        case 'Período':
          periodoDescricao = inicio != null && fim != null
              ? '${_formatShortDate(inicio)} até '
                  '${_formatShortDate(fim)}'
              : 'Período selecionado';
          break;

        default:
          periodoDescricao = 'Todos os registros';
      }

      final hoje = DateTime.now();
      final nomeArquivo = 'relatorio_atividades_${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}.pdf';
      final user = FirebaseAuth.instance.currentUser;
      final responsible = user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!.trim()
          : user?.email ?? 'Conta conectada';
      final pdf = await buildTaskPdfReport(
        data: TaskReportData(logsFiltrados, _duracaoEmMinutos),
        period: periodoDescricao,
        responsible: responsible,
        generatedAt: hoje,
      );

      if (!mounted || !context.mounted) {
        return;
      }

      await showDialog(
        context: context,
        builder: (dialogContext) {
          AppAppearance.watch(dialogContext);

          return Dialog(
            backgroundColor: CoresApp.superficie,
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              width: 1000,
              height: 750,
              child: Column(
                children: [
                  Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Pré-visualização do Relatório',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(
                            dialogContext,
                          ).pop(),
                          icon: Icon(
                            Icons.close_rounded,
                            color: CoresApp.textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PdfPreview(
                      build: (format) async => pdf.save(),
                      allowPrinting: true,
                      allowSharing: true,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      pdfFileName: nomeArquivo,
                      actions: const [],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao gerar PDF: $e',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }
  }

  // ============================================================
  // ESTADO VAZIO
  // ============================================================

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 480,
        ),
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: CoresApp.primaria.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(
                  16,
                ),
                border: Border.all(
                  color: CoresApp.primaria.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(
                Icons.task_alt_rounded,
                color: CoresApp.destaque,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum apontamento encontrado',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CoresApp.textoPrincipal,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Não existem tarefas cadastradas para os filtros selecionados.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LINHA DO DIA
  // ============================================================

  Widget _buildDayRow({
    required DateTime dataReferencia,
    required List<TimeLog> logsDoDia,
  }) {
    final totalDia = _formatarMinutos(
      _totalMinutos(logsDoDia),
    );

    final now = DateTime.now();

    final isToday = now.year == dataReferencia.year &&
        now.month == dataReferencia.month &&
        now.day == dataReferencia.day;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _abrirModalDetalhesDia(
          _formatDateHeader(
            dataReferencia,
          ),
          totalDia,
          logsDoDia,
        ),
        child: Container(
          height: 50,
          margin: const EdgeInsets.only(
            bottom: 4,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
          ),
          decoration: BoxDecoration(
            color: isToday
                ? CoresApp.primaria.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isToday
                  ? CoresApp.primaria.withValues(alpha: 0.25)
                  : CoresApp.borda.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dayNameShort(
                        dataReferencia.weekday,
                      ),
                      style: TextStyle(
                        color: isToday
                            ? CoresApp.destaque
                            : CoresApp.textoSecundario,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${dataReferencia.day.toString().padLeft(2, '0')} '
                      '${_monthShort(dataReferencia.month)}',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 26,
                color: CoresApp.borda.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${logsDoDia.length} '
                  '${logsDoDia.length == 1 ? 'tarefa' : 'tarefas'}',
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: CoresApp.primaria.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(
                    6,
                  ),
                ),
                child: Text(
                  totalDia,
                  style: TextStyle(
                    color: CoresApp.destaque,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: CoresApp.textoSecundario,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CARD DA SEMANA
  // ============================================================

  Widget _buildWeekCard({
    required DateTime weekStart,
    required List<TimeLog> logsDaSemana,
    required bool expanded,
  }) {
    final weekKey = _weekKey(weekStart);

    final totalSemana = _formatarMinutos(
      _totalMinutos(logsDaSemana),
    );

    final projetosSemana = _projetosUnicos(
      logsDaSemana,
    ).length;

    final groupedDays = <String, List<TimeLog>>{};

    for (final log in logsDaSemana) {
      final key = '${log.date.year}-${log.date.month}-${log.date.day}';

      groupedDays
          .putIfAbsent(
            key,
            () => [],
          )
          .add(log);
    }

    final dayKeys = groupedDays.keys.toList()
      ..sort(
        (a, b) => b.compareTo(a),
      );

    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      decoration: BoxDecoration(
        color: CoresApp.superficie.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: expanded
              ? CoresApp.primaria.withValues(alpha: 0.3)
              : CoresApp.borda.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(
                12,
              ),
              onTap: () {
                setState(() {
                  if (_semanasExpandidas.contains(weekKey)) {
                    _semanasExpandidas.remove(weekKey);
                  } else {
                    _semanasExpandidas.add(weekKey);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(
                        milliseconds: 180,
                      ),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: expanded
                            ? CoresApp.primaria.withValues(
                                alpha: 0.12,
                              )
                            : CoresApp.fundo,
                        borderRadius: BorderRadius.circular(
                          8,
                        ),
                      ),
                      child: Icon(
                        expanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        color: expanded
                            ? CoresApp.destaque
                            : CoresApp.textoSecundario,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _formatWeekTitle(
                                  weekStart,
                                ),
                                style: TextStyle(
                                  color: CoresApp.textoPrincipal,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (_weekKey(
                                    DateTime.now(),
                                  ) ==
                                  weekKey) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CoresApp.destaque.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(
                                      4,
                                    ),
                                  ),
                                  child: Text(
                                    'ATUAL',
                                    style: TextStyle(
                                      color: CoresApp.destaque,
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatWeekRange(
                              weekStart,
                            ),
                            style: TextStyle(
                              color: CoresApp.textoSecundario,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildWeekInfo(
                      value: totalSemana,
                      label: 'horas',
                      color: CoresApp.destaque,
                    ),
                    const SizedBox(width: 16),
                    _buildWeekInfo(
                      value: '${logsDaSemana.length}',
                      label: 'tarefas',
                      color: CoresApp.primaria,
                    ),
                    const SizedBox(width: 16),
                    _buildWeekInfo(
                      value: '$projetosSemana',
                      label: 'projetos',
                      color: CoresApp.secundaria,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                10,
                0,
                10,
                10,
              ),
              child: Column(
                children: [
                  Divider(
                    height: 1,
                    color: CoresApp.borda.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 6),
                  for (final dayKey in dayKeys)
                    _buildDayRow(
                      dataReferencia: groupedDays[dayKey]!.first.date,
                      logsDoDia: groupedDays[dayKey]!,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWeekInfo({
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: CoresApp.textoSecundario,
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _monthName(int month) {
    const months = [
      'JANEIRO',
      'FEVEREIRO',
      'MARÇO',
      'ABRIL',
      'MAIO',
      'JUNHO',
      'JULHO',
      'AGOSTO',
      'SETEMBRO',
      'OUTUBRO',
      'NOVEMBRO',
      'DEZEMBRO',
    ];
    return months[month - 1];
  }

  String _monthKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  Widget _buildPeriodInfo({required String value, required String label}) {
    return SizedBox(
      width: 58,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value,
              style: TextStyle(
                  color: CoresApp.destaque,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
          Text(label,
              style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 8,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildMonthCard(
      {required int year,
      required int month,
      required List<TimeLog> logs,
      required bool expanded}) {
    final key = _monthKey(year, month);
    final groupedWeeks = _groupLogsByWeek(logs);
    final weekKeys = groupedWeeks.keys.toList()..sort((a, b) => b.compareTo(a));
    final now = DateTime.now();
    final isCurrent = year == now.year && month == now.month;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      decoration: BoxDecoration(
        color: CoresApp.superficie.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: expanded
                ? CoresApp.primaria.withValues(alpha: 0.35)
                : CoresApp.borda.withValues(alpha: 0.6)),
      ),
      child: Column(children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => expanded
                ? _mesesExpandidos.remove(key)
                : _mesesExpandidos.add(key)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    color: expanded
                        ? CoresApp.destaque
                        : CoresApp.textoSecundario),
                const SizedBox(width: 8),
                Icon(Icons.calendar_month_rounded,
                    color: CoresApp.destaque, size: 18),
                const SizedBox(width: 10),
                Expanded(
                    child: Row(children: [
                  Text('${_monthName(month)} $year',
                      style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: 13,
                          fontWeight: FontWeight.w900)),
                  if (isCurrent) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: CoresApp.destaque.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text('ATUAL',
                          style: TextStyle(
                              color: CoresApp.destaque,
                              fontSize: 7.5,
                              fontWeight: FontWeight.w900)),
                    ),
                  ],
                ])),
                _buildPeriodInfo(
                    value: _formatarMinutos(_totalMinutos(logs)),
                    label: 'horas'),
                const SizedBox(width: 10),
                _buildPeriodInfo(value: '${logs.length}', label: 'tarefas'),
                const SizedBox(width: 10),
                _buildPeriodInfo(
                    value: '${_projetosUnicos(logs).length}',
                    label: 'projetos'),
              ]),
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(children: [
              for (final weekKey in weekKeys)
                _buildWeekCard(
                  weekStart: _weekStart(groupedWeeks[weekKey]!.first.date),
                  logsDaSemana: groupedWeeks[weekKey]!,
                  expanded: _semanasExpandidas.contains(weekKey) ||
                      weekKey == _weekKey(DateTime.now()),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _buildYearCard(
      {required int year,
      required List<TimeLog> logs,
      required bool expanded}) {
    final groupedMonths = <int, List<TimeLog>>{};
    final weeks = _groupLogsByWeek(logs);
    for (final entry in weeks.entries) {
      final weekLogs = entry.value;
      final start = _weekStart(weekLogs.first.date);
      final reference = start.add(const Duration(days: 6));
      groupedMonths.putIfAbsent(reference.month, () => []).addAll(weekLogs);
    }
    final months = groupedMonths.keys.toList()..sort((a, b) => b.compareTo(a));
    final now = DateTime.now();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: CoresApp.superficie.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: expanded
                ? CoresApp.primaria.withValues(alpha: 0.4)
                : CoresApp.borda.withValues(alpha: 0.65)),
      ),
      child: Column(children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => expanded
                ? _anosExpandidos.remove(year)
                : _anosExpandidos.add(year)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(children: [
                Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    color: expanded
                        ? CoresApp.destaque
                        : CoresApp.textoSecundario),
                const SizedBox(width: 8),
                Icon(Icons.calendar_month_rounded,
                    color: CoresApp.destaque, size: 19),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('$year',
                        style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 14,
                            fontWeight: FontWeight.w900))),
                _buildPeriodInfo(
                    value: _formatarMinutos(_totalMinutos(logs)),
                    label: 'horas'),
                const SizedBox(width: 10),
                _buildPeriodInfo(value: '${logs.length}', label: 'tarefas'),
                const SizedBox(width: 10),
                _buildPeriodInfo(
                    value: '${_projetosUnicos(logs).length}',
                    label: 'projetos'),
              ]),
            ),
          ),
        ),
        if (expanded)
          for (final month in months)
            _buildMonthCard(
              year: year,
              month: month,
              logs: groupedMonths[month]!,
              expanded: _mesesExpandidos.contains(_monthKey(year, month)) ||
                  (year == now.year && month == now.month),
            ),
      ]),
    );
  }

  String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<TimeLog> _logsDoDiaSelecionado(List<TimeLog> logs, DateTime dia) =>
      logs.where((log) => _sameDay(log.date, dia)).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  DateTime _diaInicial(List<TimeLog> logs) {
    if (_diaSelecionado != null) {
      return _diaSelecionado!;
    }
    final hoje = DateTime.now();
    if (logs.any((log) => _sameDay(log.date, hoje))) return hoje;
    final datas = logs.map((e) => e.date).toList()
      ..sort((a, b) => b.compareTo(a));
    return datas.first;
  }

  Map<int, Map<int, Map<DateTime, List<TimeLog>>>> _arvoreHistorico(
    List<TimeLog> logs,
  ) {
    final arvore = taskHistoryTree(logs);
    if (_anoHistoricoSelecionado != null && _mesHistoricoSelecionado != null) {
      arvore.putIfAbsent(_anoHistoricoSelecionado!, () => {})
          .putIfAbsent(_mesHistoricoSelecionado!, () => {});
    }
    for (final year in arvore.keys) {
      for (final month in arvore[year]!.keys) {
        for (final week in TaskHistoryMonth(year, month, []).weeks) {
          arvore[year]![month]!.putIfAbsent(week.monday, () => []);
        }
      }
    }
    return arvore;
  }

  Color _corProjeto(TimeLog log) {
    const cores = <Color>[
      Color(0xFF2196F3), // azul
      Color(0xFF7C4DFF), // roxo
      Color(0xFF00C853), // verde
      Color(0xFFFF9800), // laranja
      Color(0xFFE91E63), // rosa
      Color(0xFF00BCD4), // ciano
      Color(0xFFFFC107), // amarelo
      Color(0xFF9C27B0), // violeta
      Color(0xFF26A69A), // verde-água
      Color(0xFFFF5252), // vermelho
    ];

    final nome = (log.projectName ?? log.targetId).trim().toLowerCase();
    var hash = 0;
    for (final unidade in nome.codeUnits) {
      hash = ((hash * 31) + unidade) & 0x7fffffff;
    }
    return cores[hash % cores.length];
  }

  Widget _treeInfo(String horas, int tarefas) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(horas,
              style: TextStyle(
                  color: CoresApp.destaque,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900)),
          Text('$tarefas ${tarefas == 1 ? 'tarefa' : 'tarefas'}',
              style: TextStyle(color: CoresApp.textoSecundario, fontSize: 8.5)),
        ],
      );

  Widget _treeRow({
    required int level,
    required bool expanded,
    required bool expandable,
    required IconData icon,
    required String title,
    required List<TimeLog> logs,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: EdgeInsets.only(left: level * 18.0, bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? CoresApp.destaque.withValues(alpha: .12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(color: CoresApp.destaque.withValues(alpha: .8))
              : null,
        ),
        child: Row(children: [
          SizedBox(
            width: 18,
            child: expandable
                ? Icon(
                    expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                    size: 18,
                    color: CoresApp.destaque)
                : const SizedBox.shrink(),
          ),
          Container(
            width: 27,
            height: 27,
            decoration: BoxDecoration(
              color: CoresApp.primaria.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 15, color: CoresApp.destaque),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: level <= 1 ? 11.5 : 10.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700)),
          ),
          _treeInfo(_formatarMinutos(_totalMinutos(logs)), logs.length),
        ]),
      ),
    );
  }

  Widget _buildHistoryTree(List<TimeLog> logs, DateTime selectedDay) {
    final arvore = _arvoreHistorico(logs);
    final anos = arvore.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.only(right: 5),
      children: [
        for (final ano in anos) ...[
          Builder(builder: (_) {
            final mesesMap = arvore[ano]!;
            final logsAno = mesesMap.values
                .expand((semanas) => semanas.values.expand((e) => e))
                .toList();
            final anoAberto = _anosExpandidos.contains(ano);
            return Column(children: [
              _treeRow(
                level: 0,
                expanded: anoAberto,
                expandable: true,
                icon: Icons.calendar_month_rounded,
                title: '$ano',
                logs: logsAno,
                onTap: () => setState(() {
                  _nivelHistoricoSelecionado = 'ano';
                  _anoHistoricoSelecionado = ano;
                  _mesHistoricoSelecionado = null;
                  _semanaHistoricoSelecionada = null;
                  anoAberto
                      ? _anosExpandidos.remove(ano)
                      : _anosExpandidos.add(ano);
                }),
                selected: _nivelHistoricoSelecionado == 'ano' &&
                    _anoHistoricoSelecionado == ano,
              ),
              if (anoAberto)
                for (final mes
                    in (mesesMap.keys.toList()..sort((a, b) => b.compareTo(a))))
                  Builder(builder: (_) {
                    final semanasMap = mesesMap[mes]!;
                    final logsMes = semanasMap.values.expand((e) => e).toList();
                    final mk = _monthKey(ano, mes);
                    final mesAberto = _mesesExpandidos.contains(mk);
                    return Column(children: [
                      _treeRow(
                        level: 1,
                        expanded: mesAberto,
                        expandable: true,
                        icon: Icons.folder_rounded,
                        title: _monthName(mes),
                        logs: logsMes,
                        onTap: () => setState(() {
                          _nivelHistoricoSelecionado = 'mes';
                          _anoHistoricoSelecionado = ano;
                          _mesHistoricoSelecionado = mes;
                          _semanaHistoricoSelecionada = null;
                          mesAberto
                              ? _mesesExpandidos.remove(mk)
                              : _mesesExpandidos.add(mk);
                        }),
                        selected: _nivelHistoricoSelecionado == 'mes' &&
                            _anoHistoricoSelecionado == ano &&
                            _mesHistoricoSelecionado == mes,
                      ),
                      if (mesAberto)
                        for (final inicio
                            in (semanasMap.keys.toList()
                              ..sort((a, b) => b.compareTo(a))))
                          Builder(builder: (_) {
                            final logsSemana = semanasMap[inicio]!;
                            final wk = '$ano-$mes-${_weekKey(inicio)}';
                            final semanaAberta =
                                _semanasExpandidas.contains(wk);
                            final dias = <String, List<TimeLog>>{};
                            for (final log in logsSemana) {
                              dias
                                  .putIfAbsent(_dayKey(log.date), () => [])
                                  .add(log);
                            }
                            final week = TaskHistoryMonth(ano, mes, []).weeks.firstWhere(
                                (week) => _sameDay(week.monday, inicio));
                            final datas = week.days;
                            return Column(children: [
                              _treeRow(
                                level: 2,
                                expanded: semanaAberta,
                                expandable: true,
                                icon: Icons.date_range_rounded,
                                title: week.label,
                                logs: logsSemana,
                                onTap: () => setState(() {
                                  _nivelHistoricoSelecionado = 'semana';
                                  _anoHistoricoSelecionado = ano;
                                  _mesHistoricoSelecionado = mes;
                                  _semanaHistoricoSelecionada = inicio;
                                  semanaAberta
                                      ? _semanasExpandidas.remove(wk)
                                      : _semanasExpandidas.add(wk);
                                }),
                                selected: _nivelHistoricoSelecionado ==
                                        'semana' &&
                                    _anoHistoricoSelecionado == ano && _mesHistoricoSelecionado == mes &&
                                    _semanaHistoricoSelecionada != null &&
                                    _sameDay(
                                        _semanaHistoricoSelecionada!, inicio),
                              ),
                              if (semanaAberta)
                                for (final data in datas)
                                  _treeRow(
                                    level: 3,
                                    expanded: false,
                                    expandable: false,
                                    icon: Icons.calendar_today_rounded,
                                    title:
                                        '${_formatShortDate(data)} (${_dayNameShort(data.weekday)})',
                                    logs: dias[_dayKey(data)] ?? [],
                                    selected:
                                        _nivelHistoricoSelecionado == 'dia' &&
                                            _sameDay(data, selectedDay),
                                    onTap: () => setState(() {
                                      _nivelHistoricoSelecionado = 'dia';
                                      _diaSelecionado = data;
                                      _anoHistoricoSelecionado = data.year;
                                      _mesHistoricoSelecionado = data.month;
                                      _semanaHistoricoSelecionada =
                                          _weekStart(data);
                                    }),
                                  ),
                            ]);
                          }),
                    ]);
                  }),
            ]);
          }),
        ],
      ],
    );
  }

  List<TimeLog> _logsPeriodoSelecionado(List<TimeLog> logs) {
    final arvore = _arvoreHistorico(logs);

    if (_nivelHistoricoSelecionado == 'ano' &&
        _anoHistoricoSelecionado != null) {
      final meses = arvore[_anoHistoricoSelecionado];
      if (meses == null) return [];
      return meses.values
          .expand((semanas) => semanas.values.expand((e) => e))
          .toList();
    }

    if (_nivelHistoricoSelecionado == 'mes' &&
        _anoHistoricoSelecionado != null &&
        _mesHistoricoSelecionado != null) {
      final semanas =
          arvore[_anoHistoricoSelecionado]?[_mesHistoricoSelecionado];
      if (semanas == null) return [];
      return semanas.values.expand((e) => e).toList();
    }

    if (_nivelHistoricoSelecionado == 'semana' &&
        _semanaHistoricoSelecionada != null) {
      final inicio = _semanaHistoricoSelecionada!;
      final fim = inicio.add(const Duration(days: 6));
      return logs.where((log) {
        final d = DateTime(log.date.year, log.date.month, log.date.day);
        final i = DateTime(inicio.year, inicio.month, inicio.day);
        final f = DateTime(fim.year, fim.month, fim.day);
        return !d.isBefore(i) && !d.isAfter(f) &&
            (_anoHistoricoSelecionado == null || d.year == _anoHistoricoSelecionado) &&
            (_mesHistoricoSelecionado == null || d.month == _mesHistoricoSelecionado);
      }).toList();
    }

    return [];
  }

  String _tituloPeriodoSelecionado() {
    if (_nivelHistoricoSelecionado == 'ano') {
      return '${_anoHistoricoSelecionado ?? ''}';
    }
    if (_nivelHistoricoSelecionado == 'mes') {
      final mes = _mesHistoricoSelecionado;
      final ano = _anoHistoricoSelecionado;
      return mes == null || ano == null ? 'Mês' : '${_monthName(mes)} de $ano';
    }
    final inicio = _semanaHistoricoSelecionada;
    if (inicio == null) return 'Semana';
    final year = _anoHistoricoSelecionado;
    final month = _mesHistoricoSelecionado;
    if (year != null && month != null) {
      return TaskHistoryMonth(year, month, []).weeks.firstWhere(
          (week) => _sameDay(week.monday, inicio)).label;
    }
    return _formatWeekTitle(inicio);
  }

  void _selecionarMes(DateTime month) => setState(() {
    _historicoInicializado = true;
    _nivelHistoricoSelecionado = 'mes';
    _anoHistoricoSelecionado = month.year;
    _mesHistoricoSelecionado = month.month;
    _semanaHistoricoSelecionada = null;
    _anosExpandidos.add(month.year);
    _mesesExpandidos.add(_monthKey(month.year, month.month));
  });

  Widget _buildMonthNavigation(List<TimeLog> logs, DateTime fallback) {
    final month = DateTime(_anoHistoricoSelecionado ?? fallback.year,
        _mesHistoricoSelecionado ?? fallback.month);
    final months = <DateTime>{month, for (final log in logs) DateTime(log.date.year, log.date.month)}
        .toList()..sort((a, b) => b.compareTo(a));
    return Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      IconButton(tooltip: 'Mês anterior', onPressed: () => _selecionarMes(DateTime(month.year, month.month - 1)),
          icon: const Icon(Icons.chevron_left)),
      DropdownButton<DateTime>(value: month,
          items: [for (final date in months) DropdownMenuItem(value: date,
            child: Text('${taskHistoryMonths[date.month - 1]} ${date.year}'))],
          onChanged: (date) { if (date != null) _selecionarMes(date); }),
      IconButton(tooltip: 'Próximo mês', onPressed: () => _selecionarMes(DateTime(month.year, month.month + 1)),
          icon: const Icon(Icons.chevron_right)),
      if (_nivelHistoricoSelecionado != 'mes')
        TextButton(onPressed: () => _selecionarMes(month), child: const Text('Ver mês')),
      OutlinedButton.icon(icon: const Icon(Icons.today_outlined, size: 17), label: const Text('Hoje'),
          onPressed: () => setState(() {
            final today = DateTime.now();
            _historicoInicializado = true;
            _filter = 'Todas';
            _startDate = null;
            _endDate = null;
            _diaSelecionado = DateTime(today.year, today.month, today.day);
            _nivelHistoricoSelecionado = 'dia';
            _anoHistoricoSelecionado = today.year;
            _mesHistoricoSelecionado = today.month;
            _anosExpandidos.add(today.year);
            _mesesExpandidos.add(_monthKey(today.year, today.month));
            _semanasExpandidas.add('${today.year}-${today.month}-${_weekKey(today)}');
          })),
    ]);
  }

  Widget _buildSelectedPeriodPanel(List<TimeLog> allLogs) {
    if (_nivelHistoricoSelecionado == 'mes' && _anoHistoricoSelecionado != null && _mesHistoricoSelecionado != null) {
      return TaskHistoryMonthPanel(
        data: TaskHistoryMonth(_anoHistoricoSelecionado!, _mesHistoricoSelecionado!, allLogs),
        onEdit: _abrirModalEdicao,
        onSelectDay: (day) => setState(() {
          _nivelHistoricoSelecionado = 'dia';
          _diaSelecionado = day;
          _anoHistoricoSelecionado = day.year;
          _mesHistoricoSelecionado = day.month;
        }),
      );
    }
    final logs = _logsPeriodoSelecionado(allLogs)
      ..sort((a, b) {
        final data = a.date.compareTo(b.date);
        return data != 0 ? data : a.startTime.compareTo(b.startTime);
      });
    final total = _formatarMinutos(_totalMinutos(logs));
    final projetos = _projetosUnicos(logs).length;
    final porDia = <String, List<TimeLog>>{};
    for (final log in logs) {
      porDia.putIfAbsent(_dayKey(log.date), () => []).add(log);
    }
    final dias = porDia.values.map((e) => e.first.date).toList()
      ..sort((a, b) => a.compareTo(b));

    return Container(
      decoration: BoxDecoration(
        color: CoresApp.superficie.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CoresApp.borda.withValues(alpha: .7)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: CoresApp.primaria.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _nivelHistoricoSelecionado == 'mes'
                    ? Icons.calendar_month_rounded
                    : _nivelHistoricoSelecionado == 'semana'
                        ? Icons.date_range_rounded
                        : Icons.calendar_today_rounded,
                color: CoresApp.destaque,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tituloPeriodoSelecionado(),
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _nivelHistoricoSelecionado == 'mes'
                          ? 'Todas as tarefas e horas do mês'
                          : _nivelHistoricoSelecionado == 'semana'
                              ? 'Todas as tarefas e horas da semana'
                              : 'Todas as tarefas e horas do ano',
                      style: TextStyle(
                          color: CoresApp.textoSecundario, fontSize: 11),
                    ),
                  ]),
            ),
            _buildPeriodInfo(value: total, label: 'horas'),
            const SizedBox(width: 18),
            _buildPeriodInfo(value: '${logs.length}', label: 'tarefas'),
            const SizedBox(width: 18),
            _buildPeriodInfo(value: '$projetos', label: 'projetos'),
          ]),
        ),
        Divider(height: 1, color: CoresApp.borda.withValues(alpha: .6)),
        Expanded(
          child: logs.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: dias.length,
                  itemBuilder: (_, dayIndex) {
                    final dia = dias[dayIndex];
                    final logsDia = porDia[_dayKey(dia)]!;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: CoresApp.fundo.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(11),
                        border:
                            Border.all(color: CoresApp.borda.withValues(alpha: .45)),
                      ),
                      child: Column(children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          child: Row(children: [
                            SizedBox(
                              width: 54,
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dia.day.toString().padLeft(2, '0'),
                                      style: TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900),
                                    ),
                                    Text(
                                      _dayNameShort(dia.weekday),
                                      style: TextStyle(
                                          color: CoresApp.textoSecundario,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ]),
                            ),
                            Expanded(
                              child: Text(
                                _formatDateHeader(dia),
                                style: TextStyle(
                                    color: CoresApp.textoPrincipal,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            _buildPeriodInfo(
                                value: _formatarMinutos(_totalMinutos(logsDia)),
                                label: 'horas'),
                            const SizedBox(width: 12),
                            _buildPeriodInfo(
                                value: '${logsDia.length}', label: 'tarefas'),
                          ]),
                        ),
                        Divider(
                            height: 1, color: CoresApp.borda.withValues(alpha: .4)),
                        for (final log in logsDia)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            child: Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _corProjeto(log).withValues(alpha: .88),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  log.projectName ?? 'Projeto',
                                  style: TextStyle(
                                      color: AppPalette.text,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        log.taskName ?? log.targetId,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: CoresApp.textoPrincipal,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800),
                                      ),
                                      if ((log.description ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        Text(
                                          log.description!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: CoresApp.textoSecundario,
                                              fontSize: 10),
                                        ),
                                    ]),
                              ),
                              Text(
                                log.durationFormatted,
                                style: TextStyle(
                                    color: CoresApp.destaque,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'Editar',
                                onPressed: () => _abrirModalEdicao(log),
                                icon: Icon(Icons.edit_outlined,
                                    color: CoresApp.destaque, size: 18),
                              ),
                              IconButton(
                                tooltip: 'Excluir',
                                onPressed: () async {
                                  await _excluirApontamentoComConfirmacao(log);
                                },
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: CoresApp.erro,
                                  size: 18,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Ver detalhes do dia',
                                onPressed: () => setState(() {
                                  _nivelHistoricoSelecionado = 'dia';
                                  _diaSelecionado = dia;
                                  _anoHistoricoSelecionado = dia.year;
                                  _mesHistoricoSelecionado = dia.month;
                                  _semanaHistoricoSelecionada = _weekStart(dia);
                                }),
                                icon: Icon(Icons.visibility_outlined,
                                    color: CoresApp.destaque, size: 18),
                              ),
                            ]),
                          ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _buildSelectedDayPanel(List<TimeLog> allLogs, DateTime dia) {
    final logs = _logsDoDiaSelecionado(allLogs, dia);
    final total = _formatarMinutos(_totalMinutos(logs));
    final projetos = _projetosUnicos(logs).length;

    return Container(
      decoration: BoxDecoration(
        color: CoresApp.superficie.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CoresApp.borda.withValues(alpha: .7)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: CoresApp.primaria.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.calendar_month_rounded,
                  color: CoresApp.destaque, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(_formatDateHeader(dia),
                      style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: 17,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(_dayNameShort(dia.weekday),
                      style: TextStyle(
                          color: CoresApp.textoSecundario, fontSize: 11)),
                ])),
            _buildPeriodInfo(value: total, label: 'horas'),
            const SizedBox(width: 18),
            _buildPeriodInfo(value: '${logs.length}', label: 'tarefas'),
            const SizedBox(width: 18),
            _buildPeriodInfo(value: '$projetos', label: 'projetos'),
            const SizedBox(width: 18),
            ElevatedButton.icon(
              onPressed: logs.isEmpty ? null : () => _enviarHorasDireto(logs),
              icon: const Icon(Icons.cloud_upload_rounded, size: 17),
              label: const Text('Enviar para o E-Desk'),
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.primaria,
                foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
            ),
          ]),
        ),
        Divider(height: 1, color: CoresApp.borda.withValues(alpha: .6)),
        Expanded(
          child: logs.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final log = logs[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CoresApp.fundo.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(11),
                        border:
                            Border.all(color: CoresApp.borda.withValues(alpha: .45)),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 6),
                          decoration: BoxDecoration(
                            color: _corProjeto(log).withValues(alpha: .88),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(log.projectName ?? 'Projeto',
                              style: TextStyle(
                                  color: AppPalette.text,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(log.taskName ?? log.targetId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: CoresApp.textoPrincipal,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800)),
                              if ((log.description ?? '')
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(log.description!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: CoresApp.textoSecundario,
                                        fontSize: 10.5)),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                  '${log.startTime} até ${log.endTime}  •  ${_referenciaEdesk(log)}',
                                  style: TextStyle(
                                      color: CoresApp.destaque, fontSize: 9.5)),
                            ])),
                        Text(log.durationFormatted,
                            style: TextStyle(
                                color: CoresApp.destaque,
                                fontSize: 13,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Enviar esta tarefa para o E-Desk',
                          onPressed: () => _enviarHorasDireto([log]),
                          icon: Icon(Icons.cloud_upload_rounded,
                              color: CoresApp.destaque, size: 18),
                        ),
                        IconButton(
                          tooltip: 'Editar',
                          onPressed: () => _abrirModalEdicao(log),
                          icon: Icon(Icons.edit_outlined,
                              color: CoresApp.destaque, size: 18),
                        ),
                        IconButton(
                          tooltip: 'Excluir',
                          onPressed: () async {
                            await _excluirApontamentoComConfirmacao(log);
                          },
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: CoresApp.erro,
                            size: 18,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Ver detalhes do dia',
                          onPressed: () => _abrirModalDetalhesDia(
                              _formatDateHeader(dia), total, logs),
                          icon: Icon(Icons.visibility_outlined,
                              color: CoresApp.destaque, size: 18),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final registeredLogs = _registeredLogs;
    final dia =
        registeredLogs.isEmpty ? DateTime.now() : _diaInicial(registeredLogs);
    _anoHistoricoSelecionado ??= dia.year;
    _mesHistoricoSelecionado ??= dia.month;

    if (!_historicoInicializado && registeredLogs.isNotEmpty) {
      _historicoInicializado = true;
      _anosExpandidos.add(dia.year);
      _mesesExpandidos.add(_monthKey(dia.year, dia.month));
      _anoHistoricoSelecionado = dia.year;
      _mesHistoricoSelecionado = dia.month;
      _semanasExpandidas.add('${dia.year}-${dia.month}-${_weekKey(dia)}');
    }

    final summaryLogs = _nivelHistoricoSelecionado == 'mes'
        ? TaskHistoryMonth(_anoHistoricoSelecionado!, _mesHistoricoSelecionado!, registeredLogs).logs
        : registeredLogs;
    final totalRegistros = summaryLogs.length;
    final totalHoras = _formatarMinutos(_totalMinutos(summaryLogs));
    final totalProjetos = _projetosUnicos(summaryLogs).length;
    final totalDias = _nivelHistoricoSelecionado == 'mes'
        ? summaryLogs.map((log) => _dayKey(log.date)).toSet().length : _groupedLogsByDate.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: Cabecalho(
          selectedIndex: widget.selectedIndex,
          onSelectTab: widget.onSelectTab,
          searchQuery: _search,
          onSearchChanged: (value) => setState(() => _search = value),
          userName: '',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(children: [
          _buildUnifiedHeader(
            totalRegistros: totalRegistros,
            totalProjetos: totalProjetos,
            totalHoras: totalHoras,
            totalDias: totalDias,
          ),
          const SizedBox(height: 12),
          DailyHoursVoiceCommand(
            accountKey: FirebaseAuth.instance.currentUser?.uid,
            accountIsCurrent: (uid) => FirebaseAuth.instance.currentUser?.uid == uid,
            enabled: widget.selectedIndex == 5 && !_enviandoEdesk,
            loadDay: widget.timeLogStore.loadRegisteredDay,
            onBusyChanged: (busy) { if (mounted) setState(() => _preparandoHorasVoz = busy); },
            onSend: (logs, speakResult) => _enviarHorasDireto(logs, fromVoice: true, speakResult: speakResult)),
          const SizedBox(height: 8),
          _buildFiltersBar(),
          const SizedBox(height: 8),
          _buildMonthNavigation(registeredLogs, dia),
          const SizedBox(height: 8),
          Expanded(
            child: registeredLogs.isEmpty && _nivelHistoricoSelecionado != 'mes' && _nivelHistoricoSelecionado != 'dia'
                ? Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: CoresApp.superficie.withValues(alpha: .95),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: CoresApp.borda.withValues(alpha: .7)),
                    ),
                    child: _buildEmptyState(),
                  )
                : LayoutBuilder(builder: (context, constraints) => Row(children: [
                    if (constraints.maxWidth >= 980) SizedBox(
                      width: 300,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: CoresApp.superficie.withValues(alpha: .96),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: CoresApp.borda.withValues(alpha: .7)),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.fromLTRB(5, 3, 5, 8),
                                child: Row(children: [
                                  Icon(Icons.history_rounded,
                                      color: CoresApp.sucesso, size: 18),
                                  SizedBox(width: 8),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text('Histórico de apontamentos',
                                            style: TextStyle(
                                                color: CoresApp.textoPrincipal,
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w900)),
                                        Text('Ano • mês • semana • dia',
                                            style: TextStyle(
                                                color: CoresApp.textoSecundario,
                                                fontSize: 9.5)),
                                      ])),
                                ]),
                              ),
                              Divider(height: 1, color: CoresApp.borda),
                              const SizedBox(height: 6),
                              Expanded(
                                  child:
                                      _buildHistoryTree(registeredLogs, dia)),
                            ]),
                      ),
                    ),
                    if (constraints.maxWidth >= 980) const SizedBox(width: 10),
                    Expanded(
                      child: _nivelHistoricoSelecionado == 'dia'
                          ? _buildSelectedDayPanel(registeredLogs, dia)
                          : _buildSelectedPeriodPanel(registeredLogs),
                    ),
                  ])),
          ),
        ]),
      ),
    );
  }
}

// ================================================================
// MODELO TEMPORÁRIO DO E-DESK
// ================================================================

class _EdeskDraft {
  final TimeLog log;

  String taskName;
  String description;
  String startTime;
  String endTime;

  _EdeskDraft({
    required this.log,
    required this.taskName,
    required this.description,
    required this.startTime,
    required this.endTime,
  });
}

