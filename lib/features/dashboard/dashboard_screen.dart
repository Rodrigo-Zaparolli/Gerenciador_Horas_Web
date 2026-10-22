import 'package:gerenciador_horas/shared/widgets/recovery_error.dart';
import 'package:gerenciador_horas/domain/models/work_duration.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/core/theme/app_visuals.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:gerenciador_horas/data/services/project_update_service.dart';
import 'package:gerenciador_horas/data/services/project_status_update.dart';
import '../projects/dialogs/project_archive_dialog.dart';
import 'widgets/dashboard_alerts_modal.dart';
import '../../core/config/pilot_feature_access.dart';
import '../edesk/work_audit_dialog.dart';
import '../edesk/received_work_dialog.dart';
import '../../domain/models/deadline_alert.dart';
import 'comentario/comentario_modal.dart';
import 'package:gerenciador_horas/core/platform/timer_session_storage.dart';
import 'package:gerenciador_horas/domain/models/timer_session.dart';
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';

import 'package:gerenciador_horas/features/dashboard/widgets/central_alertas_widget.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/controle_projetos_widget.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/grafico_horas_widget.dart';
import 'widgets/monthly_hours_chart.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/progresso_projeto_widget.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/tabela_projetos_widget.dart';

import 'package:gerenciador_horas/features/projects/dialogs/project_form_dialog.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

class DashboardScreen extends StatefulWidget {
  final int selectedIndex;
  final int entryVersion;
  final ValueChanged<int> onSelectTab;
  final List<WorkFormat> workFormats;
  final ValueChanged<ProjectModel>? onProjectCompleted;
  final TimeLogStore timeLogStore;

