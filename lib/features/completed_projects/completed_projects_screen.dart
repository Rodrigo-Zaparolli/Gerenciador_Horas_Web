import 'package:gerenciador_horas/domain/models/work_duration.dart';
import 'completed_project_summary.dart';
import '../projects/dialogs/project_archive_dialog.dart';
import '../../data/services/project_file_service.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';

class CompletedProjectsScreen extends StatefulWidget {
  final FirebaseService firebaseService;
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  /// Mantido para não quebrar chamadas existentes da navegação.
  final String userName;

  const CompletedProjectsScreen({
    super.key,
    required this.firebaseService,
    required this.selectedIndex,
    required this.onSelectTab,
    required this.userName,
  });

  @override
  State<CompletedProjectsScreen> createState() =>
      _CompletedProjectsScreenState();
}

class _CompletedProjectsScreenState extends State<CompletedProjectsScreen> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  final Set<String> _expandedProjectIds = {};

  String _searchQuery = '';

  final TimeLogStore _timeLogStore = TimeLogStore();

  // ============================================================
  // CONVERSÃO DOS PROJETOS
  // ============================================================

  List<Map<String, dynamic>> _convertProjects(
    List<dynamic> projects,
  ) {
    return projects.map<Map<String, dynamic>>((project) {
      final dynamic data = project;

      if (data is Map<String, dynamic>) {
        return Map<String, dynamic>.from(data);
      }

      try {
        return {
          'id': data.id,
          'id2': data.id2,
          'client': data.client,
          'serviceType': data.serviceType,
          'stage': data.stage,
          'task': data.task,
          'status': data.status,
          'startDate': data.startDate,
          'estimatedHours': data.estimatedHours,
          'leader': data.leader,
          'hourType': data.hourType,
          'excelLink': data.excelLink,
          'folderPath': data.folderPath,
          'observacao': data.observacao,
          'finalizedAt': data.finalizedAt,
          'subTasks': (data.subTasks ?? [])
              .map<Map<String, dynamic>>(
                (task) => {
                  'subId': task.subId,
                  'stage': task.stage,
                  'status': task.status,
                  'startDate': task.startDate,
                  'planStart': task.planStart,
                  'planEnd': task.planEnd,
                  'estimatedHours': task.estimatedHours,
                  'hourType': task.hourType,
                },
              )
              .toList(),
        };
      } catch (_) {
        return <String, dynamic>{};
      }
    }).toList();
  }

  // ============================================================
  // FILTRO
  // ============================================================

  List<Map<String, dynamic>> _filterProjects(
    List<Map<String, dynamic>> projects,
  ) {
    final query = _searchQuery.trim().toLowerCase();

    final completed = projects.where((project) {
      final status = project['status']?.toString().trim().toUpperCase() ?? '';

      return status == 'TRAB_FIM';
    }).toList();

    if (query.isEmpty) {
      return completed;
    }

    return completed.where((project) {
      final id = project['id']?.toString().toLowerCase() ?? '';
      final id2 = project['id2']?.toString().toLowerCase() ?? '';
      final client = project['client']?.toString().toLowerCase() ?? '';
      final serviceType =
          project['serviceType']?.toString().toLowerCase() ?? '';
      final leader = project['leader']?.toString().toLowerCase() ?? '';
      final stage = project['stage']?.toString().toLowerCase() ?? '';

      return id.contains(query) ||
          id2.contains(query) ||
          client.contains(query) ||
          serviceType.contains(query) ||
          leader.contains(query) ||
          stage.contains(query);
    }).toList();
  }

  // ============================================================
  // DATAS
  // ============================================================

  DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    try {
      if (value.runtimeType.toString() == 'Timestamp') {
        return value.toDate();
      }
    } catch (_) {}

    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return '-';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year.toString().substring(2)}';
  }



  // ============================================================
  // HORAS
  // ============================================================

  int _timeToMinutes(String value) => WorkDuration.parse(value) ?? 0;

  String _minutesToTime(int totalMinutes) {
    if (totalMinutes < 0) {
      totalMinutes = 0;
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  int _getLogMinutes(TimeLog log) => WorkDuration.minutes(log);

  // ============================================================
  // VALORES
  // ============================================================

  String _stringValue(
    Map<String, dynamic> project,
    String key, [
    String defaultValue = '',
  ]) {
    final value = project[key];

    if (value == null) {
      return defaultValue;
    }

    return value.toString();
  }

  List<Map<String, dynamic>> _getSubTasks(
    Map<String, dynamic> project,
  ) {
    final value = project['subTasks'];

    if (value == null || value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(item),
        )
        .toList();
  }

  // ============================================================
  // CORES DE STATUS
  // ============================================================

  Color _getStatusColor(String status) {
    switch (status) {
      case 'TRAB_FIM':
        return CoresDashboard.statusFinalizado;

      case 'TRAB':
        return CoresDashboard.statusTrabalhando;

      case 'EA':
        return CoresDashboard.statusAndamento;

      case 'INI_PRO':
        return CoresDashboard.statusInicial;

      default:
        return CoresApp.textoSecundario;
    }
  }

  // ============================================================
  // DECORAÇÕES
  // ============================================================

  BoxDecoration _cardDecoration({
    Color? borderColor,
    Color? backgroundColor,
    double radius = 14,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? CoresDashboard.tabelaFundo,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? CoresDashboard.tabelaBorda,
      ),
      boxShadow: [
        BoxShadow(
          color: CoresApp.overlay.withValues(alpha: 0.14),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  // ============================================================
  // CARD DE INDICADOR
  // ============================================================

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required String description,
    Color? accentColor,
  }) {
    final color = accentColor ?? CoresApp.destaque;

    return Container(
      constraints: const BoxConstraints(
        minWidth: 120,
        minHeight: 72,
        maxHeight: 78,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: color.withValues(alpha: 0.18),
              ),
            ),
            child: Icon(
              icon,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
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
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.55,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.80),
                    fontSize: 8,
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
  // TÍTULO DA PÁGINA
  // ============================================================

  Widget _buildPageTitleContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 5,
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                CoresApp.sucesso,
                CoresApp.destaque,
              ],
            ),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CoresApp.sucesso.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: CoresApp.sucesso.withValues(alpha: 0.20),
            ),
          ),
          child: Icon(
            Icons.task_alt_rounded,
            color: CoresApp.sucesso,
            size: 24,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Projetos Finalizados',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.25,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Histórico completo dos trabalhos concluídos',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PESQUISA
  // ============================================================

  Widget _buildHeaderSearch() {
    return TextField(
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
        });
      },
      style: TextStyle(
        color: CoresApp.textoPrincipal,
        fontSize: 12,
      ),
      decoration: InputDecoration(
        hintText: 'Buscar por ID, cliente, serviço, líder ou etapa...',
        hintStyle: TextStyle(
          color: CoresApp.textoSecundario.withValues(alpha: 0.45),
          fontSize: 11,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: CoresApp.destaque,
          size: 18,
        ),
        suffixIcon: _searchQuery.trim().isNotEmpty
            ? IconButton(
                tooltip: 'Limpar pesquisa',
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                  });
                },
                icon: Icon(
                  Icons.close_rounded,
                  color: CoresApp.textoSecundario,
                  size: 16,
                ),
              )
            : null,
        filled: true,
        fillColor: CoresTelas.campoFormulario,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(
            color: CoresApp.bordaSuave,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(
            color: CoresApp.destaque,
            width: 1.2,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TÍTULO + INDICADORES
  // ============================================================

  Widget _buildPageTitle({
    required List<Map<String, dynamic>> allProjects,
    required List<Map<String, dynamic>> completedProjects,
    required int totalSubTasks,
    required DateTime? latestFinalized,
  }) {
    final int completedCount = allProjects.where((project) {
      final status = project['status']?.toString().trim().toUpperCase() ?? '';
      return status == 'TRAB_FIM';
    }).length;

    final stats = [
      _buildStatCard(
        icon: Icons.folder_copy_rounded,
        label: 'Projetos',
        value: '$completedCount',
        description: 'concluídos',
        accentColor: CoresApp.sucesso,
      ),
      _buildStatCard(
        icon: Icons.account_tree_rounded,
        label: 'Etapas',
        value: '$totalSubTasks',
        description: 'registradas',
        accentColor: CoresApp.destaque,
      ),
      _buildStatCard(
        icon: Icons.event_available_rounded,
        label: 'Última Conclusão',
        value: _formatDate(latestFinalized),
        description: 'data registrada',
        accentColor: CoresDashboard.statusFinalizado,
      ),
      _buildStatCard(
        icon: Icons.filter_alt_rounded,
        label: 'Exibindo',
        value: '${completedProjects.length}',
        description: _searchQuery.trim().isEmpty
            ? 'todos os projetos'
            : 'resultado da busca',
        accentColor: CoresApp.destaqueVerde,
      ),
    ];

    return Container(
      width: double.infinity,
      decoration: _cardDecoration(
        backgroundColor: CoresDashboard.tabelaFundo.withValues(alpha: 0.97),
        radius: 15,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      CoresApp.sucesso,
                      CoresApp.destaque,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(15),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  AppAppearance.watch(context);
                  final double width = constraints.maxWidth;

                  if (width >= 1200) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildPageTitleContent(),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 7,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  for (int i = 0; i < stats.length; i++) ...[
                                    Expanded(
                                      child: stats[i],
                                    ),
                                    if (i < stats.length - 1)
                                      const SizedBox(width: 8),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildHeaderSearch(),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPageTitleContent(),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, wrapConstraints) {
                          AppAppearance.watch(context);
                          final cardWidth = (wrapConstraints.maxWidth - 8) / 2;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: stats
                                .map(
                                  (stat) => SizedBox(
                                    width: cardWidth > 140
                                        ? cardWidth
                                        : wrapConstraints.maxWidth,
                                    child: stat,
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildHeaderSearch(),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CABEÇALHO DA TABELA
  // ============================================================

  Widget _buildTableHeader(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: CoresApp.textoSecundario,
        fontSize: TamanhosApp.tabelaFonteCabecalho,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    );
  }

  // ============================================================
  // TEXTO DA CÉLULA
  // ============================================================

  Widget _buildCellText(
    String text, {
    Color? color,
    FontWeight fontWeight = FontWeight.normal,
    double? fontSize,
  }) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? CoresApp.textoSecundario,
        fontSize: fontSize ?? TamanhosApp.tabelaFonte,
        fontWeight: fontWeight,
      ),
    );
  }

  // ============================================================
  // BADGE DO ID
  // ============================================================

  Widget _buildProjectIdBadge({
    required String id,
    required bool hasSubtasks,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(
        TamanhosApp.raioBotao,
      ),
      onTap: hasSubtasks ? onTap : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 21,
            child: hasSubtasks
                ? AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: CoresApp.destaque,
                      size: 18,
                    ),
                  )
                : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: CoresApp.destaque.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(
                TamanhosApp.raioBadge,
              ),
              border: Border.all(
                color: CoresApp.destaque.withValues(alpha: 0.32),
                width: TamanhosApp.espessuraBorda,
              ),
            ),
            child: Text(
              id,
              style: TextStyle(
                color: CoresApp.destaque,
                fontSize: TamanhosApp.tabelaFonte,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STATUS FINALIZADO
  // ============================================================

  Widget _buildCompletedStatusBadge() {
    final color = CoresDashboard.statusFinalizado;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioBadge,
        ),
        border: Border.all(
          color: color.withValues(alpha: 0.45),
          width: TamanhosApp.espessuraBorda,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 5),
          Text(
            'TRAB_FIM',
            style: TextStyle(
              color: color,
              fontSize: TamanhosApp.tabelaFonteStatus,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STATUS DA ETAPA
  // ============================================================

  Widget _buildTaskStatusBadge(String status) {
    final color = _getStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: 0.45),
          width: TamanhosApp.espessuraBorda,
        ),
      ),
      child: Text(
        status.isEmpty ? '-' : status,
        style: TextStyle(
          color: color,
          fontSize: TamanhosApp.tabelaFonteStatus,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ============================================================
  // AÇÕES
  // ============================================================

  Widget _buildActionControls(
    Map<String, dynamic> project,
  ) {
    final excelLink = _stringValue(
      project,
      'excelLink',
    ).trim();

    final folderPath = _stringValue(
      project,
      'folderPath',
    ).trim();

    final hasExcel = excelLink.isNotEmpty;
    final hasFolder = folderPath.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 3,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: CoresApp.textoPrincipal.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: CoresDashboard.tabelaBorda.withValues(alpha: 0.65),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasExcel || hasFolder)
            _buildActionButton(
              icon: Icons.link_rounded,
              color: CoresApp.destaqueVerde,
              tooltip: 'Abrir arquivo/link',
              onPressed: () => _openProjectResource(
                  hasExcel ? excelLink : folderPath, project['id'].toString(),
                  field: hasExcel ? 'excelLink' : 'folderPath'),
            ),
          _buildActionButton(
            icon: Icons.undo_rounded,
            color: CoresApp.destaqueVerde,
            tooltip: 'Reabrir trabalho',
            onPressed: () => _reopenProject(project),
          ),
          _buildActionButton(
            icon: Icons.visibility_rounded,
            color: CoresApp.destaque,
            tooltip: 'Visualizar trabalho',
            onPressed: () => _viewProject(project),
          ),
          _buildActionButton(
            icon: Icons.delete_outline_rounded,
            color: CoresApp.erro,
            tooltip: 'Excluir do histórico',
            onPressed: () => _deleteProjectFromHistory(project),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(
          minWidth: 31,
          minHeight: 31,
        ),
        padding: EdgeInsets.zero,
        splashRadius: 18,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: color,
          size: TamanhosApp.iconeAcao,
        ),
      ),
    );
  }

  // ============================================================
  // LINHA DO PROJETO
  // ============================================================

  DataRow _buildProjectRow(
    Map<String, dynamic> project,
  ) {
    final id = _stringValue(
      project,
      'id',
    );

    final id2 = _stringValue(
      project,
      'id2',
      '0',
    );

    final client = _stringValue(
      project,
      'client',
    );

    final serviceType = _stringValue(
      project,
      'serviceType',
    );

    final observation = _stringValue(
      project,
      'observacao',
    );

    final estimatedHours = _stringValue(
      project,
      'estimatedHours',
      '00:00',
    );

    final leader = _stringValue(
      project,
      'leader',
    );

    final hourType = _stringValue(
      project,
      'hourType',
      'Hs Cobradas',
    );

    final startDate = _parseDate(
      project['startDate'],
    );

    final finalizedAt = _parseDate(
      project['finalizedAt'],
    );

    final subTasks = _getSubTasks(project);

    final bool isExpanded = _expandedProjectIds.contains(id);

    final endDates = subTasks
        .map(
          (task) => _parseDate(
            task['planEnd'],
          ),
        )
        .whereType<DateTime>()
        .toList();

    DateTime? endDate;

    if (endDates.isNotEmpty) {
      endDates.sort();
      endDate = endDates.last;
    }

    endDate ??= finalizedAt;

    final String period = '${_formatDate(startDate)} - ${_formatDate(endDate)}';

    return DataRow(
      color: WidgetStateProperty.all(
        CoresDashboard.tabelaLinhaRegistrada,
      ),
      cells: [
        DataCell(
          _buildProjectIdBadge(
            id: id,
            hasSubtasks: subTasks.isNotEmpty,
            isExpanded: isExpanded,
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedProjectIds.remove(id);
                } else {
                  _expandedProjectIds.add(id);
                }
              });
            },
          ),
        ),
        DataCell(
          _buildCellText(
            id2,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            client,
            color: CoresApp.textoPrincipal,
            fontWeight: FontWeight.w700,
          ),
        ),
        DataCell(
          _buildCellText(
            serviceType,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            observation.isEmpty ? '-' : observation,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCompletedStatusBadge(),
        ),
        DataCell(
          _buildCellText(
            period,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            estimatedHours,
            color: CoresApp.destaque,
            fontWeight: FontWeight.w700,
          ),
        ),
        DataCell(
          _buildCellText(
            leader,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            hourType,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildActionControls(project),
        ),
      ],
    );
  }

  // ============================================================
  // LINHA DA SUBTAREFA
  // ============================================================

  DataRow _buildSubTaskRow({
    required Map<String, dynamic> project,
    required Map<String, dynamic> task,
  }) {
    final subId = _stringValue(
      task,
      'subId',
    );

    final stage = _stringValue(
      task,
      'stage',
    );

    final status = _stringValue(
      task,
      'status',
      'TRAB_FIM',
    );

    final estimatedHours = _stringValue(
      task,
      'estimatedHours',
      '00:00',
    );

    final hourType = _stringValue(
      task,
      'hourType',
      _stringValue(
        project,
        'hourType',
        'Hs Cobradas',
      ),
    );

    final startDate = _parseDate(
      task['startDate'],
    );

    final planEnd = _parseDate(
      task['planEnd'],
    );

    return DataRow(
      color: WidgetStateProperty.all(
        CoresDashboard.tabelaLinhaEtapa,
      ),
      cells: [
        const DataCell(
          SizedBox(width: 24),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 7,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: CoresApp.textoPrincipal.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              subId,
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: TamanhosApp.tabelaFonteSecundaria,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        DataCell(
          Padding(
            padding: const EdgeInsets.only(
              left: 12,
            ),
            child: _buildCellText(
              _stringValue(
                project,
                'client',
              ),
              color: CoresApp.textoSecundario.withValues(alpha: 0.65),
            ),
          ),
        ),
        DataCell(
          _buildCellText(
            _stringValue(
              project,
              'serviceType',
            ),
            color: CoresApp.textoSecundario.withValues(alpha: 0.65),
          ),
        ),
        DataCell(
          _buildCellText(
            stage,
            color: CoresApp.textoPrincipal,
            fontWeight: FontWeight.w600,
          ),
        ),
        DataCell(
          _buildTaskStatusBadge(status),
        ),
        DataCell(
          _buildCellText(
            '${_formatDate(startDate)} - ${_formatDate(planEnd)}',
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            estimatedHours,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            hourType,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          Icon(
            Icons.check_circle_rounded,
            color: CoresApp.sucesso,
            size: 18,
          ),
        ),
        const DataCell(
          SizedBox.shrink(),
        ),
      ],
    );
  }

  // ============================================================
  // GERA LINHAS
  // ============================================================

  List<DataRow> _generateRows(
    List<Map<String, dynamic>> projects,
  ) {
    final List<DataRow> rows = [];

    for (final project in projects) {
      final id = _stringValue(
        project,
        'id',
      );

      rows.add(
        _buildProjectRow(project),
      );

      if (_expandedProjectIds.contains(id)) {
        final subTasks = _getSubTasks(project);

        for (final task in subTasks) {
          rows.add(
            _buildSubTaskRow(
              project: project,
              task: task,
            ),
          );
        }
      }
    }

    return rows;
  }

  // ============================================================
  // ESTADO VAZIO
  // ============================================================

  Widget _buildEmptyState() {
    final bool searching = _searchQuery.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 30,
        vertical: 55,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  CoresApp.sucesso.withValues(alpha: 0.12),
                  CoresApp.destaque.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(19),
              border: Border.all(
                color: CoresApp.sucesso.withValues(alpha: 0.20),
              ),
            ),
            child: Icon(
              searching ? Icons.search_off_rounded : Icons.task_alt_rounded,
              color: searching ? CoresApp.textoSecundario : CoresApp.sucesso,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            searching
                ? 'Nenhum resultado encontrado'
                : 'Nenhum trabalho finalizado',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            searching
                ? 'Nenhum trabalho concluído corresponde à pesquisa.'
                : 'Os trabalhos concluídos aparecerão aqui automaticamente.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CoresApp.textoSecundario,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TABELA
  // ============================================================

  Widget _buildCompletedProjectsTable(
    List<Map<String, dynamic>> completedProjects,
  ) {
    final bool empty = completedProjects.isEmpty;

    return Container(
      width: double.infinity,
      decoration: _cardDecoration(
        radius: TamanhosApp.raioTabela,
      ).copyWith(
        border: Border(
          bottom: BorderSide(
            color: CoresDashboard.tabelaBorda,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  CoresApp.sucesso,
                  CoresApp.destaque,
                ],
              ),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(
                  TamanhosApp.raioTabela,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(
              16,
              11,
              14,
              10,
            ),
            decoration: BoxDecoration(
              color: CoresDashboard.tabelaCabecalho,
              border: Border(
                bottom: BorderSide(
                  color: CoresDashboard.tabelaBorda,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CoresApp.sucesso.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: CoresApp.sucesso.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Icon(
                    Icons.task_alt_rounded,
                    color: CoresApp.sucesso,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Trabalhos Finalizados',
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Histórico de projetos concluídos',
                        style: TextStyle(
                          color: CoresApp.textoSecundario,
                          fontSize: 9.5,
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
                    color: CoresApp.sucesso.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: CoresApp.sucesso.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        color: CoresApp.sucesso,
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${completedProjects.length} CONCLUÍDO'
                        '${completedProjects.length == 1 ? '' : 'S'}',
                        style: TextStyle(
                          color: CoresApp.sucesso,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          empty
              ? Center(
                  child: _buildEmptyState(),
                )
              : Expanded(
                  child: Scrollbar(
                    controller: _verticalController,
                    child: SingleChildScrollView(
                      controller: _verticalController,
                      scrollDirection: Axis.vertical,
                      child: Scrollbar(
                        controller: _horizontalController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _horizontalController,
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: DataTable(
                              showCheckboxColumn: false,
                              columnSpacing: 18,
                              horizontalMargin: 10,
                              headingRowHeight: 46,
                              dataRowMinHeight: 30,
                              dataRowMaxHeight: 38,
                              dividerThickness: 0.35,
                              headingRowColor: WidgetStateProperty.all(
                                CoresDashboard.tabelaCabecalho,
                              ),
                              dataRowColor: WidgetStateProperty.resolveWith(
                                (states) {
                                  if (states.contains(
                                    WidgetState.hovered,
                                  )) {
                                    return CoresDashboard.tabelaHover;
                                  }

                                  return null;
                                },
                              ),
                              columns: [
                                DataColumn(
                                  label: _buildTableHeader('ID'),
                                ),
                                DataColumn(
                                  label: _buildTableHeader('Nº'),
                                ),
                                DataColumn(
                                  label: _buildTableHeader('Cliente'),
                                ),
                                DataColumn(
                                  label: _buildTableHeader('Tipo de Serviço'),
                                ),
                                DataColumn(
                                  label: _buildTableHeader('Informações'),
                                ),
                                DataColumn(
                                  label: _buildTableHeader('Status'),
                                ),
                                DataColumn(
                                  label: _buildTableHeader('Data Início / Fim'),
                                ),
                                DataColumn(
                                  label: _buildTableHeader('Hs Estimadas'),
                                ),
                                DataColumn(
                                  label: _buildTableHeader('Líder Prj'),
                                ),
                                DataColumn(
                                  label: _buildTableHeader('Tipo HS'),
                                ),
                                DataColumn(
                                  label: _buildTableHeader('Ações'),
                                ),
                              ],
                              rows: _generateRows(
                                completedProjects,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  // ============================================================
  // CARD DE RESUMO DAS HORAS
  // ============================================================



  // ============================================================
  // BADGE REGISTRADO
  // ============================================================

  Widget _buildRegisteredBadge(bool registered) {
    final color = registered ? CoresApp.sucesso : CoresApp.textoSecundario;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: color.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            registered ? Icons.check_circle_rounded : Icons.schedule_rounded,
            color: color,
            size: 13,
          ),
          const SizedBox(width: 4),
          Text(
            registered ? 'REGISTRADO' : 'PENDENTE',
            style: TextStyle(
              color: color,
              fontSize: 7.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.25,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LINHA DE HORAS
  // ============================================================

  Widget _buildTimeLogCard(TimeLog log) {
    final int minutes = _getLogMinutes(log);

    final String duration = log.durationFormatted.trim().isNotEmpty
        ? log.durationFormatted.trim()
        : _minutesToTime(minutes);

    final String date = _formatDate(log.date);

    final String startTime =
        log.startTime.trim().isEmpty ? '--:--' : log.startTime.trim();

    final String endTime =
        log.endTime.trim().isEmpty ? '--:--' : log.endTime.trim();

    final String typeHs = log.typeHs?.trim().isNotEmpty == true
        ? log.typeHs!.trim()
        : 'Não informado';

    final String taskName = log.taskName?.trim().isNotEmpty == true
        ? log.taskName!.trim()
        : 'Tarefa não informada';

    final String description = log.description?.trim().isNotEmpty == true
        ? log.description!.trim()
        : '';

    return Container(
      margin: const EdgeInsets.only(
        bottom: 8,
      ),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: CoresApp.textoPrincipal.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CoresDashboard.tabelaBorda,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CoresApp.destaque.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: CoresApp.destaque.withValues(alpha: 0.14),
              ),
            ),
            child: Icon(
              Icons.access_time_rounded,
              color: CoresApp.destaque,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        taskName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildRegisteredBadge(
                      log.isRegistered,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 5,
                  children: [
                    _buildTimeLogSmallInfo(
                      icon: Icons.calendar_today_rounded,
                      text: date,
                    ),
                    _buildTimeLogSmallInfo(
                      icon: Icons.play_arrow_rounded,
                      text: startTime,
                    ),
                    _buildTimeLogSmallInfo(
                      icon: Icons.stop_rounded,
                      text: endTime,
                    ),
                    _buildTimeLogSmallInfo(
                      icon: Icons.timer_rounded,
                      text: duration,
                      highlight: true,
                    ),
                    _buildTimeLogSmallInfo(
                      icon: Icons.category_outlined,
                      text: typeHs,
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: CoresApp.textoPrincipal.withValues(alpha: 0.025),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.notes_rounded,
                          color: CoresApp.textoSecundario,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: CoresApp.textoSecundario,
                              fontSize: 9,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeLogSmallInfo({
    required IconData icon,
    required String text,
    bool highlight = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: highlight ? CoresApp.destaque : CoresApp.textoSecundario,
          size: 12,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: highlight ? CoresApp.destaque : CoresApp.textoSecundario,
            fontSize: 8.5,
            fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SEÇÃO DE HORAS
  // ============================================================



  Future<void> _openProjectResource(String reference, String projectId,
      {required String field}) async {
    try {
      await ProjectFileService.openFile(reference,
          projectId: projectId, field: field);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // ============================================================
  // VISUALIZAR PROJETO
  // ============================================================

  void _viewProject(
    Map<String, dynamic> project,
  ) {
    final id = project['id']?.toString() ?? '-';
    final client = project['client']?.toString() ?? '-';
    final serviceType = project['serviceType']?.toString() ?? '-';
    final leader = project['leader']?.toString() ?? '-';
    final estimatedHours = project['estimatedHours']?.toString() ?? '00:00';

    final startDate = _parseDate(
      project['startDate'],
    );

    final finalizedAt = completedProjectEndDate(project, _parseDate);

    final subTasks = _getSubTasks(project);

    final excelLink = _stringValue(
      project,
      'excelLink',
    );

    final folderPath = _stringValue(
      project,
      'folderPath',
    );

    final user = FirebaseAuth.instance.currentUser;

    if (user == null || id.trim().isEmpty || id == '-') {
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        final screenHeight = MediaQuery.of(dialogContext).size.height;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 20,
          ),
          child: SizedBox(
            width: 980,
            height: screenHeight > 900 ? 850 : screenHeight - 40,
            child: Container(
              decoration: BoxDecoration(
                color: CoresDashboard.tabelaFundo,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: CoresDashboard.tabelaBorda,
                ),
                boxShadow: [
                  BoxShadow(
                    color: CoresApp.overlay.withValues(alpha: 0.35),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  children: [
                    // ==================================================
                    // CABEÇALHO
                    // ==================================================

                    Container(
                      padding: const EdgeInsets.fromLTRB(
                        20,
                        16,
                        12,
                        16,
                      ),
                      decoration: BoxDecoration(
                        color: CoresDashboard.tabelaCabecalho,
                        border: Border(
                          bottom: BorderSide(
                            color: CoresDashboard.tabelaBorda,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  CoresApp.sucesso.withValues(alpha: 0.14),
                                  CoresApp.destaque.withValues(alpha: 0.07),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: CoresApp.sucesso.withValues(alpha: 0.20),
                              ),
                            ),
                            child: Icon(
                              Icons.task_alt_rounded,
                              color: CoresApp.sucesso,
                              size: 23,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Trabalho finalizado',
                                  style: TextStyle(
                                    color: CoresApp.textoPrincipal,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Projeto $id • Histórico concluído',
                                  style: TextStyle(
                                    color: CoresApp.textoSecundario,
                                    fontSize: 10.5,
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
                              color: CoresApp.sucesso.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: CoresApp.sucesso.withValues(alpha: 0.16),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: CoresApp.sucesso,
                                  size: 13,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'FINALIZADO',
                                  style: TextStyle(
                                    color: CoresApp.sucesso,
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
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
                    ),

                    // ==================================================
                    // CONTEÚDO
                    //
                    // O ponto importante da correção:
                    // o StreamBuilder fica dentro do conteúdo principal,
                    // mas a rolagem fica em um único ListView.
                    // ==================================================

                    Expanded(
                      child: StreamBuilder<List<TimeLog>>(
                        stream: _timeLogStore.streamProjectTimeLogs(
                          user.uid,
                          id,
                        ),
                        builder: (context, snapshot) {
                          AppAppearance.watch(context);
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              !snapshot.hasData) {
                            return Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: CoresApp.destaque,
                              ),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(25),
                                child: Text(
                                  'Não foi possível carregar os horários:\n'
                                  '${snapshot.error}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: CoresApp.erro,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            );
                          }

                          final logs = snapshot.data ?? <TimeLog>[];

                          final registeredCount =
                              logs.where((log) => log.isRegistered).length;

                          return ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              // ==================================================
                              // INFORMAÇÕES PRINCIPAIS
                              // ==================================================

                              LayoutBuilder(
                                builder: (context, constraints) {
                                  AppAppearance.watch(context);
                                  if (constraints.maxWidth < 650) {
                                    return Column(
                                      children: [
                                        _buildInfoCard(
                                          icon: Icons.business_rounded,
                                          title: 'Cliente',
                                          value: client,
                                        ),
                                        const SizedBox(height: 10),
                                        _buildInfoCard(
                                          icon: Icons.work_outline_rounded,
                                          title: 'Tipo de Serviço',
                                          value: serviceType,
                                        ),
                                        const SizedBox(height: 10),
                                        _buildInfoCard(
                                          icon: Icons.person_outline_rounded,
                                          title: 'Líder',
                                          value: leader,
                                        ),
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      Expanded(
                                        child: _buildInfoCard(
                                          icon: Icons.business_rounded,
                                          title: 'Cliente',
                                          value: client,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _buildInfoCard(
                                          icon: Icons.work_outline_rounded,
                                          title: 'Tipo de Serviço',
                                          value: serviceType,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _buildInfoCard(
                                          icon: Icons.person_outline_rounded,
                                          title: 'Líder',
                                          value: leader,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),

                              const SizedBox(height: 10),

                              LayoutBuilder(
                                builder: (context, constraints) {
                                  AppAppearance.watch(context);
                                  if (constraints.maxWidth < 650) {
                                    return Column(
                                      children: [
                                        _buildInfoCard(
                                          icon: Icons.schedule_rounded,
                                          title: 'Horas Estimadas',
                                          value: estimatedHours,
                                        ),
                                        const SizedBox(height: 10),
                                        _buildInfoCard(
                                          icon: Icons.calendar_today_rounded,
                                          title: 'Data de Início',
                                          value: _formatDate(startDate),
                                        ),
                                        const SizedBox(height: 10),
                                        _buildInfoCard(
                                          icon: Icons.event_available_rounded,
                                          title: 'Finalizado em',
                                          value: _formatDate(
                                            finalizedAt,
                                          ),
                                        ),
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      Expanded(
                                        child: _buildInfoCard(
                                          icon: Icons.schedule_rounded,
                                          title: 'Horas Estimadas',
                                          value: estimatedHours,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _buildInfoCard(
                                          icon: Icons.calendar_today_rounded,
                                          title: 'Data de Início',
                                          value: _formatDate(startDate),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _buildInfoCard(
                                          icon: Icons.event_available_rounded,
                                          title: 'Finalizado em',
                                          value: _formatDate(
                                            finalizedAt,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),

                              // ==================================================
                              // STATUS
                              // ==================================================

                              const SizedBox(height: 18),

                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      CoresApp.sucesso.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: CoresApp.sucesso
                                        .withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: CoresApp.sucesso,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'TRAB_FIM',
                                      style: TextStyle(
                                        color: CoresApp.sucesso,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${subTasks.length} etapa(s)',
                                      style: TextStyle(
                                        color: CoresApp.textoSecundario,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 18),
                              CompletedProjectSummaryCard(
                                summary: CompletedHoursSummary.calculate(
                                  projectId: id,
                                  estimatedHours: estimatedHours,
                                  tasks: subTasks,
                                  logs: logs,
                                  parseMinutes: _timeToMinutes,
                                  logMinutes: _getLogMinutes,
                                ),
                              ),

                              // ==================================================
                              // HORAS TRABALHADAS
                              // ==================================================

                              const SizedBox(height: 18),

                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: CoresApp.destaque
                                      .withValues(alpha: 0.025),
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(
                                    color: CoresApp.destaque
                                        .withValues(alpha: 0.14),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(13),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 35,
                                            height: 35,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: CoresApp.destaque
                                                  .withValues(alpha: 0.10),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                9,
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.access_time_filled_rounded,
                                              color: CoresApp.destaque,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 9),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Horas trabalhadas',
                                                  style: TextStyle(
                                                    color:
                                                        CoresApp.textoPrincipal,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  'Apontamentos cadastrados neste projeto',
                                                  style: TextStyle(
                                                    color: CoresApp
                                                        .textoSecundario,
                                                    fontSize: 9,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: CoresApp.destaque
                                                  .withValues(alpha: 0.09),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                20,
                                              ),
                                            ),
                                            child: Text(
                                              '${logs.length} apontamento(s)',
                                              style: TextStyle(
                                                color: CoresApp.destaque,
                                                fontSize: 8,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '${logs.length} apontamentos | $registeredCount registrados',
                                        style: TextStyle(
                                            color: CoresApp.textoSecundario,
                                            fontSize: 11),
                                      ),
                                      const SizedBox(height: 12),
                                      if (logs.isEmpty)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 15,
                                            vertical: 22,
                                          ),
                                          decoration: BoxDecoration(
                                            color: CoresApp.textoPrincipal
                                                .withValues(alpha: 0.018),
                                            borderRadius:
                                                BorderRadius.circular(9),
                                            border: Border.all(
                                              color: CoresDashboard.tabelaBorda,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Icon(
                                                Icons.schedule_outlined,
                                                color: CoresApp.textoSecundario,
                                                size: 26,
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                'Nenhum horário encontrado',
                                                style: TextStyle(
                                                  color:
                                                      CoresApp.textoPrincipal,
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else ...[
                                        Text(
                                          'Lançamentos de horas',
                                          style: TextStyle(
                                            color: CoresApp.textoPrincipal,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        ...logs.map(
                                          (log) => _buildTimeLogCard(log),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),

                              // ==================================================
                              // ETAPAS
                              // ==================================================

                              if (subTasks.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.account_tree_rounded,
                                      color: CoresApp.destaque,
                                      size: 17,
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      'Etapas do projeto',
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: CoresApp.destaque
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '${subTasks.length}',
                                        style: TextStyle(
                                          color: CoresApp.destaque,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 9),
                                ...subTasks.map(
                                  (task) {
                                    final stage = _stringValue(
                                      task,
                                      'stage',
                                      '-',
                                    );

                                    final status = _stringValue(
                                      task,
                                      'status',
                                      'TRAB_FIM',
                                    );

                                    final taskStart = _parseDate(
                                      task['startDate'],
                                    );

                                    final taskEnd = _parseDate(
                                      task['planEnd'],
                                    );

                                    return Container(
                                      margin: const EdgeInsets.only(
                                        bottom: 7,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        color: CoresApp.textoPrincipal
                                            .withValues(alpha: 0.025),
                                        borderRadius: BorderRadius.circular(9),
                                        border: Border.all(
                                          color: CoresDashboard.tabelaBorda,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 30,
                                            height: 30,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: CoresApp.sucesso
                                                  .withValues(alpha: 0.08),
                                              borderRadius:
                                                  BorderRadius.circular(7),
                                            ),
                                            child: Icon(
                                              Icons.check_rounded,
                                              color: CoresApp.sucesso,
                                              size: 17,
                                            ),
                                          ),
                                          const SizedBox(width: 9),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  stage,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color:
                                                        CoresApp.textoPrincipal,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${_formatDate(taskStart)} - '
                                                  '${_formatDate(taskEnd)}',
                                                  style: TextStyle(
                                                    color: CoresApp
                                                        .textoSecundario,
                                                    fontSize: 9.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          _buildTaskStatusBadge(
                                            status,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],

                              // ==================================================
                              // RECURSOS
                              // ==================================================

                              if (excelLink.trim().isNotEmpty ||
                                  folderPath.trim().isNotEmpty) ...[
                                const SizedBox(height: 18),
                                if (ProjectArchiveDialog.acceptsFolder(
                                        folderPath) &&
                                    ProjectArchiveDialog.allowed)
                                  OutlinedButton.icon(
                                      icon: const Icon(
                                          Icons.drive_file_move_outline),
                                      label: const Text(
                                          'Mover pasta para Finalizados'),
                                      onPressed: () async {
                                        final result =
                                            await ProjectArchiveDialog.show(
                                                context,
                                                projectId: id,
                                                folder: folderPath,
                                                excel: excelLink);
                                        if (result != null && context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      }),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.folder_open_rounded,
                                      color: CoresApp.destaque,
                                      size: 17,
                                    ),
                                    SizedBox(width: 7),
                                    Text(
                                      'Recursos',
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 9),
                                LayoutBuilder(
                                  builder: (
                                    context,
                                    constraints,
                                  ) {
                                    AppAppearance.watch(context);

                                    if (constraints.maxWidth < 500) {
                                      return Column(
                                        children: [
                                          if (excelLink.trim().isNotEmpty)
                                            _buildResourceButton(
                                              icon: Icons.table_view_rounded,
                                              title: 'Arquivo Excel',
                                              subtitle: 'Abrir arquivo/link',
                                              onPressed: () =>
                                                  _openProjectResource(
                                                      excelLink, id,
                                                      field: 'excelLink'),
                                            ),
                                          if (excelLink.trim().isNotEmpty &&
                                              folderPath.trim().isNotEmpty)
                                            const SizedBox(height: 10),
                                          if (folderPath.trim().isNotEmpty)
                                            _buildResourceButton(
                                              icon: Icons.folder_rounded,
                                              title: 'Pasta do projeto',
                                              subtitle: 'Abrir pasta',
                                              onPressed: () =>
                                                  _openProjectResource(
                                                      folderPath, id,
                                                      field: 'folderPath'),
                                            ),
                                        ],
                                      );
                                    }

                                    return Row(
                                      children: [
                                        if (excelLink.trim().isNotEmpty)
                                          Expanded(
                                            child: _buildResourceButton(
                                              icon: Icons.table_view_rounded,
                                              title: 'Arquivo Excel',
                                              subtitle: 'Abrir arquivo/link',
                                              onPressed: () =>
                                                  _openProjectResource(
                                                      excelLink, id,
                                                      field: 'excelLink'),
                                            ),
                                          ),
                                        if (excelLink.trim().isNotEmpty &&
                                            folderPath.trim().isNotEmpty)
                                          const SizedBox(width: 10),
                                        if (folderPath.trim().isNotEmpty)
                                          Expanded(
                                            child: _buildResourceButton(
                                              icon: Icons.folder_rounded,
                                              title: 'Pasta do projeto',
                                              subtitle: 'Abrir pasta',
                                              onPressed: () =>
                                                  _openProjectResource(
                                                      folderPath, id,
                                                      field: 'folderPath'),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),

                    // ==================================================
                    // RODAPÉ
                    // ==================================================

                    Container(
                      padding: const EdgeInsets.fromLTRB(
                        20,
                        10,
                        20,
                        14,
                      ),
                      decoration: BoxDecoration(
                        color: CoresDashboard.tabelaCabecalho,
                        border: Border(
                          top: BorderSide(
                            color: CoresDashboard.tabelaBorda,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                            },
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 15,
                            ),
                            label: const Text('Fechar'),
                            style: TextButton.styleFrom(
                              foregroundColor: CoresApp.destaque,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  // ============================================================
  // CARD DE INFORMAÇÃO
  // ============================================================

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: CoresApp.textoPrincipal.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: CoresDashboard.tabelaBorda,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CoresApp.destaque.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: CoresApp.destaque,
              size: 17,
            ),
          ),
          const SizedBox(width: 8),
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
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
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
  // RECURSO
  // ============================================================

  Widget _buildResourceButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: CoresApp.destaque.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: CoresApp.destaque.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CoresApp.destaque.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: CoresApp.destaque,
                size: 18,
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
                      color: CoresApp.textoPrincipal,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.open_in_new_rounded,
              color: CoresApp.destaque,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // REABRIR PROJETO
  // ============================================================

  Future<void> _reopenProject(
    Map<String, dynamic> project,
  ) async {
    final id = project['id']?.toString() ?? '';

    if (id.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        AppAppearance.watch(context);
        return AlertDialog(
          backgroundColor: CoresDashboard.tabelaFundo,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CoresApp.destaqueVerde.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.undo_rounded,
                  color: CoresApp.destaqueVerde,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Reabrir trabalho?',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'O trabalho "$id" será devolvido para a lista de projetos ativos.',
            style: TextStyle(
              color: CoresApp.textoSecundario,
              fontSize: 11,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.destaqueVerde,
                foregroundColor:
                    AppPalette.foregroundOn(CoresApp.destaqueVerde),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              icon: const Icon(
                Icons.undo_rounded,
                size: 16,
              ),
              label: const Text(
                'Reabrir',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.firebaseService.reopenCompletedProject(id);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Trabalho $id reaberto com sucesso.',
          ),
          backgroundColor: CoresApp.sucesso,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao reabrir o trabalho: $e',
          ),
          backgroundColor: CoresApp.erro,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ============================================================
  // EXCLUIR DO HISTÓRICO
  // ============================================================

  Future<void> _deleteProjectFromHistory(
    Map<String, dynamic> project,
  ) async {
    final id = project['id']?.toString() ?? '';

    if (id.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        AppAppearance.watch(context);
        return AlertDialog(
          backgroundColor: CoresDashboard.tabelaFundo,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CoresApp.erro.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: CoresApp.erro,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Excluir do histórico?',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'O trabalho "$id" será excluído do histórico. '
            'Essa ação não poderá ser desfeita.',
            style: TextStyle(
              color: CoresApp.textoSecundario,
              fontSize: 11,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                foregroundColor: AppPalette.foregroundOn(CoresApp.erro),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 16,
              ),
              label: const Text(
                'Excluir',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.firebaseService.deleteCompletedProject(id);

      if (!mounted) {
        return;
      }

      setState(() {
        _expandedProjectIds.remove(id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Trabalho $id removido do histórico.',
          ),
          backgroundColor: CoresApp.sucesso,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao excluir o trabalho: $e',
          ),
          backgroundColor: CoresApp.erro,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    _timeLogStore.dispose();
    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: Cabecalho(
        selectedIndex: widget.selectedIndex,
        onSelectTab: widget.onSelectTab,
        searchQuery: '',
        onSearchChanged: (_) {},
        userName: widget.userName,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                0,
                12,
                0,
                12,
              ),
              child: StreamBuilder(
                stream: widget.firebaseService.getCompletedProjectsStream(),
                builder: (context, snapshot) {
                  AppAppearance.watch(context);
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: _cardDecoration(
                          radius: 14,
                        ),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: CoresApp.destaque,
                          ),
                        ),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: CoresDashboard.tabelaFundo,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: CoresApp.erro.withValues(alpha: 0.30),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: CoresApp.overlay.withValues(alpha: 0.18),
                              blurRadius: 18,
                              offset: const Offset(0, 7),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: CoresApp.erro.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.error_outline_rounded,
                                color: CoresApp.erro,
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Erro ao carregar trabalhos finalizados',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final List<dynamic> rawProjects = snapshot.data is List
                      ? List<dynamic>.from(
                          snapshot.data as List,
                        )
                      : <dynamic>[];

                  final allProjects = _convertProjects(
                    rawProjects,
                  );

                  final completedProjects = _filterProjects(
                    allProjects,
                  );

                  int totalSubTasks = 0;

                  for (final project in completedProjects) {
                    totalSubTasks += _getSubTasks(project).length;
                  }

                  DateTime? latestFinalized;

                  for (final project in completedProjects) {
                    final date = _parseDate(
                      project['finalizedAt'],
                    );

                    if (date == null) {
                      continue;
                    }

                    if (latestFinalized == null ||
                        date.isAfter(latestFinalized)) {
                      latestFinalized = date;
                    }
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        child: _buildPageTitle(
                          allProjects: allProjects,
                          completedProjects: completedProjects,
                          totalSubTasks: totalSubTasks,
                          latestFinalized: latestFinalized,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          child: _buildCompletedProjectsTable(
                            completedProjects,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