  const DashboardScreen({
    super.key,
    required this.selectedIndex,
    this.entryVersion = 0,
    required this.onSelectTab,
    required this.workFormats,
    required this.timeLogStore,
    this.onProjectCompleted,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _filterOwner;
  String _lastFilterState = '';
  Map<String, dynamic> get _personalFilters => {
    'service': _tipoServicoSelecionado, 'start': _dataInicioFiltro?.toIso8601String(),
    'end': _dataFimFiltro?.toIso8601String(), 'group': _agrupar,
    'priority': _ordenarPrioridade, 'active': _onlyActive,
    'status': _statusFiltroDashboard, 'onlyActiveCard': _filtroApenasAtivos,
    'allProjectsCard': _filtroTodosProjetos, 'advancedService': _filterOptions.serviceType,
    'shift': _filterOptions.shift, 'date': _filterOptions.selectedDate?.toIso8601String(),
  };
  void _restorePersonalFilters() {
    _filterOwner = FirebaseAuth.instance.currentUser?.uid;
    final filters = LocalUserState.read(_filterOwner, 'filters.dashboard');
    if (filters == null) return;
    _tipoServicoSelecionado = filters['service'] is String ? filters['service'] as String : null;
    _dataInicioFiltro = DateTime.tryParse(filters['start']?.toString() ?? '');
    _dataFimFiltro = DateTime.tryParse(filters['end']?.toString() ?? '');
    _agrupar = filters['group'] is bool ? filters['group'] as bool : true;
    _ordenarPrioridade = filters['priority'] is bool ? filters['priority'] as bool : false;
    _onlyActive = filters['active'] is bool ? filters['active'] as bool : true;
    _statusFiltroDashboard = _statusList.contains(filters['status']) ? filters['status'] as String : null;
    _filtroApenasAtivos = filters['onlyActiveCard'] is bool ? filters['onlyActiveCard'] as bool : true;
    _filtroTodosProjetos = filters['allProjectsCard'] is bool ? filters['allProjectsCard'] as bool : false;
    _filterOptions.serviceType = filters['advancedService'] is String ? filters['advancedService'] as String : null;
    _filterOptions.selectedDate = DateTime.tryParse(filters['date']?.toString() ?? '');
    _filterOptions.shift = ['Todos', 'Manh\u00e3', 'Tarde'].contains(filters['shift']) ? filters['shift'] as String : 'Todos';
    _lastFilterState = jsonEncode(_personalFilters);
  }
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (_filterOwner == null || FirebaseAuth.instance.currentUser?.uid != _filterOwner) return;
    final encoded = jsonEncode(_personalFilters);
    if (encoded == _lastFilterState) return;
    _lastFilterState = encoded;
    LocalUserState.write(_filterOwner, 'filters.dashboard', _personalFilters);
  }
  void _clearPersonalFilters() => setState(() {
    _tipoServicoSelecionado = null;
    _dataInicioFiltro = null; _dataFimFiltro = null;
    _agrupar = true; _ordenarPrioridade = false; _onlyActive = true;
    _statusFiltroDashboard = null; _filtroProjetos = ''; _searchQuery = '';
    _filtroApenasAtivos = true; _filtroTodosProjetos = false;
    _filterOptions.clear();
  });

  int _updateCheckGeneration = 0;
  final Set<String> _updatingProjectStatuses = {};
  bool _updateDialogOpen = false;
  final _alertsKey = GlobalKey();

  Future<void> _checkPendingCommentUpdates({bool showEmpty = false}) async {
    final generation = ++_updateCheckGeneration;
    bool opened = false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.selectedIndex != 0 || _updateDialogOpen) return;
    try {
      final deadlines = DeadlineAlert.collect(_projects, DateTime.now());
      List<PendingProjectUpdate> pending = [];
      bool updatesUnavailable = false;
      try {
        pending =
            await ProjectUpdateService(uid).pending(_projects, DateTime.now());
      } catch (error) {
        updatesUnavailable = true;
        debugPrint('Erro ao verificar prazos de comentarios: $error');
      }
      if (!mounted ||
          generation != _updateCheckGeneration ||
          widget.selectedIndex != 0 ||
          FirebaseAuth.instance.currentUser?.uid != uid ||
          (!showEmpty && pending.isEmpty && deadlines.isEmpty) ||
          _updateDialogOpen) {
        return;
      }
      if (ModalRoute.of(context)?.isCurrent == false) return;
      _updateDialogOpen = true;
      opened = true;
      final action = await DashboardAlertsModal.show(
          context, deadlines, pending,
          updatesUnavailable: updatesUnavailable);
      if (!mounted ||
          widget.selectedIndex != 0 ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      if (action == 'requests') {
        widget.onSelectTab(7);
      } else if (action != null && action.startsWith('comment:')) {
        final id = action.substring('comment:'.length);
        final project =
            pending.firstWhere((entry) => entry.project.id == id).project;
        ComentarioModal.show(context, project);
      } else if (action == 'alerts') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = _alertsKey.currentContext;
          if (mounted && widget.selectedIndex == 0 && target != null) {
            Scrollable.ensureVisible(target,
                duration: const Duration(milliseconds: 250));
          }
        });
      }
    } catch (error) {
      debugPrint('Erro ao verificar prazos de comentarios: $error');
    } finally {
      if (opened) _updateDialogOpen = false;
    }
  }

  // ============================================================
  // ESTADO DO DASHBOARD
  // ============================================================

  bool _onlyActive = true;
  bool _agrupar = true;
  bool _ordenarPrioridade = false;
  String _searchQuery = '';

  // ============================================================
  // FOTO DE PERFIL
  // ============================================================


  // ============================================================
  // FILTROS
  // ============================================================

  String? _tipoServicoSelecionado;
  String _filtroProjetos = '';
  DateTime? _dataInicioFiltro;
  DateTime? _dataFimFiltro;
  String? _statusFiltroDashboard;
  bool _filtroApenasAtivos = true;
  bool _filtroTodosProjetos = false;

  // ============================================================
  // PROJETOS
  // ============================================================

  final Set<String> _expandedProjectIds = {};

  bool _showPostStopButton = false;
  bool _isLoadingProjects = true;

  // ============================================================
  // SCROLLS
  // ============================================================

  final ScrollController _verticalTableScroll = ScrollController();
  final ScrollController _horizontalTableScroll = ScrollController();

  // ============================================================
  // FILTROS AVANÇADOS
  // ============================================================

  final FilterOptions _filterOptions = FilterOptions();

  String? _selectedTargetId;

  final List<String> _statusList = [
    'INI_PRO',
    'TRAB',
    'EA',
    'TRAB_STOP',
    'TRAB_FIM',
  ];

  // ============================================================
  // DADOS
  // ============================================================

  List<ProjectModel> _projects = [];
  List<WorkFormat> _workFormatsFirebase = [];

  final FirebaseService _firebaseService = FirebaseService();

  List<TimeLog> get _timeLogs => widget.timeLogStore.logs;

  // ============================================================
  // CRONÔMETRO
  // ============================================================

  String? _activeTimerTargetId;
  DateTime? _activeStartTime;

  // Momento em que o segmento atual de trabalho começou.
  //
  // Exemplo:
  // 14:00 começa
  // 15:00 pausa
  // 15:30 retoma
  // 16:00 para
  //
  // O primeiro segmento é 14:00 -> 15:00.
  // O segundo é 15:30 -> 16:00.
  DateTime? _segmentStartTime;

  // Total de segundos efetivamente trabalhados antes
  // do segmento atual.
  //
  // O tempo em pausa nunca entra aqui.
  int _accumulatedWorkedSeconds = 0;

  TimerState _timerState = TimerState.stopped;

  Timer? _timer;
  bool _timerRestored = false;
  bool _stoppingTimer = false;
  int _secondsElapsed = 0;

  // ============================================================
  // INPUT DECORATION
  // ============================================================

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: CoresApp.textoSecundario,
      ),
      filled: true,
      fillColor: CoresDashboard.fundoSecundario,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: CoresApp.borda,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: CoresApp.borda,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: CoresApp.primaria,
          width: 1.5,
        ),
      ),
      isDense: true,
    );
  }

  // ============================================================
  // CRIAÇÃO DO TIME LOG
  // ============================================================

  TimeLog _createTimeLog({
    required String targetId,
    required DateTime date,
    required String startTime,
    required String endTime,
    required String durationFormatted,
    required bool isRegistered,
  }) {
    String? projectName;
    String? taskName;
    String? typeHs;

    final project = _projects.cast<ProjectModel?>().firstWhere(
          (p) => p!.id == targetId,
          orElse: () => null,
        );

    if (project != null) {
      projectName = project.client;
      taskName = project.stage;
      typeHs = project.hourType;
    } else if (targetId.contains('_')) {
      final parts = targetId.split('_');

      if (parts.length >= 2) {
        final projectId = parts.first;
        final subId = parts.sublist(1).join('_');

        final parent = _projects.cast<ProjectModel?>().firstWhere(
              (p) => p!.id == projectId,
              orElse: () => null,
            );

        if (parent != null) {
          projectName = parent.client;

          final task = parent.subTasks?.cast<TaskModel?>().firstWhere(
                (t) => t!.subId == subId,
                orElse: () => null,
              );

          taskName = task?.stage ?? 'Etapa $subId';
          typeHs = task?.hourType ?? parent.hourType;
        }
      }
    }

    return TimeLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      targetId: targetId,
      date: date,
      startTime: startTime,
      endTime: endTime,
      durationFormatted: durationFormatted,
      isRegistered: isRegistered,
      projectName: projectName,
      taskName: taskName,
      typeHs: typeHs,
      hours: null,
      description: null,
    );
  }

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _restorePersonalFilters();
    widget.timeLogStore.addListener(_onTimeLogsChanged);

    _loadDataFromFirebase(showLoader: true, checkCommentUpdates: true);
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeLogStore != widget.timeLogStore) {
      oldWidget.timeLogStore.removeListener(_onTimeLogsChanged);
      widget.timeLogStore.addListener(_onTimeLogsChanged);
    }
    if (widget.selectedIndex == 0 &&
        (oldWidget.selectedIndex != 0 ||
            oldWidget.entryVersion != widget.entryVersion)) {
      _loadDataFromFirebase(checkCommentUpdates: true);
    }
  }

  void _onTimeLogsChanged() {
    if (mounted && context.mounted) setState(() {});
  }

  // ============================================================
  // FOTO DE PERFIL
  // ============================================================

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _timer?.cancel();
    widget.timeLogStore.removeListener(_onTimeLogsChanged);

    _verticalTableScroll.dispose();
    _horizontalTableScroll.dispose();

    super.dispose();
  }

  // ============================================================
  // FIREBASE
  // ============================================================

  Future<void> _loadDataFromFirebase({
    bool showLoader = false,
    bool checkCommentUpdates = false,
  }) async {
    final visit = widget.entryVersion;
    if (showLoader) {
      setState(() {
        _isLoadingProjects = true;
      });
    }

    try {
      final results = await Future.wait([
        _firebaseService.getProjects(),
        _firebaseService.getWorkFormats(),
      ]);

      final loadedProjects = results[0] as List<ProjectModel>;
      final loadedWorkFormats = results[1] as List<WorkFormat>;

      final projectIds = loadedProjects
          .map((project) => project.id.trim())
          .where((id) => id.isNotEmpty)
          .toList();

      await widget.timeLogStore.startListeningToProjects(projectIds);

      if (!mounted || !context.mounted) {
        return;
      }

      setState(() {
        _projects = loadedProjects;
        _workFormatsFirebase = loadedWorkFormats;
        _isLoadingProjects = false;

        if (_projects.isNotEmpty && _selectedTargetId == null) {
          _selectedTargetId = _projects.first.id;
        }
      });
      _restoreTimerSession();
      if (checkCommentUpdates && visit == widget.entryVersion) {
        unawaited(_checkPendingCommentUpdates());
      }
    } catch (e) {
      if (!mounted || !context.mounted) {
        return;
      }

      setState(() {
        _isLoadingProjects = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(recoveryError(e, operation: 'carregar os projetos')),
          action: SnackBarAction(label: 'Tentar novamente', onPressed: () => _loadDataFromFirebase(showLoader: true)),
          backgroundColor: CoresApp.erro,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ============================================================
  // LOCALIZAR PROJETO/TAREFA PELO TARGET ID
  // ============================================================

  ProjectModel? _findProjectByTargetId(String targetId) {
    final projectId = targetId.split('_').first;

    for (final project in _projects) {
      if (project.id == projectId) {
        return project;
      }
    }

    return null;
  }

  TaskModel? _findTaskByTargetId(
    String targetId,
    ProjectModel project,
  ) {
    if (!targetId.contains('_')) {
      return null;
    }

    final projectId = targetId.split('_').first;

    if (project.id != projectId) {
      return null;
    }

    final subId = targetId.substring(projectId.length + 1);

    for (final task in project.subTasks ?? <TaskModel>[]) {
      if (task.subId == subId) {
        return task;
      }
    }

    return null;
  }

  // ============================================================
  // ATUALIZAR STATUS DO ALVO DO CRONÔMETRO
  // ============================================================

  Future<void> _setTimerTargetStatus(
    String targetId,
    String status,
  ) async {
    final project = _findProjectByTargetId(targetId);

    if (project == null) {
      return;
    }

    if (targetId == project.id) {
      project.status = status;
    } else {
      final task = _findTaskByTargetId(
        targetId,
        project,
      );

      if (task == null) {
        return;
      }

      task.status = status;
    }

    await _firebaseService.saveProject(project);
  }

  // ============================================================
  // CRONÔMETRO
  // ============================================================

  /// Inicia o ticker visual do cronômetro.
  ///
  /// A contagem continua baseada em DateTime, preservando o comportamento
  /// original e evitando acumular o período em que o trabalho ficou pausado.
  void _saveTimerSession() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    final target = _activeTimerTargetId;
    final started = _activeStartTime;
    writeTimerSession(
        userId,
        target == null || started == null
            ? null
            : TimerSession(
                targetId: target,
                startedAt: started,
                segmentStartedAt: _segmentStartTime,
                accumulatedSeconds: _accumulatedWorkedSeconds,
              ));
  }

  void _restoreTimerSession() {
    if (_timerRestored) return;
    _timerRestored = true;
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    final session = readTimerSession(userId);
    if (session == null) return;
    final project = _findProjectByTargetId(session.targetId);
    if (project == null ||
        (session.targetId.contains('_') &&
            _findTaskByTargetId(session.targetId, project) == null)) {
      writeTimerSession(userId, null);
      return;
    }
    setState(() {
      _activeTimerTargetId = session.targetId;
      _selectedTargetId = session.targetId;
      _activeStartTime = session.startedAt;
      _segmentStartTime = session.segmentStartedAt;
      _accumulatedWorkedSeconds = session.accumulatedSeconds;
      _secondsElapsed = session.elapsedSeconds(DateTime.now());
      _timerState = session.running ? TimerState.running : TimerState.paused;
    });
    if (session.running) _startTimerTicker();
  }

  void _startTimerTicker() {
    _saveTimerSession();
    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted || !context.mounted) {
          timer.cancel();
          return;
        }

        if (_timerState != TimerState.running || _segmentStartTime == null) {
          return;
        }

        final now = DateTime.now();
        final currentSegmentSeconds =
            now.difference(_segmentStartTime!).inSeconds;

        setState(() {
          _secondsElapsed = _accumulatedWorkedSeconds + currentSegmentSeconds;
        });
      },
    );
  }

  Future<void> _startTimer(String targetId) async {
    if (_stoppingTimer) return;
    // ----------------------------------------------------------
    // NOVO TRABALHO
    // ----------------------------------------------------------

    if (_activeTimerTargetId != targetId) {
      if (_activeTimerTargetId != null) {
        await _stopTimer();
        if (!mounted || _activeTimerTargetId != null) return;
      }

      final now = DateTime.now();

      _activeTimerTargetId = targetId;
      _activeStartTime = now;
      _segmentStartTime = now;
      _accumulatedWorkedSeconds = 0;
      _secondsElapsed = 0;
      _timerState = TimerState.running;
      _showPostStopButton = false;

      _startTimerTicker();

      unawaited(
        _setTimerTargetStatus(
          targetId,
          'TRAB',
        ),
      );

      setState(() {});

      return;
    }

    // ----------------------------------------------------------
    // MESMO TRABALHO — RETOMAR APÓS PAUSA
    // ----------------------------------------------------------

    if (_timerState == TimerState.paused) {
      final now = DateTime.now();

      _segmentStartTime = now;
      _timerState = TimerState.running;
      _showPostStopButton = false;

      _startTimerTicker();

      unawaited(
        _setTimerTargetStatus(
          targetId,
          'TRAB',
        ),
      );

      setState(() {});

      return;
    }

    // ----------------------------------------------------------
    // JÁ ESTÁ RODANDO
    // ----------------------------------------------------------

    if (_timerState == TimerState.running) {
      return;
    }

    // ----------------------------------------------------------
    // CASO GERAL — INICIAR
    // ----------------------------------------------------------

    final now = DateTime.now();

    _activeTimerTargetId = targetId;
    _activeStartTime ??= now;
    _segmentStartTime = now;
    _accumulatedWorkedSeconds = 0;
    _secondsElapsed = 0;
    _timerState = TimerState.running;
    _showPostStopButton = false;

    _startTimerTicker();

    unawaited(
      _setTimerTargetStatus(
        targetId,
        'TRAB',
      ),
    );

    setState(() {});
  }

  // ============================================================
  // PAUSAR CRONÔMETRO
  // ============================================================

  void _pauseTimer() {
    if (_activeTimerTargetId == null) {
      return;
    }

    if (_timerState != TimerState.running) {
      return;
    }

    final now = DateTime.now();

    // ----------------------------------------------------------
    // FECHA O SEGMENTO ATUAL
    // ----------------------------------------------------------

    if (_segmentStartTime != null) {
      final currentSegmentSeconds =
          now.difference(_segmentStartTime!).inSeconds;

      if (currentSegmentSeconds > 0) {
        _accumulatedWorkedSeconds += currentSegmentSeconds;
      }
    }

    // O valor exibido passa a representar somente o tempo
    // realmente trabalhado.
    _secondsElapsed = _accumulatedWorkedSeconds;

    _segmentStartTime = null;

    _timer?.cancel();
    _timer = null;

    _timerState = TimerState.paused;
    _saveTimerSession();

    final targetId = _activeTimerTargetId!;

    setState(() {});

    // ----------------------------------------------------------
    // PERSISTIR TRAB_STOP NO FIRESTORE
    // ----------------------------------------------------------

    unawaited(
      _setTimerTargetStatus(
        targetId,
        'TRAB_STOP',
      ),
    );
  }

  // ============================================================
  // FINALIZAR CRONÔMETRO
  // ============================================================

  Future<void> _stopTimer() async {
    if (_stoppingTimer) return;
    _stoppingTimer = true;
    try {
      _timer?.cancel();
      _timer = null;

      if (_activeTimerTargetId != null) {
        final targetId = _activeTimerTargetId!;
        final endTime = DateTime.now();

        final startTime = _activeStartTime ?? endTime;

        // --------------------------------------------------------
        // CALCULAR O TEMPO REALMENTE TRABALHADO
        // --------------------------------------------------------

        int totalSeconds = _accumulatedWorkedSeconds;

        // Se ainda estava trabalhando, fecha o último segmento.
        //
        // Se estava pausado, _segmentStartTime é null e nenhum
        // segundo do período pausado será contabilizado.
        if (_timerState == TimerState.running && _segmentStartTime != null) {
          final currentSegmentSeconds =
              endTime.difference(_segmentStartTime!).inSeconds;

          if (currentSegmentSeconds > 0) {
            totalSeconds += currentSegmentSeconds;
          }
        }

        // Segurança para impedir valores negativos.
        if (totalSeconds < 0) {
          totalSeconds = 0;
        }

        // --------------------------------------------------------
        // HORÁRIOS
        // --------------------------------------------------------

        final startFormatted = '${startTime.hour.toString().padLeft(2, '0')}:'
            '${startTime.minute.toString().padLeft(2, '0')}';

        final endFormatted = '${endTime.hour.toString().padLeft(2, '0')}:'
            '${endTime.minute.toString().padLeft(2, '0')}';

        // --------------------------------------------------------
        // NÃO CRIAR APONTAMENTO VAZIO
        // --------------------------------------------------------

        if (totalSeconds > 0) {
          final durationFormatted = _formatDuration(
            totalSeconds,
          );

          final log = _createTimeLog(
            targetId: targetId,
            date: startTime,
            startTime: startFormatted,
            endTime: endFormatted,
            durationFormatted: durationFormatted,
            isRegistered: false,
          );
          // Retrying after a connection failure updates the same time entry.
          log.id = 'timer_${startTime.microsecondsSinceEpoch}_$targetId';

          try {
            final projectId = targetId.split('_').first;

            final logId = await widget.timeLogStore.addFirebaseLog(
              projectId,
              log,
            );

            log.id = logId;
            widget.timeLogStore.add(log);

            if (mounted && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Tempo de trabalho salvo: $durationFormatted.',
                  ),
                  backgroundColor: CoresApp.sucesso,
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }
          } catch (e) {
            if (mounted && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Erro ao salvar o tempo no Firebase: $e',
                  ),
                  backgroundColor: CoresApp.erro,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }
            _accumulatedWorkedSeconds = totalSeconds;
            _segmentStartTime = null;
            _timerState = TimerState.paused;
            _secondsElapsed = totalSeconds;
            _saveTimerSession();
            if (mounted && context.mounted) setState(() {});
            return;
          }
        }

        // --------------------------------------------------------
        // IMPORTANTE:
        //
        // Ao parar definitivamente, não deixamos TRAB_STOP
        // como estado do projeto caso o trabalho tenha sido
        // encerrado.
        //
        // Voltamos para TRAB somente se o item estava pausado.
        // Isso evita deixar um projeto permanentemente marcado
        // como pausado depois que o apontamento foi encerrado.
        // --------------------------------------------------------

        if (_timerState == TimerState.paused) {
          unawaited(
            _setTimerTargetStatus(
              targetId,
              'TRAB',
            ),
          );
        }
      }

      // ----------------------------------------------------------
      // RESET DO CRONÔMETRO
      // ----------------------------------------------------------

      if (!mounted || !context.mounted) {
        return;
      }

      setState(() {
        _timerState = TimerState.stopped;
        _activeTimerTargetId = null;
        _activeStartTime = null;
        _segmentStartTime = null;
        _accumulatedWorkedSeconds = 0;
        _secondsElapsed = 0;
        _showPostStopButton = true;
      });
      _saveTimerSession();
    } finally {
      _stoppingTimer = false;
    }
  }

  // ============================================================
  // FORMATAÇÃO
  // ============================================================

  String _formatDuration(int seconds) {
    final hours = (seconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');

    return '$hours:$minutes';
  }

  double _parseTimeToHours(String value) => (WorkDuration.parse(value) ?? 0) / 60;

  String _formatHours(double hours) => WorkDuration.format((hours * 60).round());

  String _formatDateShort(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year.toString().substring(2)}';
  }

  // ============================================================
  // HORAS POR DATA
  // ============================================================

  double _getHoursForDate(DateTime targetDate) {
    double totalHours = 0.0;

    for (final log in _timeLogs.where((l) => l.isRegistered)) {
      if (log.date.year == targetDate.year &&
          log.date.month == targetDate.month &&
          log.date.day == targetDate.day) {
        totalHours += WorkDuration.minutes(log) / 60;
      }
    }

    return totalHours;
  }

  // ============================================================
  // HORAS DO DIA
  // ============================================================

  Future<void> _abrirHorasDoDia(DateTime data) async {
    final logsDoDia = _timeLogs.where((log) {
      if (!log.isRegistered) {
        return false;
      }

      return log.date.year == data.year &&
          log.date.month == data.month &&
          log.date.day == data.day;
    }).toList();

    logsDoDia.sort((a, b) {
      int minutos(TimeLog log) {
        final partes = log.startTime.split(':');

        if (partes.length != 2) {
          return 0;
        }

        final hora = int.tryParse(partes[0]) ?? 0;
        final minuto = int.tryParse(partes[1]) ?? 0;

        return hora * 60 + minuto;
      }

      return minutos(a).compareTo(minutos(b));
    });

    int totalMinutos = 0;

    for (final log in logsDoDia) {
      totalMinutos += WorkDuration.minutes(log);
    }

    final totalHoras = _formatHours(totalMinutos / 60.0);

    final dataFormatada = '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year}';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: CoresApp.borda,
            ),
          ),
          titlePadding: const EdgeInsets.fromLTRB(
            20,
            18,
            20,
            10,
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            20,
            4,
            20,
            12,
          ),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppPalette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.access_time_rounded,
                  color: AppPalette.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Horas cadastradas',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dataFormatada,
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 12,
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
                  color: AppPalette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppPalette.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  totalHoras,
                  style: TextStyle(
                    color: AppPalette.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 650,
            height: 430,
            child: logsDoDia.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppPalette.text.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.access_time_outlined,
                            color: AppPalette.secondary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Nenhum apontamento cadastrado',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Não existem horas registradas para este dia.',
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: CoresApp.borda.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.list_alt_rounded,
                              color: CoresApp.destaque,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${logsDoDia.length} apontamento(s)',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Total: $totalHoras',
                              style: TextStyle(
                                color: AppPalette.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          itemCount: logsDoDia.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final log = logsDoDia[index];

                            final projeto = (log.projectName ?? '').trim();
                            final tarefa = (log.taskName ?? '').trim();
                            final descricao = (log.description ?? '').trim();
                            final tipo = (log.typeHs ?? '').trim();

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: CoresDashboard.fundoSecundario,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: CoresApp.borda.withValues(alpha: 0.7),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color:
                                          AppPalette.primary.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Icon(
                                      Icons.schedule_rounded,
                                      color: AppPalette.primary,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tarefa.isNotEmpty
                                              ? tarefa
                                              : 'Tarefa não informada',
                                          style: TextStyle(
                                            color: CoresApp.textoPrincipal,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          projeto.isNotEmpty
                                              ? projeto
                                              : 'Projeto não informado',
                                          style: TextStyle(
                                            color: CoresApp.textoSecundario,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (descricao.isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            descricao,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: CoresApp.textoSecundario,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 7),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.access_time_rounded,
                                              color: AppPalette.primary,
                                              size: 14,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${log.startTime} até ${log.endTime}',
                                              style: TextStyle(
                                                color: AppPalette.secondary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFF0099FF,
                                                ).withValues(alpha: 0.10),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                log.durationFormatted,
                                                style: TextStyle(
                                                  color: AppPalette.primary,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            if (tipo.isNotEmpty) ...[
                                              const SizedBox(width: 7),
                                              Text(
                                                tipo,
                                                style: TextStyle(
                                                  color:
                                                      CoresApp.textoSecundario,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  PopupMenuButton<String>(
                                    tooltip: 'Opções',
                                    color: CoresDashboard.card,
                                    icon: Icon(
                                      Icons.more_vert_rounded,
                                      color: CoresApp.textoSecundario,
                                      size: 19,
                                    ),
                                    onSelected: (value) async {
                                      Navigator.of(dialogContext).pop();

                                      if (value == 'editar') {
                                        await _editLogDialog(log);
                                        await _abrirHorasDoDia(data);
                                      } else if (value == 'excluir') {
                                        await _confirmDeleteLog(log);
                                        await _abrirHorasDoDia(data);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem<String>(
                                        value: 'editar',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.edit_outlined,
                                              color: CoresApp.destaque,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Editar',
                                              style: TextStyle(
                                                color: CoresApp.textoPrincipal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'excluir',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.delete_outline,
                                              color: CoresApp.erro,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Excluir',
                                              style: TextStyle(
                                                color: CoresApp.textoPrincipal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.primaria,
                foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text(
                'Fechar',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // SELEÇÃO DE DATA
  // ============================================================

  Future<DateTime?> _selectCustomDate(DateTime initialDate) async {
    int day = initialDate.day;
    int month = initialDate.month;
    int year = initialDate.year;

    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            AppAppearance.watch(context);
            return AlertDialog(
              backgroundColor: AppPalette.field,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: AppPalette.text.withValues(alpha: 0.16),
                ),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    color: Color(0xFF35D27F),
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Selecionar Data',
                    style: TextStyle(
                      color: AppPalette.text,
                      fontSize: 15,
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
                    _buildDateDropdown(
                      label: 'Dia',
                      value: day,
                      values: List.generate(31, (index) => index + 1),
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() => day = value);
                        }
                      },
                      padLeft: true,
                    ),
                    Text(
                      '/',
                      style: TextStyle(
                        color: AppPalette.text,
                        fontSize: 20,
                      ),
                    ),
                    _buildDateDropdown(
                      label: 'Mês',
                      value: month,
                      values: List.generate(12, (index) => index + 1),
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() => month = value);
                        }
                      },
                      padLeft: true,
                    ),
                    Text(
                      '/',
                      style: TextStyle(
                        color: AppPalette.text,
                        fontSize: 20,
                      ),
                    ),
                    _buildDateDropdown(
                      label: 'Ano',
                      value: year,
                      values: List.generate(11, (index) => 2020 + index),
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() => year = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: AppPalette.secondary,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF35D27F),
                    foregroundColor: AppPalette.foregroundOn(const Color(0xFF35D27F)),
                  ),
                  onPressed: () {
                    final novaData = DateTime(
                      year,
                      month,
                      day,
                    );

                    Navigator.of(dialogContext).pop(novaData);
                  },
                  child: const Text(
                    'Confirmar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDateDropdown({
    required String label,
    required int value,
    required List<int> values,
    required ValueChanged<int?> onChanged,
    bool padLeft = false,
  }) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 5),
          DropdownButton<int>(
            value: value,
            dropdownColor: AppPalette.field,
            style: TextStyle(
              color: AppPalette.text,
              fontSize: 16,
            ),
            items: values.map((item) {
              return DropdownMenuItem<int>(
                value: item,
                child: Text(
                  padLeft ? item.toString().padLeft(2, '0') : item.toString(),
                ),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EDITAR SUBTRABALHO
  // ============================================================

  void _editSubTaskDialog(
    ProjectModel project,
    TaskModel task,
  ) {
    final subIdController = TextEditingController(text: task.subId);
    final stageController = TextEditingController(text: task.stage);
    final serviceTypeController =
        TextEditingController(text: project.serviceType);
    final hoursController = TextEditingController(text: task.estimatedHours);
    final hourTypeController = TextEditingController(text: task.hourType);

    DateTime startDate = task.startDate;
    DateTime endDate = task.planEnd ?? task.startDate;

    showDialog(
      context: context,
      builder: (context) {
        AppAppearance.watch(context);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            AppAppearance.watch(context);
            return AlertDialog(
              backgroundColor: CoresDashboard.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: CoresApp.borda,
                ),
              ),
              title: Text(
                'Editar Subtrabalho (Etapa ${task.subId})',
                style: TextStyle(
                  fontSize: 16,
                  color: CoresApp.textoPrincipal,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: subIdController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Número (Nº)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: serviceTypeController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Tipo de Serviço'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stageController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Trabalho / Etapa'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hoursController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration(
                        'Horas Estimadas (ex: 10:00)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hourTypeController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration(
                        'Tipo de Horas (ex: Hs Cobradas)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: CoresDashboard.fundoSecundario,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: CoresApp.bordaSuave,
                                ),
                              ),
                            ),
                            icon: Icon(
                              Icons.calendar_today,
                              color: CoresApp.destaque,
                              size: 16,
                            ),
                            label: Text(
                              'Início: ${_formatDateShort(startDate)}',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () async {
                              final DateTime? picked =
                                  await _selectCustomDate(endDate);

                              if (picked != null) {
                                setDialogState(() {
                                  endDate = picked;
                                });
                              }

                              if (picked != null) {
                                setDialogState(() {
                                  startDate = picked;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: CoresDashboard.fundoSecundario,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: CoresApp.bordaSuave,
                                ),
                              ),
                            ),
                            icon: Icon(
                              Icons.calendar_today,
                              color: CoresApp.destaque,
                              size: 16,
                            ),
                            label: Text(
                              'Fim: ${_formatDateShort(endDate)}',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () async {
                              // CORREÇÃO APLICADA AQUI:
                              // Passa e atualiza a endDate em vez da startDate
                              final DateTime? picked = await _selectCustomDate(
                                endDate,
                              );

                              if (picked != null) {
                                setDialogState(() {
                                  endDate = picked;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    setState(() {
                      task.subId = subIdController.text.trim();
                      task.stage = stageController.text.trim();
                      task.estimatedHours = hoursController.text.trim();
                      task.hourType = hourTypeController.text.trim();

                      task.startDate = startDate;
                      task.planStart = startDate;
                      task.planEnd = endDate; // Salva o fim corretamente
                    });

                    await _firebaseService.saveProject(
                      project,
                    );

                    if (mounted && context.mounted) {
                      Navigator.of(context).pop();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Subtrabalho atualizado com sucesso!',
                          ),
                          backgroundColor: CoresApp.sucesso,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'Salvar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // ADICIONAR NOVA ETAPA
  // ============================================================

  void _addNewTaskDialog(ProjectModel project) {
    final subIdController = TextEditingController(
      text: ((project.subTasks?.length ?? 0) + 1).toString(),
    );

    final stageController = TextEditingController();

    final serviceTypeController =
        TextEditingController(text: project.serviceType);

    final hoursController = TextEditingController(text: '10:00');

    final hourTypeController = TextEditingController(text: project.hourType);

    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 15));

    showDialog(
      context: context,
      builder: (context) {
        AppAppearance.watch(context);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            AppAppearance.watch(context);
            return AlertDialog(
              backgroundColor: CoresDashboard.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: CoresApp.borda,
                ),
              ),
              title: Text(
                'Adicionar Nova Etapa ao Projeto ${project.id}',
                style: TextStyle(
                  fontSize: 16,
                  color: CoresApp.textoPrincipal,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: subIdController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration(
                        'Número da Etapa (Nº)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stageController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Trabalho / Etapa'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: serviceTypeController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Tipo de Serviço'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hoursController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration(
                        'Horas Estimadas (ex: 10:00)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hourTypeController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Tipo de Horas'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: CoresDashboard.fundoSecundario,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: CoresApp.bordaSuave,
                                ),
                              ),
                            ),
                            icon: Icon(
                              Icons.calendar_today,
                              color: CoresApp.destaque,
                              size: 16,
                            ),
                            label: Text(
                              'Início: ${_formatDateShort(startDate)}',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () async {
                              final DateTime? picked = await _selectCustomDate(
                                startDate,
                              );

                              if (picked != null) {
                                setDialogState(() {
                                  startDate = picked;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: CoresDashboard.fundoSecundario,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: CoresApp.bordaSuave,
                                ),
                              ),
                            ),
                            icon: Icon(
                              Icons.calendar_today,
                              color: CoresApp.destaque,
                              size: 16,
                            ),
                            label: Text(
                              'Fim: ${_formatDateShort(endDate)}',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () async {
                              final DateTime? picked = await _selectCustomDate(
                                startDate,
                              );

                              if (picked != null) {
                                setDialogState(() {
                                  startDate = picked;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    final stageName = stageController.text.trim();

                    if (stageName.isEmpty) {
                      return;
                    }

                    setState(() {
                      project.subTasks ??= [];

                      project.subTasks!.add(
                        TaskModel(
                          subId: subIdController.text.trim().isNotEmpty
                              ? subIdController.text.trim()
                              : (project.subTasks!.length + 1).toString(),
                          stage: stageName,
                          status: 'INI_PRO',
                          startDate: startDate,
                          planStart: startDate,
                          planEnd: endDate,
                          estimatedHours: hoursController.text.trim(),
                          hourType: hourTypeController.text.trim(),
                        ),
                      );

                      _expandedProjectIds.add(project.id);
                    });

                    await _firebaseService.saveProject(
                      project,
                    );

                    if (mounted && context.mounted) {
                      Navigator.of(context).pop();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Etapa "$stageName" adicionada com sucesso!',
                          ),
                          backgroundColor: CoresApp.sucesso,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'Adicionar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // HORAS MANUAIS
  // ============================================================

  Future<void> _showManualTimeDialog(
    String itemTitle,
  ) async {
    final hoursController = TextEditingController();
    final minutesController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: CoresApp.borda,
            ),
          ),
          title: Text(
            'Adicionar Horas Manualmente\n($itemTitle)',
            style: TextStyle(
              fontSize: 16,
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: hoursController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Horas'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: minutesController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Minutos'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.primaria,
                foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final h = int.tryParse(hoursController.text.trim()) ?? 0;
                final m = int.tryParse(minutesController.text.trim()) ?? 0;

                if (h <= 0 && m <= 0) {
                  return;
                }

                final now = DateTime.now();

                final durationFormatted = '${h.toString().padLeft(2, '0')}:'
                    '${m.toString().padLeft(2, '0')}';

                final startFormatted = '${now.hour.toString().padLeft(2, '0')}:'
                    '${now.minute.toString().padLeft(2, '0')}';

                final endDateTime = now.add(
                  Duration(
                    hours: h,
                    minutes: m,
                  ),
                );

                final endFormatted =
                    '${endDateTime.hour.toString().padLeft(2, '0')}:'
                    '${endDateTime.minute.toString().padLeft(2, '0')}';

                final targetId = _selectedTargetId ??
                    (_projects.isNotEmpty ? _projects.first.id : 'Geral');

                final log = _createTimeLog(
                  targetId: targetId,
                  date: now,
                  startTime: startFormatted,
                  endTime: endFormatted,
                  durationFormatted: durationFormatted,
                  isRegistered: true,
                );

                try {
                  final projectId = targetId.split('_').first;

                  final logId = await widget.timeLogStore.addFirebaseLog(
                    projectId,
                    log,
                  );

                  log.id = logId;
                  widget.timeLogStore.add(log);

                  if (!mounted || !dialogContext.mounted || !context.mounted) {
                    return;
                  }

                  Navigator.of(dialogContext).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Apontado manualmente ${h}h ${m}m e salvo no Firebase!',
                      ),
                      backgroundColor: CoresApp.sucesso,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                } catch (e) {
                  if (!mounted || !dialogContext.mounted || !context.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao salvar apontamento manual: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              },
              child: const Text(
                'Salvar',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    hoursController.dispose();
    minutesController.dispose();
  }

  // ============================================================
// EDITAR APONTAMENTO (CORRIGIDO)
// ============================================================

  Future<void> _editLogDialog(TimeLog log) async {
    final startController = TextEditingController(text: log.startTime);
    final endController = TextEditingController(text: log.endTime);
    final durationController =
        TextEditingController(text: log.durationFormatted);
    final descriptionController =
        TextEditingController(text: log.description ?? '');

    void calculateDuration() {
      final startParts = startController.text.split(':');
      final endParts = endController.text.split(':');

      if (startParts.length == 2 && endParts.length == 2) {
        final sh = int.tryParse(startParts[0]) ?? 0;
        final sm = int.tryParse(startParts[1]) ?? 0;
        final eh = int.tryParse(endParts[0]) ?? 0;
        final em = int.tryParse(endParts[1]) ?? 0;

        int startTotalMins = (sh * 60) + sm;
        int endTotalMins = (eh * 60) + em;
        int diffMins = endTotalMins - startTotalMins;

        if (diffMins < 0) {
          diffMins += 24 * 60;
        }

        final dh = diffMins ~/ 60;
        final dm = diffMins % 60;

        durationController.text = '${dh.toString().padLeft(2, '0')}:'
            '${dm.toString().padLeft(2, '0')}';
      }
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            AppAppearance.watch(context);
            return AlertDialog(
              backgroundColor: CoresDashboard.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: CoresApp.borda,
                ),
              ),
              title: Text(
                'Editar Horário de Apontamento',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: startController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration(
                        'Hora Início (ex: 14:00)',
                      ),
                      onChanged: (_) {
                        calculateDuration();
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: endController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration(
                        'Hora Fim (ex: 15:30)',
                      ),
                      onChanged: (_) {
                        calculateDuration();
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: durationController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Duração (ex: 01:30)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      maxLines: 2,
                      decoration: _inputDecoration(
                        'Descrição / Comentário',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    // Atualiza os valores locais da instância do log
                    log.startTime = startController.text.trim();
                    log.endTime = endController.text.trim();
                    log.durationFormatted = durationController.text.trim();
                    log.description = descriptionController.text.trim().isEmpty
                        ? null
                        : descriptionController.text.trim();

                    if (_activeTimerTargetId == log.targetId) {
                      final durationParts = log.durationFormatted.split(':');

                      if (durationParts.length >= 2) {
                        final h = int.tryParse(durationParts[0]) ?? 0;
                        final m = int.tryParse(durationParts[1]) ?? 0;

                        _secondsElapsed = (h * 3600) + (m * 60);
                        _accumulatedWorkedSeconds = _secondsElapsed;

                        if (_timerState == TimerState.running) {
                          _segmentStartTime = DateTime.now();
                        }
                      }

                      final startParts = log.startTime.split(':');
                      if (startParts.length == 2) {
                        final sh = int.tryParse(startParts[0]) ?? log.date.hour;
                        final sm =
                            int.tryParse(startParts[1]) ?? log.date.minute;

                        _activeStartTime = DateTime(
                          log.date.year,
                          log.date.month,
                          log.date.day,
                          sh,
                          sm,
                        );
                      }
                    }

                    try {
                      // Garante a persistência e atualização correta no Firebase e na Store
                      await widget.timeLogStore.updateFirebaseLog(log);

                      if (!mounted || !context.mounted) return;

                      setState(
                          () {}); // Força a reconstrução do Dashboard para refletir as horas atualizadas

                      if (!mounted || !dialogContext.mounted || !context.mounted) {
                        return;
                      }

                      Navigator.of(dialogContext).pop();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Apontamento atualizado e salvo no Firebase!',
                          ),
                          backgroundColor: CoresApp.sucesso,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!mounted || !dialogContext.mounted || !context.mounted) {
                        return;
                      }

                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Erro ao atualizar apontamento: $e',
                          ),
                          backgroundColor: CoresApp.erro,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'Salvar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    startController.dispose();
    endController.dispose();
    durationController.dispose();
    descriptionController.dispose();
  }

  // ============================================================
  // EXCLUIR APONTAMENTO
  // ============================================================

  Future<void> _confirmDeleteLog(TimeLog log) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: CoresApp.borda,
            ),
          ),
          title: Text(
            'Excluir Apontamento',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Deseja realmente remover esta linha de apontamento?',
            style: TextStyle(
              color: CoresApp.textoSecundario,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                try {
                  await widget.timeLogStore.deleteFirebaseLog(log);

                  if (!mounted || !dialogContext.mounted || !context.mounted) {
                    return;
                  }

                  Navigator.of(dialogContext).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Apontamento excluído do Firebase!',
                      ),
                      backgroundColor: CoresApp.sucesso,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                } catch (e) {
                  if (!mounted || !dialogContext.mounted || !context.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao excluir apontamento: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              },
              child: Text(
                'Excluir',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // EXCLUIR PROJETO
  // ============================================================

  Future<void> _confirmDeleteProject(
    ProjectModel project,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: CoresApp.borda,
            ),
          ),
          title: Text(
            'Excluir Projeto',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Deseja realmente excluir o projeto '
            '"${project.client}" (${project.id})?',
            style: TextStyle(
              color: CoresApp.textoSecundario,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                if (_activeTimerTargetId == project.id ||
                    (_activeTimerTargetId?.startsWith(
                          '${project.id}_',
                        ) ??
                        false)) {
                  await _stopTimer();
                }

                setState(() {
                  _projects.removeWhere(
                    (p) => p.id == project.id,
                  );

                  _expandedProjectIds.remove(
                    project.id,
                  );

                  if (_selectedTargetId == project.id) {
                    _selectedTargetId = null;
                  }
                });

                try {
                  await _firebaseService.deleteProject(project.id);

                  if (!mounted || !dialogContext.mounted || !context.mounted) {
                    return;
                  }

                  Navigator.of(dialogContext).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Projeto ${project.id} removido do Firebase!',
                      ),
                      backgroundColor: CoresApp.sucesso,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                } catch (e) {
                  if (!mounted || !dialogContext.mounted || !context.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao excluir projeto: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              },
              child: Text(
                'Excluir',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // EXCLUIR SUBTAREFA
  // ============================================================

  Future<void> _confirmDeleteSubTask(
    ProjectModel project,
    TaskModel task,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: CoresApp.borda,
            ),
          ),
          title: Text(
            'Excluir Subtrabalho (Etapa)',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Deseja realmente excluir a etapa '
            '"${task.stage}" (Nº ${task.subId})?',
            style: TextStyle(
              color: CoresApp.textoSecundario,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final subTargetId = '${project.id}_${task.subId}';

                if (_activeTimerTargetId == subTargetId) {
                  await _stopTimer();
                }

                setState(() {
                  project.subTasks?.removeWhere(
                    (t) => t.subId == task.subId,
                  );

                  widget.timeLogStore.removeByTargetId(
                    subTargetId,
                  );

                  if (_selectedTargetId == subTargetId) {
                    _selectedTargetId = null;
                  }
                });

                try {
                  await _firebaseService.saveProject(project);

                  if (!mounted || !dialogContext.mounted || !context.mounted) {
                    return;
                  }

                  Navigator.of(dialogContext).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Subtrabalho excluído com sucesso!',
                      ),
                      backgroundColor: CoresApp.sucesso,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                } catch (e) {
                  if (!mounted || !dialogContext.mounted || !context.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao excluir subtrabalho: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              },
              child: Text(
                'Excluir',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // EXPANDIR PROJETO
  // ============================================================

  void _toggleExpand(String id) {
    setState(() {
      if (_expandedProjectIds.contains(id)) {
        _expandedProjectIds.remove(id);
      } else {
        _expandedProjectIds.add(id);
      }
    });
  }

  // ============================================================
// CRIAR NOVO PROJETO
// ============================================================

  Future<void> _createNewProject() async {
    final ProjectModel? newProject = await showDialog<ProjectModel>(
      context: context,
      builder: (context) {
        AppAppearance.watch(context);
        return ProjectFormDialog(
            workFormats: _workFormatsFirebase.isNotEmpty
                ? _workFormatsFirebase
                : widget.workFormats,
            firebaseService: null);
      },
    );

    if (newProject == null) {
      return;
    }

    // ============================================================
    // IMPORTANTE:
    //
    // O ProjectFormDialog já cria as subtarefas contendo exatamente
    // as datas escolhidas pelo usuário.
    //
    // Portanto, NÃO devemos recriar as tarefas aqui.
    //
    // Antes havia uma lógica que fazia:
    //
    // planEnd: newProject.startDate.add(
    //   const Duration(days: 30),
    // ),
    //
    // Isso fazia a data final escolhida pelo usuário ser perdida.
    // ============================================================

    final List<TaskModel>? projectSubTasks = newProject.subTasks;

    final ProjectModel projectWithSubtasks = ProjectModel(
      id: newProject.id,
      id2: newProject.id2,
      client: newProject.client,
      email: newProject.email,
      serviceType: newProject.serviceType,
      stage: newProject.stage,
      task: newProject.task,
      status: newProject.status,

      // Mantém exatamente a data inicial que veio do formulário.
      startDate: newProject.startDate,

      estimatedHours: newProject.estimatedHours,
      leader: newProject.leader,
      hourType: newProject.hourType,

      // ==========================================================
      // Mantém as subtarefas criadas pelo ProjectFormDialog.
      //
      // Isso preserva as datas:
      //   - startDate
      //   - planStart
      //   - planEnd
      //
      // sem alterar para +15 ou +30 dias.
      // ==========================================================
      subTasks: projectSubTasks,

      checklist: newProject.checklist,
      observacao: newProject.observacao,
      excelLink: newProject.excelLink,
      folderPath: newProject.folderPath,
    );

    // ============================================================
    // SALVAR NO FIREBASE
    // ============================================================

    await _firebaseService.saveProject(
      projectWithSubtasks,
    );

    // ============================================================
    // ATUALIZAR O DASHBOARD
    // ============================================================

    if (!mounted || !context.mounted) {
      return;
    }

    setState(() {
      _projects.add(projectWithSubtasks);

      if (projectWithSubtasks.subTasks != null &&
          projectWithSubtasks.subTasks!.isNotEmpty) {
        _expandedProjectIds.add(
          projectWithSubtasks.id,
        );
      }

      _selectedTargetId ??= projectWithSubtasks.id;
    });

    // ============================================================
    // MENSAGEM DE SUCESSO
    // ============================================================

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Projeto salvo no Firebase com sucesso!',
        ),
        backgroundColor: CoresApp.sucesso,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
  // ============================================================
  // HORAS DOS ÚLTIMOS 10 DIAS
  // ============================================================

  List<DailyHoursPoint> _buildDailyHoursPoints() {
    final now = DateTime.now();
    final points = <DailyHoursPoint>[];

    for (int i = 6; i >= 0; i--) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(
        Duration(days: i),
      );

      final isWeekend =
          date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

      points.add(
        DailyHoursPoint(
          label: '${date.day.toString().padLeft(2, '0')}/'
              '${date.month.toString().padLeft(2, '0')}',
          date: date,
          hours: _getHoursForDate(date),
          isWeekend: isWeekend,
          isHighlighted: i == 0,
        ),
      );
    }

    return points;
  }

  // ============================================================
  // PREPARAÇÃO DOS DADOS DO DASHBOARD
  // ============================================================

  List<ProjectModel> _buildFilteredProjects() {
    return _projects.where((p) {
      final query = _searchQuery.toLowerCase().trim();

      final matchesSearch = query.isEmpty ||
          p.client.toLowerCase().contains(query) ||
          p.id.toLowerCase().contains(query) ||
          p.serviceType.toLowerCase().contains(query);

      final filtroProjeto = _filtroProjetos.toLowerCase().trim();

      final matchesProjectFilter = filtroProjeto.isEmpty ||
          p.id.toLowerCase().contains(filtroProjeto) ||
          p.client.toLowerCase().contains(filtroProjeto);

      final matchesServiceType = _tipoServicoSelecionado == null ||
          _tipoServicoSelecionado!.trim().isEmpty ||
          p.serviceType.trim().toLowerCase() ==
              _tipoServicoSelecionado!.trim().toLowerCase();

      final matchesStartDate = _dataInicioFiltro == null ||
          (p.startDate.year == _dataInicioFiltro!.year &&
              p.startDate.month == _dataInicioFiltro!.month &&
              p.startDate.day == _dataInicioFiltro!.day);

      final matchesEndDate = _dataFimFiltro == null ||
          p.startDate.isBefore(
            _dataFimFiltro!.add(const Duration(days: 1)),
          );

      final matchesDateOption = _filterOptions.selectedDate == null ||
          (p.startDate.year == _filterOptions.selectedDate!.year &&
              p.startDate.month == _filterOptions.selectedDate!.month &&
              p.startDate.day == _filterOptions.selectedDate!.day);

// ============================================================
// FILTRO DOS CARDS DO DASHBOARD
// ============================================================
//
// PROJETOS CADASTRADOS:
//   Todos os projetos.
//
// PROJETOS ATIVOS:
//   Somente projetos que não estão finalizados
//   e não estão pausados.
//
// PROJETOS PAUSADOS:
//   Somente TRAB_STOP.
//
// O filtro do card tem prioridade sobre "_onlyActive".
// ============================================================

      // ============================================================
      // FILTRO DOS CARDS DO DASHBOARD
      // ============================================================
      //
      // PROJETOS CADASTRADOS:
      //   Todos os projetos.
      //
      // PROJETOS ATIVOS:
      //   Somente projetos que não estão finalizados
      //   e não estão pausados.
      //
      // PROJETOS PAUSADOS:
      //   Somente TRAB_STOP.
      //
      // O filtro do card tem prioridade sobre "_onlyActive".
      // ============================================================

      bool matchesStatus = true;

      if (_filtroTodosProjetos) {
        // ============================================================
        // TODOS OS PROJETOS
        // Ignora o filtro padrão de ativos.
        // Mantém somente os demais filtros da tela.
        // ============================================================
        matchesStatus = true;
      } else if (_filtroApenasAtivos) {
        // ============================================================
        // PROJETOS ATIVOS
        // ============================================================
        matchesStatus = p.status != 'TRAB_FIM' && p.status != 'TRAB_STOP';
      } else if (_statusFiltroDashboard != null) {
        // ============================================================
        // FILTRO POR STATUS ESPECÍFICO
        // Ex.: PROJETOS PAUSADOS = TRAB_STOP
        // ============================================================
        matchesStatus = p.status == _statusFiltroDashboard;
      } else {
        // ============================================================
        // COMPORTAMENTO ORIGINAL
        // ============================================================
        matchesStatus = _onlyActive
            ? p.status != 'TRAB_FIM' && p.status != 'TRAB_STOP'
            : true;
      }

      // ============================================================
      // FILTRO POR TURNO
      // ============================================================

      bool matchesShift = true;

      if (_filterOptions.shift == 'Manhã') {
        final logs = _timeLogs.where(
          (l) => l.targetId.split('_').first == p.id,
        );

        matchesShift = logs.any((l) {
          final hour = int.tryParse(
                l.startTime.split(':').first,
              ) ??
              0;

          return hour < 12;
        });
      } else if (_filterOptions.shift == 'Tarde') {
        final logs = _timeLogs.where(
          (l) => l.targetId.split('_').first == p.id,
        );

        matchesShift = logs.any((l) {
          final hour = int.tryParse(
                l.startTime.split(':').first,
              ) ??
              0;

          return hour >= 12 && hour < 18;
        });
      }

      return matchesSearch &&
          matchesProjectFilter &&
          matchesServiceType &&
          matchesStartDate &&
          matchesEndDate &&
          matchesDateOption &&
          matchesStatus &&
          matchesShift;
    }).toList();
  }

  ProjectModel _getActiveProject() {
    final defaultTargetId = _projects.isNotEmpty ? _projects.first.id : '';

    return _projects.firstWhere(
      (p) => p.id == (_selectedTargetId?.split('_').first ?? defaultTargetId),
      orElse: () => _projects.isNotEmpty
          ? _projects.first
          : ProjectModel(
              id: '',
              id2: '',
              client: 'Nenhum projeto',
              serviceType: '',
              stage: '',
              task: '',
              status: '',
              startDate: DateTime.now(),
              estimatedHours: '00:00',
              leader: '',
              hourType: '',
            ),
    );
  }

  // ============================================================
  // CABEÇALHO VISUAL
  // ============================================================

  Widget _buildDashboardHeader({
    required int activeProjects,
    required int totalProjects,
    required int pausedProjects,
    required int totalTasks,
    required String totalHours,
  }) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CoresDashboard.card.withValues(alpha: 0.98),
            CoresDashboard.fundoSecundario.withValues(alpha: 0.96),
          ],
        ),
        border: Border.all(
          color: CoresApp.borda.withValues(alpha: 0.9),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppPalette.dark ? 0.20 : 0.045),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: CoresApp.primaria.withValues(alpha: 0.035),
            blurRadius: 30,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  CoresApp.primaria,
                  CoresApp.destaque,
                  CoresApp.secundaria,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                AppAppearance.watch(context);
                final width = constraints.maxWidth;

                final stats = [
                  _buildDashboardStat(
                    icon: Icons.folder_open_rounded,
                    label: 'Projetos ativos',
                    value: '$activeProjects',
                    description: 'em andamento',
                    color: CoresApp.destaque,
                    filterApenasAtivos: true,
                  ),
                  _buildDashboardStat(
                    icon: Icons.folder_rounded,
                    label: 'Projetos',
                    value: '$totalProjects',
                    description: 'cadastrados',
                    color: CoresApp.primaria,
                    filterTodosProjetos: true,
                  ),
                  _buildDashboardStat(
                    icon: Icons.pause_circle_outline_rounded,
                    label: 'Projetos pausados',
                    value: '$pausedProjects',
                    description: 'parados',
                    color: CoresApp.aviso,
                    filterStatus: 'TRAB_STOP',
                  ),
                  _buildDashboardStat(
                    icon: Icons.task_alt_rounded,
                    label: 'Tarefas',
                    value: '$totalTasks',
                    description: 'etapas',
                    color: CoresApp.secundaria,
                  ),
                  _buildDashboardStat(
                    icon: Icons.schedule_rounded,
                    label: 'Horas',
                    value: totalHours,
                    description: 'registradas',
                    color: CoresApp.destaque,
                  ),
                ];

                if (width >= 1250) {
                  return Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildDashboardTitle(),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 8,
                        child: Row(
                          children: [
                            for (int i = 0; i < stats.length; i++) ...[
                              Expanded(child: stats[i]),
                              if (i < stats.length - 1)
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                }

                if (width >= 800) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDashboardTitle(),
                      const SizedBox(height: 13),
                      Row(
                        children: [
                          for (int i = 0; i < stats.length; i++) ...[
                            Expanded(child: stats[i]),
                            if (i < stats.length - 1) const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDashboardTitle(),
                    const SizedBox(height: 13),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        for (final stat in stats)
                          SizedBox(
                            width: _responsiveStatWidth(width),
                            child: stat,
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

  Widget _buildDashboardTitle() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                CoresApp.destaque,
                CoresApp.primaria,
                CoresApp.secundaria,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: CoresApp.destaque.withValues(alpha: 0.25),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 15),
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                CoresApp.primaria.withValues(alpha: 0.26),
                CoresApp.destaque.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: CoresApp.primaria.withValues(alpha: 0.34),
            ),
            boxShadow: [
              BoxShadow(
                color: CoresApp.primaria.withValues(alpha: 0.13),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(
            Icons.dashboard_customize_rounded,
            color: CoresApp.destaque,
            size: 28,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gestão de Horas e Projetos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Acompanhe projetos, etapas, horas e produtividade em um único painel.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: CoresApp.sucesso.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: CoresApp.sucesso.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: CoresApp.sucesso,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: CoresApp.sucesso.withValues(alpha: 0.45),
                      blurRadius: 7,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'PAINEL ATIVO',
                style: TextStyle(
                  color: CoresApp.sucesso,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardStat({
    required IconData icon,
    required String label,
    required String value,
    required String description,
    required Color color,
    String? filterStatus,
    bool filterApenasAtivos = false,
    bool filterTodosProjetos = false,
  }) {
    final bool isSelected = (filterApenasAtivos && _filtroApenasAtivos) ||
        (filterTodosProjetos && _filtroTodosProjetos) ||
        (filterStatus != null && _statusFiltroDashboard == filterStatus);

    final isClickable =
        filterStatus != null || filterApenasAtivos || filterTodosProjetos;

    return InkWell(
      onTap: !isClickable
          ? null
          : () {
              _toggleDashboardStatusFilter(
                status: filterStatus,
                apenasAtivos: filterApenasAtivos,
                todosProjetos: filterTodosProjetos,
              );
            },
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 70),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSelected
                ? [
                    color.withValues(alpha: 0.19),
                    color.withValues(alpha: 0.08),
                  ]
                : [
                    CoresDashboard.fundoSecundario.withValues(alpha: 0.98),
                    CoresDashboard.fundoSecundario.withValues(alpha: 0.78),
                  ],
          ),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color:
                isSelected ? color.withValues(alpha: 0.72) : color.withValues(alpha: 0.20),
            width: isSelected ? 1.25 : 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? color.withValues(alpha: 0.11)
                  : Colors.black.withValues(alpha: 0.10),
              blurRadius: isSelected ? 14 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: isSelected ? 0.24 : 0.14),
                    color.withValues(alpha: isSelected ? 0.10 : 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: color.withValues(alpha: 0.14),
                ),
              ),
              child: Icon(
                isSelected ? Icons.filter_alt_rounded : icon,
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
                          label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.45,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle_rounded,
                          color: color,
                          size: 14,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    isSelected ? 'filtro aplicado' : description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.92),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _responsiveStatWidth(double width) {
    if (width >= 700) {
      return 175;
    }

    if (width >= 500) {
      return 160;
    }

    if (width >= 360) {
      return 150;
    }

    return width;
  }

  // ============================================================
  // PAINEL SUPERIOR
  // ============================================================

  Widget _buildTopDashboardPanels({
    required ProjectModel activeProject,
    required List<DailyHoursPoint> dailyHoursPoints,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        AppAppearance.watch(context);
        final width = constraints.maxWidth;

        if (width < 1000) {
          return Column(
            children: [
              _buildDashboardPanel(
                height: 260,
                child: ControleProjetosWidget(
                  onReset: _clearPersonalFilters,
                  agrupar: _agrupar,
                  ordenarPrioridade: _ordenarPrioridade,
                  somenteAtivos: _onlyActive,
                  filtroAtivo: _filterOptions.hasFilter ||
                      (_tipoServicoSelecionado != null &&
                          _tipoServicoSelecionado!.isNotEmpty) ||
                      _filtroProjetos.isNotEmpty ||
                      _dataInicioFiltro != null ||
                      _dataFimFiltro != null ||
                      _statusFiltroDashboard != null ||
                      _filtroApenasAtivos,
                  expandedProjectIds: _expandedProjectIds,
                  onNewProject: _createNewProject,
                  onSynchronize: () {
                    _loadDataFromFirebase(
                      showLoader: false,
                    );
                  },
                  onFilter: () {},
                  onManual: () {
                    final target = _selectedTargetId ??
                        (_projects.isNotEmpty ? _projects.first.id : 'Geral');

                    _showManualTimeDialog(target);
                  },
                  onStart: () {
                    final target = _selectedTargetId ??
                        (_projects.isNotEmpty ? _projects.first.id : null);

                    if (target != null) {
                      _startTimer(target);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Selecione um trabalho na tabela para iniciar!',
                          ),
                          backgroundColor: CoresApp.aviso,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    }
                  },
                  onPause: _pauseTimer,
                  onStop: _stopTimer,
                  onAgruparChanged: (value) {
                    setState(() {
                      _agrupar = value ?? false;
                    });
                  },
                  onOrdenarPrioridadeChanged: (value) {
                    setState(() {
                      _ordenarPrioridade = value ?? false;
                    });
                  },
                  onSomenteAtivosChanged: (value) {
                    setState(() {
                      _onlyActive = value ?? false;
                    });
                  },
                  filtroProjetos: _filtroProjetos,
                  tipoServicoSelecionado: _tipoServicoSelecionado ?? '',
                  onFiltroProjetosChanged: (String? value) {
                    setState(() {
                      _filtroProjetos = value ?? '';
                    });
                  },
                  onTipoServicoChanged: (String? value) {
                    setState(() {
                      _tipoServicoSelecionado = value;
                    });
                  },
                  tiposServicoOpcoes: _getServiceTypeNames(),
                  onDataInicioChanged: (DateTime? value) {
                    setState(() {
                      _dataInicioFiltro = value;
                    });
                  },
                  onDataFimChanged: (DateTime? value) {
                    setState(() {
                      _dataFimFiltro = value;
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              _buildDashboardPanel(
                child: ProgressoProjetoWidget(
                  activeProject: activeProject,
                  timeLogs: _timeLogs,
                  parseTimeToHours: _parseTimeToHours,
                  formatHours: _formatHours,
                  formatDateShort: _formatDateShort,
                ),
              ),
              const SizedBox(height: 12),
              _buildDashboardPanel(
                child: MonthlyHoursChart(
                  logs: _timeLogs,
                  points: dailyHoursPoints,
                  formatHours: _formatHours,
                  onDayTap: _abrirHorasDoDia,
                ),
              ),
            ],
          );
        }

        return SizedBox(
          height: 260,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ========================================================
              // CONTROLE DE PROJETOS
              // ========================================================

              Expanded(
                flex: 3,
                child: _buildDashboardPanel(
                  height: 260,
                  child: ControleProjetosWidget(
                  onReset: _clearPersonalFilters,
                    agrupar: _agrupar,
                    ordenarPrioridade: _ordenarPrioridade,
                    somenteAtivos: _onlyActive,
                    filtroAtivo: _filterOptions.hasFilter ||
                        (_tipoServicoSelecionado != null &&
                            _tipoServicoSelecionado!.isNotEmpty) ||
                        _filtroProjetos.isNotEmpty ||
                        _dataInicioFiltro != null ||
                        _dataFimFiltro != null,
                    expandedProjectIds: _expandedProjectIds,
                    onNewProject: _createNewProject,
                    onSynchronize: () {
                      _loadDataFromFirebase(
                        showLoader: false,
                      );
                    },
                    onFilter: () {},
                    onManual: () {
                      final target = _selectedTargetId ??
                          (_projects.isNotEmpty ? _projects.first.id : 'Geral');

                      _showManualTimeDialog(target);
                    },
                    onStart: () {
                      final target = _selectedTargetId ??
                          (_projects.isNotEmpty ? _projects.first.id : null);

                      if (target != null) {
                        _startTimer(target);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'Selecione um trabalho na tabela para iniciar!',
                            ),
                            backgroundColor: CoresApp.aviso,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      }
                    },
                    onPause: _pauseTimer,
                    onStop: _stopTimer,
                    onAgruparChanged: (value) {
                      setState(() {
                        _agrupar = value ?? false;
                      });
                    },
                    onOrdenarPrioridadeChanged: (value) {
                      setState(() {
                        _ordenarPrioridade = value ?? false;
                      });
                    },
                    onSomenteAtivosChanged: (value) {
                      setState(() {
                        _onlyActive = value ?? false;
                      });
                    },
                    filtroProjetos: _filtroProjetos,
                    tipoServicoSelecionado: _tipoServicoSelecionado ?? '',
                    onFiltroProjetosChanged: (String? value) {
                      setState(() {
                        _filtroProjetos = value ?? '';
                      });
                    },
                    onTipoServicoChanged: (String? value) {
                      setState(() {
                        _tipoServicoSelecionado = value;
                      });
                    },
                    tiposServicoOpcoes: _getServiceTypeNames(),
                    onDataInicioChanged: (DateTime? value) {
                      setState(() {
                        _dataInicioFiltro = value;
                      });
                    },
                    onDataFimChanged: (DateTime? value) {
                      setState(() {
                        _dataFimFiltro = value;
                      });
                    },
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // ========================================================
              // ETAPAS DO PROJETO
              // ========================================================

              Expanded(
                flex: 6,
                child: _buildDashboardPanel(
                  child: ProgressoProjetoWidget(
                    activeProject: activeProject,
                    timeLogs: _timeLogs,
                    parseTimeToHours: _parseTimeToHours,
                    formatHours: _formatHours,
                    formatDateShort: _formatDateShort,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // ========================================================
              // EVOLUÇÃO DE HORAS
              // ========================================================

              Expanded(
                flex: 4,
                child: _buildDashboardPanel(
                  child: MonthlyHoursChart(
                    logs: _timeLogs,
                    points: dailyHoursPoints,
                    formatHours: _formatHours,
                    onDayTap: _abrirHorasDoDia,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDashboardPanel({
    required Widget child,
    double height = 260,
  }) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: AppVisuals.card.copyWith(boxShadow: AppVisuals.shadows),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppVisuals.cardRadius),
        child: child,
      ),
    );
  }

  List<String> _getServiceTypeNames() {
    final availableWorkFormats = _workFormatsFirebase.isNotEmpty
        ? _workFormatsFirebase
        : widget.workFormats;

    return availableWorkFormats.map((wf) => wf.name).toList();
  }

  // ============================================================
  // TABELA
  // ============================================================

  Widget _buildProjectsTable(
    List<ProjectModel> filteredProjects,
  ) {
    return Container(
      width: double.infinity,
      decoration: AppVisuals.card.copyWith(boxShadow: AppVisuals.shadows),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
              decoration: BoxDecoration(
                color: CoresDashboard.fundoSecundario.withValues(alpha: 0.42),
                border: Border(
                  bottom: BorderSide(
                    color: CoresApp.borda.withValues(alpha: 0.55),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: CoresApp.primaria.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: CoresApp.primaria.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Icon(
                      Icons.table_rows_rounded,
                      color: CoresApp.destaque,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Projetos e tarefas',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Acompanhamento operacional e registro de horas',
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: CoresApp.primaria.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: CoresApp.primaria.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      '${filteredProjects.length} ${filteredProjects.length == 1 ? 'projeto' : 'projetos'}',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (PilotFeatureAccess.allows(uid: FirebaseAuth.instance.currentUser?.uid, email: FirebaseAuth.instance.currentUser?.email))
              Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(bottom:8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => ReceivedWorkDialog.show(context),
                    icon: const Icon(Icons.move_to_inbox_outlined), label: const Text('Trabalhos recebidos')),
                  OutlinedButton.icon(onPressed: () => WorkAuditDialog.show(context, _projects),
                    icon: const Icon(Icons.fact_check_outlined), label: const Text('Conferir no E-Desk'))]))),
            TabelaProjetosWidget(
              projects: filteredProjects,
              auditProjects: _projects,
              statusList: _statusList,
              expandedProjectIds: _expandedProjectIds,
              selectedTargetId: _selectedTargetId,
              timeLogs: _timeLogs,
              activeTimerTargetId: _activeTimerTargetId,
              activeStartTime: _activeStartTime,
              timerState: _timerState,
              secondsElapsed: _secondsElapsed,
              showPostStopButton: _showPostStopButton,
              horizontalController: _horizontalTableScroll,
              verticalController: _verticalTableScroll,
              onSelectTarget: (targetId) {
                setState(() {
                  _selectedTargetId = targetId;
                });
              },
              onToggleExpand: _toggleExpand,
              onEditProject: (project) {
                setState(() {
                  final index = _projects.indexWhere((p) => p.id == project.id);
                  if (index != -1) {
                    _projects[index] = project;
                  }
                });
              },
              onDeleteProject: _confirmDeleteProject,
              onAddSubTask: _addNewTaskDialog,
              onProjectStatusChanged: _handleProjectStatusChanged,
              onSubTaskStatusChanged: _handleSubTaskStatusChanged,
              onEditSubTask: _editSubTaskDialog,
              onDeleteSubTask: _confirmDeleteSubTask,
              onStartTimer: _startTimer,
              onPauseTimer: _pauseTimer,
              onStopTimer: _stopTimer,
              onManualTime: _showManualTimeDialog,
              onEditLog: _editLogDialog,
              onDeleteLog: _confirmDeleteLog,
              onRegisterLog: _handleRegisterLog,
              onMarkTaskCompleted: _handleMarkTaskCompleted,
              formatDuration: _formatDuration,
              firebaseService: _firebaseService,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CALLBACKS DA TABELA
  // ============================================================

  Future<void> _handleProjectStatusChanged(
    ProjectModel project,
    String newStatus,
  ) async {
    final owner = FirebaseAuth.instance.currentUser?.uid;
    if (owner == null) return;
    if (!mounted || !_updatingProjectStatuses.add(project.id)) return;
    try {
      final folderMoved = await updateProjectStatus(
        project: project,
        status: newStatus,
        registerLogs: () => widget.timeLogStore.registerProjectLogs(project.id),
        persist: () async {
          if (FirebaseAuth.instance.currentUser?.uid != owner) throw StateError('A conta mudou.');
          await _firebaseService.saveProject(project);
        },
        offerArchive: () async {
          if (!mounted || !context.mounted || FirebaseAuth.instance.currentUser?.uid != owner || !ProjectArchiveDialog.allowed ||
              !ProjectArchiveDialog.acceptsFolder(project.folderPath ?? '')) {
            return false;
          }
          final result = await ProjectArchiveDialog.show(context,
            projectId: project.id, folder: project.folderPath!, excel: project.excelLink ?? '');
          if (result == null) return false;
          project.folderPath = result['folderReference'] as String;
          project.excelLink = result['excelReference'] as String;
          return true;
        },
      );

      if (newStatus == 'TRAB_FIM' && mounted && context.mounted && FirebaseAuth.instance.currentUser?.uid == owner) {
        widget.onProjectCompleted?.call(
          project,
        );

        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                folderMoved
                    ? 'Projeto ${project.id} finalizado. Pasta movida e vínculos atualizados.'
                    : 'Projeto ${project.id} finalizado.',
              ),
              backgroundColor: CoresApp.sucesso,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted && context.mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao atualizar status: $e',
            ),
            backgroundColor: CoresApp.erro,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      _updatingProjectStatuses.remove(project.id);
    }
  }

  Future<void> _handleSubTaskStatusChanged(
    TaskModel task,
    String newStatus,
  ) async {
    setState(() {
      task.status = newStatus;
    });

    final parent = _projects.firstWhere(
      (p) => p.subTasks?.contains(task) ?? false,
      orElse: () => _projects.first,
    );

    await _firebaseService.saveProject(
      parent,
    );
  }

  Future<void> _handleRegisterLog(
    TimeLog log,
  ) async {
    try {
      await widget.timeLogStore.register(
        log,
      );

      if (!mounted || !context.mounted) {
        return;
      }

      setState(() {
        _showPostStopButton = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Tempo cadastrado e salvo no Firebase com sucesso!',
          ),
          backgroundColor: CoresApp.sucesso,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted || !context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao cadastrar tempo no Firebase: $e',
          ),
          backgroundColor: CoresApp.erro,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _handleMarkTaskCompleted(
    TaskModel task,
  ) async {
    setState(() {
      task.status = 'TRAB';
    });

    final parent = _projects.firstWhere(
      (p) => p.subTasks?.contains(task) ?? false,
      orElse: () => _projects.first,
    );

    await _firebaseService.saveProject(
      parent,
    );

    if (mounted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Etapa ${task.subId} marcada como realizada!',
          ),
          backgroundColor: CoresApp.sucesso,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ============================================================
  // ALERTAS
  // ============================================================

  Widget _buildAlerts() {
    return Container(
      key: _alertsKey,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CoresDashboard.card.withValues(alpha: 0.995),
            CoresDashboard.fundoSecundario.withValues(alpha: 0.95),
          ],
        ),
        border: Border.all(
          color: CoresApp.borda.withValues(alpha: 0.88),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppPalette.dark ? 0.18 : 0.045),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
              decoration: BoxDecoration(
                color: CoresDashboard.fundoSecundario.withValues(alpha: 0.42),
                border: Border(
                  bottom: BorderSide(
                    color: CoresApp.borda.withValues(alpha: 0.55),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: CoresApp.aviso.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: CoresApp.aviso.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Icon(
                      Icons.notifications_active_rounded,
                      color: CoresApp.aviso,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Central de alertas',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Pendências e situações que precisam de atenção',
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ver todos os alertas',
                    onPressed: () =>
                        _checkPendingCommentUpdates(showEmpty: true),
                    icon: Icon(Icons.notifications_outlined,
                        color: CoresApp.aviso),
                  ),
                ],
              ),
            ),
            CentralAlertasWidget(
              projects: _projects,
              formatDateShort: _formatDateShort,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LOADING
  // ============================================================

  Widget _buildLoadingState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 34,
          vertical: 28,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              CoresDashboard.card.withValues(alpha: 0.99),
              CoresDashboard.fundoSecundario.withValues(alpha: 0.96),
            ],
          ),
          border: Border.all(
            color: CoresApp.borda.withValues(alpha: 0.82),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: AppPalette.dark ? 0.20 : 0.045),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: CoresApp.destaque.withValues(alpha: 0.10),
                border: Border.all(
                  color: CoresApp.destaque.withValues(alpha: 0.18),
                ),
              ),
              alignment: Alignment.center,
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.8,
                  color: CoresApp.destaque,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Carregando projetos...',
              style: TextStyle(
                color: CoresApp.textoPrincipal,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Sincronizando dados com o Firebase',
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final filteredProjects = _buildFilteredProjects();

    final activeProject = _getActiveProject();

    final dailyHoursPoints = _buildDailyHoursPoints();

    final totalProjects = _projects.length;

    final activeProjects = _projects
        .where(
          (p) => p.status != 'TRAB_FIM' && p.status != 'TRAB_STOP',
        )
        .length;

    final pausedProjects = _projects
        .where(
          (p) => p.status == 'TRAB_STOP',
        )
        .length;

    final totalTasks = _projects.fold<int>(
      0,
      (total, project) => total + (project.subTasks?.length ?? 0),
    );

    final totalRegisteredMinutes = _timeLogs
        .where(
      (log) => log.isRegistered,
    )
        .fold<int>(
      0,
      (total, log) => total + WorkDuration.minutes(log),
    );

    final totalHours = _formatHours(
      totalRegisteredMinutes / 60.0,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: Cabecalho(
          selectedIndex: widget.selectedIndex,
          onSelectTab: widget.onSelectTab,
          searchQuery: _searchQuery,
          onSearchChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
          userName: '',
        ),
      ),
      body: _isLoadingProjects
          ? _buildLoadingState()
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDashboardHeader(
                      activeProjects: activeProjects,
                      totalProjects: totalProjects,
                      pausedProjects: pausedProjects,
                      totalTasks: totalTasks,
                      totalHours: totalHours,
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    _buildTopDashboardPanels(
                      activeProject: activeProject,
                      dailyHoursPoints: dailyHoursPoints,
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    _buildProjectsTable(
                      filteredProjects,
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    _buildAlerts(),
                  ],
                ),
              ),
            ),
    );
  }

  void _toggleDashboardStatusFilter({
    String? status,
    bool apenasAtivos = false,
    bool todosProjetos = false,
  }) {
    setState(() {
      // Se clicar novamente no card que já está selecionado,
      // mantém a seleção.
      final alreadySelected = (_filtroApenasAtivos && apenasAtivos) ||
          (_filtroTodosProjetos && todosProjetos) ||
          (status != null && _statusFiltroDashboard == status);

      if (alreadySelected) {
        return;
      }

      // Selecionou outro card:
      // limpa completamente a seleção anterior.
      _statusFiltroDashboard = status;
      _filtroApenasAtivos = apenasAtivos;
      _filtroTodosProjetos = todosProjetos;
    });
  }
}
