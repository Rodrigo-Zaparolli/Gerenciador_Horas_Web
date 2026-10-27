import '../../../data/services/project_link_edit.dart';
import 'package:gerenciador_horas/core/theme/app_visuals.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import '../../../core/config/pilot_feature_access.dart';
import '../../projects/widgets/project_actions_pilot.dart';
import '../../edesk/work_audit_dialog.dart';
import '../../projects/dialogs/project_spreadsheet_dialog.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import '../../projects/widgets/edesk_phase_send_button.dart';
import 'dart:async';
import 'package:gerenciador_horas/core/platform/local_files.dart';
import 'package:gerenciador_horas/data/services/project_file_service.dart';
import 'package:gerenciador_horas/data/services/browser_local_files_service.dart';
import '../../projects/widgets/project_reference_field.dart';
import '../../projects/widgets/local_file_setup_dialog.dart';
import 'package:gerenciador_horas/core/config/web_config.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/data/services/edesk_service.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/project_storage_service.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/checklist_format_model.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comentario_modal.dart';
import 'package:gerenciador_horas/features/projects/widgets/project_storage_files_dialog.dart';

class HoraInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;

    text = text.replaceAll(RegExp(r'[^0-9:]'), '');

    if (text.contains(':')) {
      final parts = text.split(':');
      String hours = parts[0];
      String minutes = parts.length > 1 ? parts[1] : '';

      if (hours.length > 4) {
        hours = hours.substring(0, 4);
      }

      if (minutes.length > 2) {
        minutes = minutes.substring(0, 2);
      }

      text = '$hours:$minutes';
    } else {
      if (text.length > 6) {
        text = text.substring(0, 6);
      }

      if (text.length > 2) {
        final hours = text.substring(0, text.length - 2);
        final minutes = text.substring(text.length - 2);
        text = '$hours:$minutes';
      }
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// Draw the envelope without a font glyph so cached icon fonts cannot hide it.
class _ProjectEmailIconPainter extends CustomPainter {
  const _ProjectEmailIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rect = Rect.fromLTRB(size.width * 0.08, size.height * 0.2,
        size.width * 0.92, size.height * 0.8);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.09)), paint);
    final flap = Path()
      ..moveTo(rect.left + size.width * 0.02, rect.top + size.height * 0.04)
      ..lineTo(size.width * 0.5, size.height * 0.52)
      ..lineTo(rect.right - size.width * 0.02, rect.top + size.height * 0.04);
    canvas.drawPath(flap, paint);
  }

  @override
  bool shouldRepaint(covariant _ProjectEmailIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class TabelaProjetosWidget extends StatefulWidget {
  final List<ProjectModel> projects;
  final List<ProjectModel>? auditProjects;
  final List<String> statusList;
  final Set<String> expandedProjectIds;
  final String? selectedTargetId;
  final List<String> idsEmAlerta;

  final List<TimeLog> timeLogs;
  final String? activeTimerTargetId;
  final DateTime? activeStartTime;
  final TimerState timerState;
  final int secondsElapsed;
  final bool showPostStopButton;

  final ScrollController horizontalController;
  final ScrollController verticalController;

  final ValueChanged<String> onSelectTarget;
  final ValueChanged<String> onToggleExpand;

  final ValueChanged<ProjectModel> onEditProject;
  final ValueChanged<ProjectModel> onDeleteProject;
  final ValueChanged<ProjectModel> onAddSubTask;

  final Future<void> Function(ProjectModel, String) onProjectStatusChanged;
  final void Function(TaskModel, String) onSubTaskStatusChanged;

  final void Function(ProjectModel, TaskModel) onEditSubTask;
  final void Function(ProjectModel, TaskModel) onDeleteSubTask;

  final ValueChanged<String> onStartTimer;
  final VoidCallback onPauseTimer;
  final VoidCallback onStopTimer;
  final ValueChanged<String> onManualTime;

  final ValueChanged<TimeLog> onEditLog;
  final ValueChanged<TimeLog> onDeleteLog;
  final ValueChanged<TimeLog> onRegisterLog;
  final ValueChanged<TaskModel> onMarkTaskCompleted;

  final String Function(int) formatDuration;
  final FirebaseService firebaseService;

  const TabelaProjetosWidget({
    super.key,
    required this.projects,
    this.auditProjects,
    required this.statusList,
    required this.expandedProjectIds,
    required this.selectedTargetId,
    this.idsEmAlerta = const [],
    required this.timeLogs,
    required this.activeTimerTargetId,
    required this.activeStartTime,
    required this.timerState,
    required this.secondsElapsed,
    required this.showPostStopButton,
    required this.horizontalController,
    required this.verticalController,
    required this.onSelectTarget,
    required this.onToggleExpand,
    required this.onEditProject,
    required this.onDeleteProject,
    required this.onAddSubTask,
    required this.onProjectStatusChanged,
    required this.onSubTaskStatusChanged,
    required this.onEditSubTask,
    required this.onDeleteSubTask,
    required this.onStartTimer,
    required this.onPauseTimer,
    required this.onStopTimer,
    required this.onManualTime,
    required this.onEditLog,
    required this.onDeleteLog,
    required this.onRegisterLog,
    required this.onMarkTaskCompleted,
    required this.formatDuration,
    required this.firebaseService,
  });

  @override
  State<TabelaProjetosWidget> createState() => _TabelaProjetosWidgetState();
}

class _TabelaProjetosWidgetState extends State<TabelaProjetosWidget>
    with SingleTickerProviderStateMixin {
  final Map<String, TextEditingController> _inlineControllers = {};
  final Map<String, TextEditingController> _logCommentControllers = {};

  late List<TimeLog> _localTimeLogs;

  late final AnimationController _deadlineBlinkController;

  final List<String> _tiposHsOpcoes = const [
    'Hs Cobradas',
    'Hs Investimento',
    'Hs Não Cobradas',
    'Hs Internas',
    'Outras',
    'Hs Não Informadas',
  ];

  @override
  void initState() {
    super.initState();
    _localTimeLogs = List.from(widget.timeLogs);

    _deadlineBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant TabelaProjetosWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.timeLogs != oldWidget.timeLogs) {
      _localTimeLogs = List.from(widget.timeLogs);
    }
  }

  @override
  void dispose() {
    for (final controller in _inlineControllers.values) {
      controller.dispose();
    }

    _deadlineBlinkController.dispose();

    for (final controller in _logCommentControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  TextEditingController _getInlineController(ProjectModel project) {
    if (!_inlineControllers.containsKey(project.id)) {
      _inlineControllers[project.id] = TextEditingController(
        text: project.observacao ?? '',
      );
    } else {
      final controller = _inlineControllers[project.id]!;

      if (controller.text != (project.observacao ?? '')) {
        controller.text = project.observacao ?? '';
      }
    }

    return _inlineControllers[project.id]!;
  }

  TextEditingController _getLogCommentController(TimeLog log) {
    final key =
        '${log.targetId}_${log.date.toIso8601String()}_${log.startTime}';

    if (!_logCommentControllers.containsKey(key)) {
      _logCommentControllers[key] = TextEditingController(
        text: log.description ?? '',
      );
    } else {
      final controller = _logCommentControllers[key]!;

      if (controller.text != (log.description ?? '')) {
        controller.text = log.description ?? '';
      }
    }

    return _logCommentControllers[key]!;
  }

  Color _getStageColor(String status) {
    switch (status) {
      case 'INI_PRO':
        return CoresDashboard.statusInicial;

      case 'TRAB':
        return CoresDashboard.statusTrabalhando;

      case 'EA':
        return CoresDashboard.statusAndamento;

      case 'TRAB_FIM':
        return CoresDashboard.statusFinalizado;

      default:
        return CoresApp.textoSecundario;
    }
  }

  bool _projectHasDeadlineAlert(ProjectModel project) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (project.subTasks != null && project.subTasks!.isNotEmpty) {
      return project.subTasks!.any((task) {
        if (task.status == 'TRAB_FIM') return false;

        final planEnd = task.planEnd ?? task.startDate;
        final normalizedEnd =
            DateTime(planEnd.year, planEnd.month, planEnd.day);
        final differenceDays = normalizedEnd.difference(today).inDays;

        return differenceDays <= 5;
      });
    }

    if (project.status == 'TRAB_FIM') return false;

    final planEnd = project.startDate;
    final normalizedEnd = DateTime(planEnd.year, planEnd.month, planEnd.day);
    final differenceDays = normalizedEnd.difference(today).inDays;

    return differenceDays <= 5;
  }

  bool _projectIsOverdue(ProjectModel project) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (project.subTasks != null && project.subTasks!.isNotEmpty) {
      return project.subTasks!.any((task) {
        if (task.status == 'TRAB_FIM') return false;

        final planEnd = task.planEnd ?? task.startDate;
        final normalizedEnd =
            DateTime(planEnd.year, planEnd.month, planEnd.day);

        return normalizedEnd.isBefore(today);
      });
    }

    if (project.status == 'TRAB_FIM') return false;

    final planEnd = project.startDate;
    final normalizedEnd = DateTime(planEnd.year, planEnd.month, planEnd.day);

    return normalizedEnd.isBefore(today);
  }

  bool _taskIsOverdue(TaskModel task) {
    if (task.status == 'TRAB_FIM') return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final planEnd = task.planEnd ?? task.startDate;
    final normalizedEnd = DateTime(planEnd.year, planEnd.month, planEnd.day);

    return normalizedEnd.isBefore(today);
  }

  Widget _buildDeadlineDateText(
    String text, {
    required bool overdue,
    Color? normalColor,
    FontWeight? fontWeight,
  }) {
    if (!overdue) {
      return _buildCellText(
        text,
        color: normalColor ?? CoresApp.textoSecundario,
        fontWeight: fontWeight ?? FontWeight.normal,
      );
    }

    return AnimatedBuilder(
      animation: _deadlineBlinkController,
      builder: (context, child) {
        AppAppearance.watch(context);
        final t = _deadlineBlinkController.value;
        final backgroundOpacity = 0.10 + (t * 0.28);
        final borderOpacity = 0.35 + (t * 0.55);
        final textColor = Color.lerp(
          CoresApp.erro,
          AppPalette.text,
          t,
        )!;

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: CoresApp.erro.withValues(alpha: backgroundOpacity),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: CoresApp.erro.withValues(alpha: borderOpacity),
              width: 1.2,
            ),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: TamanhosApp.tabelaFonte,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
            ),
          ),
        );
      },
    );
  }

  int _parseHoursToMinutes(String rawValue) {
    final cleanVal = rawValue.replaceAll(RegExp(r'[^0-9:]'), '');

    int hours = 0;
    int minutes = 0;

    if (cleanVal.contains(':')) {
      final parts = cleanVal.split(':');

      if (parts.length >= 2) {
        hours = int.tryParse(parts[0]) ?? 0;
        minutes = int.tryParse(parts[1]) ?? 0;
      }
    } else {
      if (cleanVal.length >= 3) {
        final splitIndex = cleanVal.length - 2;

        hours = int.tryParse(cleanVal.substring(0, splitIndex)) ?? 0;

        minutes = int.tryParse(cleanVal.substring(splitIndex)) ?? 0;
      } else {
        hours = int.tryParse(cleanVal) ?? 0;
      }
    }

    return (hours * 60) + minutes;
  }

  String _formatMinutesToHHMM(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;

    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}';
  }

  String _calculateTotalEstimatedHours(
    List<TextEditingController> controllers,
  ) {
    int totalMinutes = 0;

    for (final controller in controllers) {
      totalMinutes += _parseHoursToMinutes(controller.text);
    }

    return _formatMinutesToHHMM(totalMinutes);
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year.toString().padLeft(4, '0')}';
  }

  void _handleRegisterLog(TimeLog log) {
    setState(() {
      log.isRegistered = true;
    });

    widget.onRegisterLog(log);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Tempo cadastrado e contabilizado com sucesso!',
        ),
        backgroundColor: CoresApp.sucesso,
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Text(
      text,
      style: TextStyle(
        color: CoresApp.textoSecundario,
        fontSize: TamanhosApp.tabelaFonteCabecalho,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildCellText(
    String text, {
    Color? color,
    FontWeight fontWeight = FontWeight.normal,
    double? fontSize,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? CoresApp.textoSecundario,
        fontSize: fontSize ?? TamanhosApp.tabelaFonte,
        fontWeight: fontWeight,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationThickness: 2.0,
      ),
    );
  }

  // Abre a Informação Útil do projeto sem ocupar uma coluna fixa na tabela.
  Future<void> _openProjectInfoDialog(ProjectModel project) async {
    final controller = _getInlineController(project);

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 520,
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: BoxDecoration(
              color: CoresTelas.campoFormulario,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: CoresApp.bordaSuave,
                width: TamanhosApp.espessuraBorda,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabeçalho do modal.
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: CoresApp.destaque.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.info_outline_rounded,
                          color: CoresApp.destaque,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Informações do Projeto',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Projeto ${project.id}',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: CoresApp.textoSecundario,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),

                Divider(
                  height: 1,
                  thickness: 1,
                  color: CoresApp.bordaSuave,
                ),

                // Conteúdo editável.
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'INFORMAÇÕES ÚTEIS',
                        style: TextStyle(
                          color: CoresApp.textoSecundario,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        minLines: 5,
                        maxLines: 8,
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: TamanhosApp.tabelaFonte,
                          height: 1.45,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Adicione observações ou informações importantes sobre este projeto...',
                          hintStyle: TextStyle(
                            color: CoresApp.textoSecundario.withValues(alpha: 0.55),
                            fontSize: 11,
                          ),
                          filled: true,
                          fillColor:
                              CoresTelas.campoFormulario.withValues(alpha: 0.55),
                          contentPadding: const EdgeInsets.all(14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: CoresApp.bordaSuave,
                              width: TamanhosApp.espessuraBorda,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: CoresApp.bordaSuave,
                              width: TamanhosApp.espessuraBorda,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: CoresApp.destaque,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Divider(
                  height: 1,
                  thickness: 1,
                  color: CoresApp.bordaSuave,
                ),

                // Rodapé com as mesmas ações de cancelar e salvar.
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: CoresApp.textoSecundario,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          project.observacao = controller.text.trim();

                          try {
                            await widget.firebaseService.salvarProjeto(project);
                            widget.onEditProject(project);

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }

                            if (mounted && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Informação salva com sucesso!',
                                  ),
                                  backgroundColor: CoresApp.sucesso,
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Erro ao salvar: $e'),
                                  backgroundColor: CoresApp.erro,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CoresApp.destaque,
                          foregroundColor: AppPalette.foregroundOn(CoresApp.destaque),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                        icon: const Icon(Icons.save_rounded, size: 17),
                        label: const Text(
                          'Salvar',
                          style: TextStyle(fontWeight: FontWeight.w600),
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
  }

  Widget _buildProjectIdBadge(
    ProjectModel project,
    bool hasSubtasks,
    bool isExpanded,
    bool emAlerta,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(TamanhosApp.raioBotao),
          onTap: hasSubtasks ? () => widget.onToggleExpand(project.id) : null,
          child: SizedBox(
            width: 22,
            child: hasSubtasks
                ? Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    color:
                        emAlerta ? CoresApp.destaqueAmarelo : CoresApp.destaque,
                    size: TamanhosApp.iconeTabela,
                  )
                : null,
          ),
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
              color: CoresApp.destaque.withValues(alpha: 0.35),
              width: emAlerta ? 1.5 : TamanhosApp.espessuraBorda,
            ),
          ),
          child: Text(
            project.id,
            style: TextStyle(
              color:
                  emAlerta ? CoresApp.destaqueAmarelo : CoresApp.textoPrincipal,
              fontSize: TamanhosApp.tabelaFonte,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Informação útil',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 28,
          ),
          icon: Icon(
            Icons.more_horiz_rounded,
            color: CoresApp.textoSecundario,
            size: 20,
          ),
          onPressed: () => _openProjectInfoDialog(project),
        ),
      ],
    );
  }

  Widget _buildStatusBadge({
    required String status,
    required ValueChanged<String?> onChanged,
  }) {
    final color = _getStageColor(status);

    final currentValue = widget.statusList.contains(status)
        ? status
        : widget.statusList.isNotEmpty
            ? widget.statusList.first
            : null;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioBadge,
        ),
        border: Border.all(
          color: color.withValues(alpha: 0.55),
          width: TamanhosApp.espessuraBorda,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          isDense: true,
          dropdownColor: CoresApp.superficie,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: color,
            size: TamanhosApp.iconeStatus,
          ),
          style: TextStyle(
            color: color,
            fontSize: TamanhosApp.tabelaFonteStatus,
            fontWeight: FontWeight.bold,
          ),
          onChanged: onChanged,
          items: widget.statusList.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(
                value,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: TamanhosApp.tabelaFonteStatus,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  InputDecoration _dialogInputDecoration({
    required String label,
    IconData? icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: CoresApp.textoSecundario,
        fontSize: TamanhosApp.tabelaFonteSecundaria,
      ),
      prefixIcon: icon != null
          ? Icon(
              icon,
              color: CoresApp.destaque,
              size: TamanhosApp.iconeTabela,
            )
          : null,
      suffixIcon: suffix,
      filled: true,
      fillColor: CoresTelas.campoFormulario,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioBotao,
        ),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioBotao,
        ),
        borderSide: BorderSide(
          color: CoresApp.bordaSuave,
          width: TamanhosApp.espessuraBorda,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioBotao,
        ),
        borderSide: BorderSide(
          color: CoresApp.destaque,
          width: TamanhosApp.espessuraBorda,
        ),
      ),
    );
  }

  void _showCheckListDialog(ProjectModel project) {
    final newItemController = TextEditingController();
    final checklistScrollController = ScrollController();
    String? selectedFormatId;
    List<ChecklistFormat> availableFormats = [];
    bool isLoadingFormats = true;

    showDialog(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            AppAppearance.watch(context);
            if (isLoadingFormats) {
              widget.firebaseService.getChecklistFormats().then((formats) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    availableFormats = formats;
                    isLoadingFormats = false;
                  });
                }
              }).catchError((_) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    isLoadingFormats = false;
                  });
                }
              });
            }

            final checklistItems = project.checklist;
            final int totalItems = checklistItems.length;
            final int completedItems = checklistItems
                .where((item) => item['completed'] == true)
                .length;
            final double progressValue =
                totalItems > 0 ? completedItems / totalItems : 0.0;
            final int progressPercent = (progressValue * 100).round();

            return AlertDialog(
              backgroundColor: CoresTelas.fundoModal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: CoresApp.borda),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.checklist_rounded,
                    color: CoresApp.destaque,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Check List - Projeto ${project.id}',
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 550,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: isLoadingFormats
                              ? const Center(
                                  child: SizedBox(
                                    height: 25,
                                    width: 25,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : DropdownButtonFormField<String>(
                                  initialValue: selectedFormatId,
                                  dropdownColor: CoresApp.superficie,
                                  decoration: _dialogInputDecoration(
                                    label: 'Importar Modelo de Checklist',
                                    icon: Icons.library_books_rounded,
                                  ),
                                  hint: Text(
                                    'Selecione um modelo...',
                                    style: TextStyle(
                                      color: CoresApp.textoSecundario,
                                      fontSize: 13,
                                    ),
                                  ),
                                  items: availableFormats.map((format) {
                                    final String formatId = format.id;
                                    final String formatName =
                                        format.name.trim().isNotEmpty
                                            ? format.name
                                            : 'Sem nome';

                                    return DropdownMenuItem<String>(
                                      value: formatId,
                                      child: Text(
                                        formatName,
                                        style: TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 13,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      selectedFormatId = value;
                                    });
                                  },
                                ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CoresApp.destaque,
                            foregroundColor: AppPalette.foregroundOn(CoresApp.destaque),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                          onPressed: selectedFormatId == null
                              ? null
                              : () async {
                                  ChecklistFormat? chosenFormat;

                                  for (final format in availableFormats) {
                                    if (format.id == selectedFormatId) {
                                      chosenFormat = format;
                                      break;
                                    }
                                  }

                                  if (chosenFormat != null) {
                                    for (final formatItem
                                        in chosenFormat.items) {
                                      final name = formatItem['name']
                                              ?.toString()
                                              .trim() ??
                                          '';

                                      if (name.isEmpty) continue;

                                      project.checklist.add({
                                        'order':
                                            formatItem['order']?.toString() ??
                                                '',
                                        'name': name,
                                        'completed': false,
                                      });
                                    }

                                    try {
                                      await widget.firebaseService
                                          .salvarProjeto(project);

                                      widget.onEditProject(project);

                                      setDialogState(() {
                                        selectedFormatId = null;
                                      });

                                      if (mounted && context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                              'Modelo importado com sucesso!',
                                            ),
                                            backgroundColor: CoresApp.sucesso,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted && context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Erro ao importar modelo: $e',
                                            ),
                                            backgroundColor: CoresApp.erro,
                                          ),
                                        );
                                      }
                                    }
                                  }
                                },
                          child: const Text(
                            'Aplicar',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: newItemController,
                            style: TextStyle(
                              color: CoresApp.textoPrincipal,
                              fontSize: 13,
                            ),
                            decoration: _dialogInputDecoration(
                              label: 'Nova tarefa manual',
                              icon: Icons.add_task_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CoresApp.destaque,
                            foregroundColor: AppPalette.foregroundOn(CoresApp.destaque),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          onPressed: () async {
                            final text = newItemController.text.trim();

                            if (text.isNotEmpty) {
                              final nextOrder =
                                  (project.checklist.length + 1).toString();

                              project.checklist.add({
                                'order': nextOrder,
                                'name': text,
                                'completed': false,
                              });

                              newItemController.clear();

                              try {
                                await widget.firebaseService.salvarProjeto(project);

                                widget.onEditProject(project);

                                setDialogState(() {});
                              } catch (e) {
                                if (mounted && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Erro ao salvar item: $e'),
                                      backgroundColor: CoresApp.erro,
                                    ),
                                  );
                                }
                              }
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
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: (project.checklist.isEmpty)
                          ? Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Center(
                                child: Text(
                                  'Nenhum item cadastrado no checklist.',
                                  style: TextStyle(
                                    color: CoresApp.textoSecundario,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                          : Scrollbar(
                              controller: checklistScrollController,
                              thumbVisibility: true,
                              child: ListView.separated(
                                controller: checklistScrollController,
                                shrinkWrap: true,
                                itemCount: project.checklist.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = project.checklist[index];
                                  final bool isCompleted =
                                      item['completed'] == true;
                                  final String order =
                                      item['order']?.toString() ??
                                          '${index + 1}';
                                  final String name =
                                      item['name']?.toString() ?? '';

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      '$order. $name',
                                      style: TextStyle(
                                        color: isCompleted
                                            ? CoresApp.textoSecundario
                                            : CoresApp.textoPrincipal,
                                        decoration: isCompleted
                                            ? TextDecoration.lineThrough
                                            : null,
                                        fontSize: 13,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            Icons.delete_outline_rounded,
                                            color: CoresApp.erro,
                                            size: 20,
                                          ),
                                          onPressed: () async {
                                            project.checklist.removeAt(index);

                                            try {
                                              await widget.firebaseService
                                                  .salvarProjeto(project);

                                              widget.onEditProject(project);

                                              setDialogState(() {});
                                            } catch (e) {
                                              if (mounted && context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Erro ao excluir item: $e',
                                                    ),
                                                    backgroundColor:
                                                        CoresApp.erro,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                        ),
                                        Checkbox(
                                          activeColor: CoresApp.destaque,
                                          checkColor: AppPalette.onPrimary,
                                          value: isCompleted,
                                          onChanged: (bool? value) async {
                                            setDialogState(() {
                                              item['completed'] =
                                                  value ?? false;
                                            });

                                            try {
                                              await widget.firebaseService
                                                  .salvarProjeto(project);

                                              widget.onEditProject(project);
                                            } catch (e) {
                                              if (mounted && context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Erro ao atualizar checklist: $e',
                                                    ),
                                                    backgroundColor:
                                                        CoresApp.erro,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Progresso',
                                style: TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '$progressPercent%',
                                style: TextStyle(
                                  color: CoresApp.destaque,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progressValue,
                              backgroundColor: CoresApp.borda,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                CoresApp.destaque,
                              ),
                              minHeight: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CoresApp.destaque,
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(
                        'Fechar',
                        style: TextStyle(
                          color: AppPalette.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      newItemController.dispose();
      checklistScrollController.dispose();
    });
  }

/////////////////////////////////////////////
  ///Abre o modal de editar
//////////////////////
  void _showLinksDialog(ProjectModel project) {
    final linkEdit = ProjectLinkEdit(project);
    project = linkEdit.draft;
    final idController = TextEditingController(text: project.id);
    final clientController = TextEditingController(text: project.client);
    final folderController =
        TextEditingController(text: project.folderPath ?? '');
    final excelController =
        TextEditingController(text: project.excelLink ?? '');
    final leaderController = TextEditingController(text: project.leader);
    final serviceTypeController =
        TextEditingController(text: project.serviceType);
    final hourTypeController = TextEditingController(text: project.hourType);
    final observacaoController =
        TextEditingController(text: project.observacao ?? '');

    final linksScrollController = ScrollController();

    bool atualizandoFasesEdesk = false;
    bool savingLinks = false;

    // ============================================================
    // Seleção temporária; permite enviar várias fases sem alterar os dados.
    final Set<int> fasesSelecionadasEdesk = {};

    // ============================================================
    // ETAPAS TEMPORÁRIAS
    // ============================================================

    List<TaskModel> tempSubTasks = project.subTasks != null
        ? project.subTasks!
            .map(
              (s) => TaskModel(
                subId: s.subId,
                stage: s.stage,
                status: s.status,
                startDate: s.startDate,
                planStart: s.planStart,
                planEnd: s.planEnd,
                estimatedHours: s.estimatedHours,
                hourType: _tiposHsOpcoes.contains(s.hourType)
                    ? s.hourType
                    : _tiposHsOpcoes.first,

                // ===================================================
                // E-DESK
                // ===================================================
                edeskUrl: s.edeskUrl,
                edeskIdTrabalho: s.edeskIdTrabalho,
              ),
            )
            .toList()
        : [];

    // ============================================================
    // HORAS
    // ============================================================

    final estimatedHoursController = TextEditingController();
    final List<TextEditingController> subHoursControllers = [];

    for (final s in tempSubTasks) {
      final ctrl = TextEditingController(
        text: s.estimatedHours,
      );

      ctrl.addListener(() {
        estimatedHoursController.text = _calculateTotalEstimatedHours(
          subHoursControllers,
        );
      });

      subHoursControllers.add(ctrl);
    }

    estimatedHoursController.text = project.estimatedHours.isNotEmpty
        ? project.estimatedHours
        : _calculateTotalEstimatedHours(
            subHoursControllers,
          );

    String selectedStatus = widget.statusList.contains(project.status)
        ? project.status
        : widget.statusList.isNotEmpty
            ? widget.statusList.first
            : '';

    // ============================================================
    // ABRIR MODAL
    // ============================================================

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            AppAppearance.watch(context);
            // =============================================================
            // CARREGA AS CONFIGURAÇÕES DO FIREBASE AO ABRIR O MODAL
            // =============================================================
            //
            // As etiquetas padrão existem apenas como fallback para usuários
            // que ainda não possuem configuração salva.
            //
            // Se já existe configuração no Firebase, ela passa a ser a
            // fonte definitiva.
            // =============================================================

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 30,
                vertical: 25,
              ),
              child: Container(
                width: 950,
                constraints: const BoxConstraints(
                  maxHeight: 820,
                ),
                decoration: BoxDecoration(
                  color: CoresTelas.fundoModal,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: CoresApp.borda,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: CoresApp.overlay,
                      blurRadius: 30,
                      spreadRadius: 2,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // ==================================================
                    // CABEÇALHO
                    // ==================================================

                    Container(
                      padding: const EdgeInsets.fromLTRB(
                        22,
                        18,
                        14,
                        18,
                      ),
                      decoration: BoxDecoration(
                        color: CoresTelas.fundoModalSecundario,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: CoresApp.destaque.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              Icons.edit_note_rounded,
                              color: CoresApp.destaque,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Atualize os dados e as etapas do projeto',
                                  style: TextStyle(
                                    color: CoresApp.textoSecundario,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Fechar',
                            icon: Icon(
                              Icons.close_rounded,
                              color: CoresApp.textoSecundario,
                            ),
                            onPressed: savingLinks ? null : () {
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                    ),

                    // ==================================================
                    // CONTEÚDO
                    // ==================================================

                    Expanded(
                      child: Scrollbar(
                        controller: linksScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: linksScrollController,
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ========================================
                              // ID / STATUS
                              // ========================================

                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: idController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 13,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'ID',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: InputDecorator(
                                      decoration: _dialogInputDecoration(
                                        label: 'Status',
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: selectedStatus.isNotEmpty
                                              ? selectedStatus
                                              : null,
                                          dropdownColor: CoresApp.superficie,
                                          isDense: true,
                                          isExpanded: true,
                                          style: TextStyle(
                                            color: CoresApp.textoPrincipal,
                                            fontSize: 13,
                                          ),
                                          icon: Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            color: CoresApp.textoSecundario,
                                          ),
                                          items: widget.statusList.map((st) {
                                            return DropdownMenuItem<String>(
                                              value: st,
                                              child: Text(st),
                                            );
                                          }).toList(),
                                          onChanged: (value) {
                                            if (value != null) {
                                              setDialogState(
                                                () => selectedStatus = value,
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // ========================================
                              // CLIENTE / SERVIÇO
                              // ========================================

                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: clientController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 13,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Cliente',
                                        icon: Icons.business_rounded,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: TextField(
                                      controller: serviceTypeController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 13,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Tipo de Serviço',
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

// ========================================
// OBSERVAÇÃO
// ========================================

                              Align(
                                alignment: Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 500,
                                  ),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: TextField(
                                      controller: observacaoController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 13,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Informações Úteis / Descritivo',
                                        icon: Icons.description_rounded,
                                      ),
                                      maxLines: 2,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 12),

                              // ========================================
                              // PASTA / ARQUIVO
                              // ========================================

                              Row(
                                children: [
                                  Expanded(
                                    child: ProjectReferenceField(
                                      controller: folderController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 12,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Pasta de Documentos',
                                        icon: Icons.folder_rounded,
                                        suffix: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                Icons.create_new_folder_rounded,
                                                color: CoresApp.destaque,
                                                size: 19,
                                              ),
                                              tooltip: 'Criar Pasta do Projeto',
                                              onPressed: () async {
                                                if (kIsWeb) {
                                                  try {
                                                    if (idController.text
                                                            .trim()
                                                            .isEmpty ||
                                                        clientController.text
                                                            .trim()
                                                            .isEmpty) {
                                                      throw StateError(
                                                          'Informe o ID e o Cliente antes de criar a pasta.');
                                                    }
                                                    final reference =
                                                        await BrowserLocalFiles
                                                            .pickFolder(
                                                                createName:
                                                                    '${idController.text.trim()} - ${clientController.text.trim()}');
                                                    if (reference == null ||
                                                        !dialogContext.mounted) {
                                                      return;
                                                    }
                                                    setDialogState(() =>
                                                        folderController.text =
                                                            reference);
                                                  } catch (error) {
                                                    ScaffoldMessenger.of(
                                                            dialogContext)
                                                        .showSnackBar(SnackBar(
                                                            content: Text(
                                                                '$error')));
                                                  }
                                                  return;
                                                }
                                                try {
                                                  final pastaBase =
                                                      await FilePicker.platform
                                                          .getDirectoryPath(
                                                    dialogTitle:
                                                        'Escolha onde criar a pasta do projeto',
                                                  );

                                                  if (pastaBase == null) return;

                                                  final idProjeto =
                                                      idController.text.trim();
                                                  final cliente =
                                                      clientController.text
                                                          .trim();

                                                  if (idProjeto.isEmpty ||
                                                      cliente.isEmpty) {
                                                    if (dialogContext.mounted) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Informe o ID e o Cliente antes de criar a pasta.',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                    return;
                                                  }

                                                  String limparNomePasta(
                                                    String valor,
                                                  ) {
                                                    return valor
                                                        .replaceAll(
                                                          RegExp(
                                                              r'[<>:"/\\|?*]'),
                                                          '-',
                                                        )
                                                        .replaceAll(
                                                          RegExp(r'\s+'),
                                                          ' ',
                                                        )
                                                        .trim();
                                                  }

                                                  final nomePasta =
                                                      limparNomePasta(
                                                    '$idProjeto - $cliente',
                                                  );
                                                  final caminhoPasta =
                                                      await createLocalFolder(
                                                          pastaBase, nomePasta);

                                                  if (!mounted || !dialogContext.mounted || !context.mounted) {
                                                    return;
                                                  }
                                                  setDialogState(() {
                                                    folderController.text =
                                                        caminhoPasta;
                                                  });
                                                } catch (e) {
                                                  debugPrint(
                                                    'Erro ao criar pasta do projeto: $e',
                                                  );
                                                  if (dialogContext.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          'Não foi possível criar a pasta: $e',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                }
                                              },
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.search_rounded,
                                                color: CoresApp.destaque,
                                                size: 18,
                                              ),
                                              tooltip: 'Selecionar Pasta',
                                              onPressed: () async {
                                                if (kIsWeb) {
                                                  try {
                                                    final reference =
                                                        await BrowserLocalFiles
                                                            .pickFolder();
                                                    if (reference != null &&
                                                        dialogContext.mounted) {
                                                      setDialogState(() =>
                                                          folderController
                                                                  .text =
                                                              reference);
                                                    }
                                                  } catch (error) {
                                                    if (dialogContext.mounted) {
                                                      ScaffoldMessenger.of(
                                                              dialogContext)
                                                          .showSnackBar(SnackBar(
                                                              content: Text(error
                                                                  .toString()
                                                                  .replaceFirst(
                                                                      'Bad state: ',
                                                                      ''))));
                                                    }
                                                  }
                                                  return;
                                                }
                                                try {
                                                  final selectedDirectory =
                                                      await FilePicker.platform
                                                          .getDirectoryPath(
                                                    dialogTitle:
                                                        'Selecione a Pasta do Projeto',
                                                  );

                                                  if (selectedDirectory !=
                                                          null &&
                                                      dialogContext.mounted) {
                                                    setDialogState(() {
                                                      folderController.text =
                                                          selectedDirectory;
                                                    });
                                                  }
                                                } catch (e) {
                                                  debugPrint(
                                                    'Erro ao abrir seletor de pastas: $e',
                                                  );
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ProjectReferenceField(
                                      controller: excelController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 12,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Arquivo / Link',
                                        icon: Icons.insert_drive_file_rounded,
                                        suffix: IconButton(
                                          icon: Icon(
                                            Icons.attach_file_rounded,
                                            color: CoresApp.destaque,
                                            size: 18,
                                          ),
                                          tooltip: 'Selecionar Arquivo',
                                          onPressed: () async {
                                            try {
                                              final reference =
                                                  await ProjectFileService
                                                      .pickFile(
                                                          idController.text);
                                              if (reference == null ||
                                                  !dialogContext.mounted) {
                                                return;
                                              }
                                              setDialogState(() {
                                                excelController.text =
                                                    reference;
                                                if (kIsWeb &&
                                                    WebConfig.storageEnabled &&
                                                    folderController.text
                                                        .trim()
                                                        .isEmpty) {
                                                  folderController.text =
                                                      ProjectFileService
                                                          .cloudFolder(
                                                              idController
                                                                  .text);
                                                }
                                              });
                                            } catch (error) {
                                              if (dialogContext.mounted) {
                                                ScaffoldMessenger.of(
                                                        dialogContext)
                                                    .showSnackBar(SnackBar(
                                                        content:
                                                            Text('$error')));
                                              }
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

// ========================================
// TÍTULO ETAPAS + AÇÕES
// ========================================

                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Trabalhos Internos do Serviço',
                                          style: TextStyle(
                                            color: CoresApp.textoPrincipal,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Marque as fases desejadas ou escolha enviar todas no botão ao lado.',
                                          style: TextStyle(
                                            color: CoresApp.textoSecundario,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  // ======================================
// ATUALIZAR FASES E-DESK
// ======================================

                                  EdeskPhaseSendButton(
                                    total: tempSubTasks.length,
                                    selectedCount:
                                        fasesSelecionadasEdesk.length,
                                    busy: atualizandoFasesEdesk,
                                    onSend: (enviarTodas) async {
                                      // ============================================
                                      // VALIDAÇÕES
                                      // ============================================

                                      final id = idController.text.trim();
                                      final cliente =
                                          clientController.text.trim();

                                      if (id.isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                              'Informe o ID da solicitação antes de atualizar o E-Desk.',
                                            ),
                                            backgroundColor: CoresApp.erro,
                                          ),
                                        );
                                        return;
                                      }

                                      if (cliente.isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                              'Informe o cliente antes de atualizar o E-Desk.',
                                            ),
                                            backgroundColor: CoresApp.erro,
                                          ),
                                        );
                                        return;
                                      }

                                      if (tempSubTasks.isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                              'Este projeto não possui etapas para enviar ao E-Desk.',
                                            ),
                                            backgroundColor: CoresApp.erro,
                                          ),
                                        );
                                        return;
                                      }

                                      // ============================================
                                      // Define o conjunto exato enviado nesta operação.
                                      List<int> indices;
                                      try {
                                        indices = edeskPhaseIndices(
                                            tempSubTasks.length,
                                            fasesSelecionadasEdesk,
                                            all: enviarTodas);
                                      } on StateError catch (error) {
                                        ScaffoldMessenger.of(dialogContext)
                                            .showSnackBar(SnackBar(
                                                content: Text(error.message)));
                                        return;
                                      }
                                      final List<Map<String, String>> fases =
                                          [];
                                      for (final index in indices) {
                                        final sub = tempSubTasks[index];
                                        if (sub.stage.trim().isEmpty) {
                                          ScaffoldMessenger.of(dialogContext)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      'A fase ${index + 1} não possui um nome válido.')));
                                          return;
                                        }
                                        fases.add({
                                          'nome': sub.stage.trim(),
                                          'dataInicial':
                                              _formatDate(sub.startDate),
                                          'dataFinal': sub.planEnd == null
                                              ? ''
                                              : _formatDate(sub.planEnd!)
                                        });
                                      }
                                      // ============================================
                                      // LOG
                                      // ============================================

                                      debugPrint('');
                                      debugPrint(
                                        '========== ATUALIZAÇÃO FASES E-DESK ==========',
                                      );
                                      debugPrint(
                                        '[E-DESK] Solicitação: $id',
                                      );
                                      debugPrint(
                                        '[E-DESK] Cliente: $cliente',
                                      );
                                      debugPrint(
                                        '[E-DESK] Quantidade de fases: ${fases.length}',
                                      );

                                      for (final fase in fases) {
                                        debugPrint(
                                          '[E-DESK] '
                                          '${fase['nome']} | '
                                          'Inicial=${fase['dataInicial']} | '
                                          'Final=${fase['dataFinal']}',
                                        );
                                      }

                                      debugPrint(
                                        '================================================',
                                      );

                                      // ============================================
                                      // MOSTRA O SPINNER IMEDIATAMENTE
                                      // ============================================

                                      setDialogState(() {
                                        atualizandoFasesEdesk = true;
                                      });

                                      try {
                                        final resultado = await EdeskService()
                                            .atualizarFasesViaPython(
                                          id: id,
                                          cliente: cliente,
                                          fases: fases,

                                          // ==================================================
                                          // QUANDO O PYTHON REALMENTE TERMINAR
                                          // ==================================================

                                          onConcluido: (sucesso, mensagem) {
                                            if (!mounted || !dialogContext.mounted || !context.mounted) {
                                              return;
                                            }

                                            setDialogState(() {
                                              atualizandoFasesEdesk = false;
                                            });

                                            ScaffoldMessenger.of(dialogContext)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  mensagem,
                                                ),
                                                backgroundColor: sucesso
                                                    ? CoresApp.sucesso
                                                    : CoresApp.erro,
                                                duration: const Duration(
                                                  seconds: 5,
                                                ),
                                              ),
                                            );
                                          },
                                        );

                                        if (!mounted || !dialogContext.mounted || !context.mounted) return;
                                        setDialogState(() =>
                                            atualizandoFasesEdesk = false);
                                        if (resultado.statusCode == 499) return;
                                        if (resultado.confirmed) {
                                          ScaffoldMessenger.of(dialogContext)
                                              .showSnackBar(SnackBar(
                                            content: Text(resultado.message),
                                            backgroundColor: CoresApp.sucesso,
                                          ));
                                        }
                                        debugPrint(
                                          '[E-DESK] Resultado inicial: '
                                          'confirmed=${resultado.confirmed} | '
                                          'status=${resultado.statusCode} | '
                                          'message=${resultado.message}',
                                        );

                                        // ==================================================
                                        // ERRO AO INICIAR O PROCESSO
                                        //
                                        // Se o Python nem chegou a iniciar, o callback acima
                                        // não será chamado.
                                        // ==================================================

                                        if (!resultado.confirmed) {
                                          if (!mounted || !dialogContext.mounted || !context.mounted) {
                                            return;
                                          }

                                          setDialogState(() {
                                            atualizandoFasesEdesk = false;
                                          });

                                          ScaffoldMessenger.of(dialogContext)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                resultado.message,
                                              ),
                                              backgroundColor: CoresApp.erro,
                                              duration: const Duration(
                                                seconds: 5,
                                              ),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        debugPrint(
                                          '[E-DESK] Erro ao atualizar fases: $e',
                                        );

                                        if (!mounted || !dialogContext.mounted || !context.mounted) {
                                          return;
                                        }

                                        setDialogState(() {
                                          atualizandoFasesEdesk = false;
                                        });

                                        ScaffoldMessenger.of(dialogContext)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Erro ao atualizar fases no E-Desk: $e',
                                            ),
                                            backgroundColor: CoresApp.erro,
                                            duration: const Duration(
                                              seconds: 5,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),

                                  // ======================================
                                  // NOVA ETAPA
                                  // ======================================

                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          CoresApp.destaque.withValues(alpha: 0.15),
                                      foregroundColor: CoresApp.destaque,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(
                                          color: CoresApp.destaque
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.playlist_add_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Adicionar Nova Etapa',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: () {
                                      int maiorId = 0;

                                      for (final etapa in tempSubTasks) {
                                        final id = int.tryParse(
                                              etapa.subId.toString(),
                                            ) ??
                                            0;

                                        if (id > maiorId) {
                                          maiorId = id;
                                        }
                                      }

                                      final agora = DateTime.now();

                                      final novaEtapa = TaskModel(
                                        subId: '${maiorId + 1}',
                                        stage: 'Nova Etapa',
                                        status: 'INI_PRO',
                                        startDate: agora,
                                        planStart: agora,
                                        planEnd: agora,
                                        estimatedHours: '00:00',
                                        hourType: _tiposHsOpcoes.first,

                                        // E-DESK
                                        edeskUrl: null,
                                        edeskIdTrabalho: null,
                                      );

                                      final ctrl = TextEditingController(
                                        text: '00:00',
                                      );

                                      ctrl.addListener(() {
                                        estimatedHoursController.text =
                                            _calculateTotalEstimatedHours(
                                          subHoursControllers,
                                        );
                                      });

                                      setDialogState(() {
                                        tempSubTasks.add(
                                          novaEtapa,
                                        );

                                        subHoursControllers.add(
                                          ctrl,
                                        );

                                        estimatedHoursController.text =
                                            _calculateTotalEstimatedHours(
                                          subHoursControllers,
                                        );
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // ========================================
                              // LISTA DE ETAPAS
                              // ========================================

                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: CoresTelas.fundoModalSecundario,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: CoresApp.bordaSuave,
                                  ),
                                ),
                                child: tempSubTasks.isEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Center(
                                          child: Text(
                                            'Este projeto não possui etapas cadastradas.',
                                            style: TextStyle(
                                              color: CoresApp.textoSecundario,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      )
                                    : ListView.separated(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: tempSubTasks.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(
                                          height: 10,
                                        ),
                                        itemBuilder: (context, index) {
                                          final sub = tempSubTasks[index];

                                          return Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: CoresTelas.campoFormulario,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: CoresApp.bordaSuave,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: 60,
                                                  child: TextFormField(
                                                    initialValue: sub.subId,
                                                    keyboardType:
                                                        TextInputType.number,
                                                    inputFormatters: [
                                                      FilteringTextInputFormatter
                                                          .digitsOnly,
                                                    ],
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: CoresApp.destaque,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                    decoration:
                                                        _dialogInputDecoration(
                                                      label: 'Nº',
                                                    ),
                                                    onChanged: (value) {
                                                      sub.subId = value.trim();
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  flex: 4,
                                                  child: TextFormField(
                                                    initialValue: sub.stage,
                                                    style: TextStyle(
                                                      color: CoresApp
                                                          .textoPrincipal,
                                                      fontSize: 12,
                                                    ),
                                                    decoration:
                                                        _dialogInputDecoration(
                                                      label: 'Nome da Etapa',
                                                    ),
                                                    onChanged: (val) {
                                                      sub.stage = val;
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 8),

                                                // DATA INÍCIO
                                                Expanded(
                                                  flex: 3,
                                                  child: InkWell(
                                                    onTap: () async {
                                                      final picked =
                                                          await showDatePicker(
                                                        context: context,
                                                        initialDate:
                                                            sub.startDate,
                                                        firstDate:
                                                            DateTime(2020),
                                                        lastDate:
                                                            DateTime(2030),
                                                        locale: const Locale(
                                                          'pt',
                                                          'BR',
                                                        ),
                                                        builder: (
                                                          BuildContext context,
                                                          Widget? child,
                                                        ) {
                                                          AppAppearance.watch(
                                                              context);

                                                          return Theme(
                                                            data:
                                                                ThemeData.dark()
                                                                    .copyWith(
                                                              colorScheme:
                                                                  ColorScheme
                                                                      .dark(
                                                                primary: CoresApp
                                                                    .destaque,
                                                                onPrimary:
                                                                    Colors
                                                                        .black,
                                                                surface: CoresTelas
                                                                    .fundoModal,
                                                                onSurface: CoresApp
                                                                    .textoPrincipal,
                                                              ), dialogTheme: DialogThemeData(backgroundColor: CoresTelas
                                                                      .fundoModal),
                                                            ),
                                                            child: Localizations
                                                                .override(
                                                              context: context,
                                                              locale:
                                                                  const Locale(
                                                                'pt',
                                                                'BR',
                                                              ),
                                                              child: child!,
                                                            ),
                                                          );
                                                        },
                                                      );

                                                      if (picked != null) {
                                                        setDialogState(
                                                          () {
                                                            sub.startDate =
                                                                picked;
                                                            sub.planStart =
                                                                picked;
                                                          },
                                                        );
                                                      }
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 10,
                                                        vertical: 8,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: CoresTelas
                                                            .fundoModalSecundario,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        border: Border.all(
                                                          color: CoresApp
                                                              .bordaSuave,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Text(
                                                            'Início: ${_formatDate(sub.startDate)}',
                                                            style: TextStyle(
                                                              color: CoresApp
                                                                  .textoPrincipal,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                          Icon(
                                                            Icons
                                                                .calendar_today_rounded,
                                                            size: 14,
                                                            color: CoresApp
                                                                .destaque,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),

                                                const SizedBox(width: 8),

                                                // DATA FINAL
                                                Expanded(
                                                  flex: 3,
                                                  child: InkWell(
                                                    onTap: () async {
                                                      final picked =
                                                          await showDatePicker(
                                                        context: context,
                                                        initialDate:
                                                            sub.planEnd ??
                                                                sub.startDate,
                                                        firstDate:
                                                            DateTime(2020),
                                                        lastDate:
                                                            DateTime(2030),
                                                        locale: const Locale(
                                                          'pt',
                                                          'BR',
                                                        ),
                                                        builder: (
                                                          BuildContext context,
                                                          Widget? child,
                                                        ) {
                                                          AppAppearance.watch(
                                                              context);

                                                          return Theme(
                                                            data:
                                                                ThemeData.dark()
                                                                    .copyWith(
                                                              colorScheme:
                                                                  ColorScheme
                                                                      .dark(
                                                                primary: CoresApp
                                                                    .destaque,
                                                                onPrimary:
                                                                    Colors
                                                                        .black,
                                                                surface: CoresTelas
                                                                    .fundoModal,
                                                                onSurface: CoresApp
                                                                    .textoPrincipal,
                                                              ), dialogTheme: DialogThemeData(backgroundColor: CoresTelas
                                                                      .fundoModal),
                                                            ),
                                                            child: Localizations
                                                                .override(
                                                              context: context,
                                                              locale:
                                                                  const Locale(
                                                                'pt',
                                                                'BR',
                                                              ),
                                                              child: child!,
                                                            ),
                                                          );
                                                        },
                                                      );

                                                      if (picked != null) {
                                                        setDialogState(
                                                          () {
                                                            sub.planEnd =
                                                                picked;
                                                          },
                                                        );
                                                      }
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 10,
                                                        vertical: 8,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: CoresTelas
                                                            .fundoModalSecundario,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        border: Border.all(
                                                          color: CoresApp
                                                              .bordaSuave,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Text(
                                                            'Fim: ${sub.planEnd != null ? _formatDate(sub.planEnd!) : '-'}',
                                                            style: TextStyle(
                                                              color: CoresApp
                                                                  .textoPrincipal,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                          Icon(
                                                            Icons
                                                                .calendar_today_rounded,
                                                            size: 14,
                                                            color: CoresApp
                                                                .destaque,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),

                                                const SizedBox(width: 8),

                                                // ========================================
                                                // FASE PARA ENVIO AO E-DESK
                                                // ========================================
                                                //
                                                // Selecione uma ou várias fases para o envio.
                                                Tooltip(
                                                  message:
                                                      'Selecionar esta fase para enviar ao E-Desk',
                                                  child: SizedBox(
                                                    width: 44,
                                                    child: Checkbox(
                                                      value:
                                                          fasesSelecionadasEdesk
                                                              .contains(index),
                                                      activeColor:
                                                          Colors.blueAccent,
                                                      onChanged:
                                                          atualizandoFasesEdesk
                                                              ? null
                                                              : (value) {
                                                                  setDialogState(
                                                                      () {
                                                                    if (value ==
                                                                        true) {
                                                                      fasesSelecionadasEdesk
                                                                          .add(
                                                                              index);
                                                                    } else {
                                                                      fasesSelecionadasEdesk
                                                                          .remove(
                                                                              index);
                                                                    }
                                                                  });
                                                                },
                                                    ),
                                                  ),
                                                ),

                                                const SizedBox(width: 4),

                                                // HORAS
                                                Expanded(
                                                  flex: 2,
                                                  child: TextField(
                                                    controller:
                                                        subHoursControllers[
                                                            index],
                                                    keyboardType:
                                                        TextInputType.text,
                                                    inputFormatters: [
                                                      HoraInputFormatter(),
                                                    ],
                                                    style: TextStyle(
                                                      color: CoresApp
                                                          .textoPrincipal,
                                                      fontSize: 12,
                                                    ),
                                                    decoration:
                                                        _dialogInputDecoration(
                                                      label: 'Horas',
                                                    ),
                                                    onChanged: (_) {
                                                      setDialogState(() {});
                                                    },
                                                  ),
                                                ),

                                                const SizedBox(width: 8),

                                                // TIPO HORAS
                                                Expanded(
                                                  flex: 3,
                                                  child: InputDecorator(
                                                    decoration:
                                                        _dialogInputDecoration(
                                                      label: 'Tipo de Horas',
                                                    ),
                                                    child:
                                                        DropdownButtonHideUnderline(
                                                      child: DropdownButton<
                                                          String>(
                                                        value: _tiposHsOpcoes
                                                                .contains(
                                                          sub.hourType,
                                                        )
                                                            ? sub.hourType
                                                            : _tiposHsOpcoes
                                                                .first,
                                                        dropdownColor:
                                                            CoresApp.superficie,
                                                        isDense: true,
                                                        isExpanded: true,
                                                        style: TextStyle(
                                                          color: CoresApp
                                                              .textoPrincipal,
                                                          fontSize: 11,
                                                        ),
                                                        icon: Icon(
                                                          Icons
                                                              .keyboard_arrow_down_rounded,
                                                          color: CoresApp
                                                              .textoSecundario,
                                                          size: 16,
                                                        ),
                                                        items:
                                                            _tiposHsOpcoes.map(
                                                          (tipo) {
                                                            return DropdownMenuItem<
                                                                String>(
                                                              value: tipo,
                                                              child: Text(
                                                                tipo,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            );
                                                          },
                                                        ).toList(),
                                                        onChanged: (newValue) {
                                                          if (newValue !=
                                                              null) {
                                                            setDialogState(
                                                              () {
                                                                sub.hourType =
                                                                    newValue;
                                                              },
                                                            );
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),

                              const SizedBox(height: 15),

                              // ========================================
                              // HORAS GERAIS
                              // ========================================

                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: estimatedHoursController,
                                      readOnly: true,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 12,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Hs Estimadas (Calc.)',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: hourTypeController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 12,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Tipo de Horas Geral',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: leaderController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 12,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Líder Prj',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ==================================================
                    // RODAPÉ
                    // ==================================================

                    Container(
                      padding: const EdgeInsets.fromLTRB(
                        22,
                        13,
                        22,
                        13,
                      ),
                      decoration: BoxDecoration(
                        color: CoresTelas.fundoModalSecundario,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(18),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: savingLinks ? null : () => Navigator.of(
                              dialogContext,
                            ).pop(),
                            child: Text(
                              'Cancelar',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CoresApp.destaque,
                              foregroundColor: AppPalette.foregroundOn(CoresApp.destaque),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  TamanhosApp.raioBotao,
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.save_rounded,
                              size: 17,
                            ),
                            label: const Text(
                              'Salvar alterações',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            onPressed: savingLinks ? null : () async {
                              // ======================================
                              // ATUALIZA HORAS DAS ETAPAS
                              // ======================================

                              for (int i = 0; i < tempSubTasks.length; i++) {
                                tempSubTasks[i].estimatedHours =
                                    subHoursControllers[i].text.trim();
                              }

                              // ======================================
                              // ATUALIZA PROJETO
                              // ======================================

                              project.id = idController.text.trim();

                              project.client = clientController.text.trim();

                              project.status = selectedStatus;

                              project.serviceType =
                                  serviceTypeController.text.trim();

                              project.subTasks = tempSubTasks;

                              project.estimatedHours =
                                  estimatedHoursController.text.trim();

                              project.observacao =
                                  observacaoController.text.trim();

                              if (tempSubTasks.isNotEmpty) {
                                project.startDate =
                                    tempSubTasks.first.startDate;
                              }

                              project.leader = leaderController.text.trim();

                              project.hourType = hourTypeController.text.trim();

                              // ======================================
                              // SALVA
                              // ======================================

                              if (savingLinks) return;
                              setDialogState(() => savingLinks = true);
                              final previousFolderPath = linkEdit.previousFolder;
                              final previousExcelLink = linkEdit.previousExcel;
                              try {
                                final excelLink =
                                    ProjectFileService.editedReference(
                                        excelController.text,
                                        previousExcelLink);
                                project.folderPath =
                                    ProjectFileService.editedReference(
                                        folderController.text,
                                        previousFolderPath);
                                project.excelLink = excelLink;

                                await linkEdit.save(widget.firebaseService);

                                widget.onEditProject(
                                  project,
                                );

                                if (mounted && context.mounted) {
                                  setState(() {});
                                }

                                if (dialogContext.mounted) {
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                        'Trabalho salvo com sucesso no banco de dados!',
                                      ),
                                      backgroundColor: CoresApp.sucesso,
                                    ),
                                  );
                                  Navigator.of(dialogContext).pop();
                                }
                              } catch (e) {
                                if (dialogContext.mounted) {
                                  setDialogState(() => savingLinks = false);
                                }
                                var errorMessage = '$e';
                                if (dialogContext.mounted) {
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Erro ao salvar no Firebase: $errorMessage',
                                      ),
                                      backgroundColor: CoresApp.erro,
                                    ),
                                  );
                                }
                              }
                            },
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
    ).whenComplete(() {
      linksScrollController.dispose();
      idController.dispose();
      clientController.dispose();
      folderController.dispose();
      excelController.dispose();
      leaderController.dispose();
      serviceTypeController.dispose();
      hourTypeController.dispose();
      observacaoController.dispose();
      estimatedHoursController.dispose();

      for (final controller in subHoursControllers) {
        controller.dispose();
      }
    });
  }

  double checklistProgress(
    List<Map<String, dynamic>> checklist,
  ) {
    if (checklist.isEmpty) return 0;

    final completed =
        checklist.where((item) => item['completed'] == true).length;

    return completed / checklist.length;
  }

  List<DataRow> _generateRows(
    List<ProjectModel> projects,
  ) {
    final List<DataRow> rows = [];

    final now = DateTime.now();

    final todayFormatted = '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year.toString().substring(2)}';

    final listaAlertasNormalizada = widget.idsEmAlerta
        .map(
          (id) => id.toString().trim(),
        )
        .toList();

    for (final project in projects) {
      final isExpanded = widget.expandedProjectIds.contains(project.id);
      final isRowSelected = widget.selectedTargetId == project.id;

      final bool emAlerta =
          listaAlertasNormalizada.contains(project.id.toString().trim()) ||
              _projectHasDeadlineAlert(project);
      final bool dataVencida = _projectIsOverdue(project);

      final hasSubtasks = project.subTasks?.isNotEmpty ?? false;
      final startFormatted = _formatDate(project.startDate);

      final endFormatted = hasSubtasks && project.subTasks!.isNotEmpty
          ? project.subTasks!
                      .where(
                        (task) => task.planEnd != null,
                      )
                      .map(
                        (task) => task.planEnd!,
                      )
                      .fold<DateTime?>(
                    null,
                    (latest, date) {
                      if (latest == null || date.isAfter(latest)) {
                        return date;
                      }

                      return latest;
                    },
                  ) !=
                  null
              ? _formatDate(
                  project.subTasks!
                      .where(
                        (task) => task.planEnd != null,
                      )
                      .map(
                        (task) => task.planEnd!,
                      )
                      .reduce(
                        (a, b) => a.isAfter(b) ? a : b,
                      ),
                )
              : startFormatted
          : startFormatted;

      rows.add(
        DataRow(
          selected: isRowSelected,
          onSelectChanged: (_) => widget.onSelectTarget(project.id),
          color: WidgetStateProperty.resolveWith<Color?>(
            (states) {
              if (isRowSelected) {
                return CoresDashboard.tabelaLinhaSelecionada;
              }
              if (states.contains(WidgetState.hovered)) {
                return CoresDashboard.tabelaHover1;
              }

              if (isExpanded) {
                return CoresDashboard.tabelaLinhaExpandida;
              }

              return null;
            },
          ),
          cells: [
            DataCell(
              _buildProjectIdBadge(
                project,
                hasSubtasks,
                isExpanded,
                emAlerta,
              ),
            ),
            DataCell(
              _buildCellText(
                project.id2,
                color: CoresApp.textoSecundario,
              ),
            ),
            DataCell(
              _buildCellText(
                project.client,
                color: emAlerta
                    ? CoresApp.destaqueAmarelo
                    : CoresApp.textoPrincipal,
                fontWeight: FontWeight.w700,
              ),
            ),
            DataCell(
              _buildCellText(
                project.serviceType,
                color:
                    emAlerta ? AppPalette.secondary : CoresApp.textoSecundario,
              ),
            ),
            DataCell(
              _buildProjectActionControls(
                project: project,
                onDelete: () => widget.onDeleteProject(project),
                onAddSubTask: () => widget.onAddSubTask(project),
              ),
            ),
            DataCell(
              _buildStatusBadge(
                status: project.status,
                onChanged: (newStatus) async {
                  if (newStatus != null) {
                    try {
                      await widget.onProjectStatusChanged(
                        project,
                        newStatus,
                      );
                    } catch (e) {
                      if (!mounted || !context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Erro ao atualizar status: $e',
                          ),
                          backgroundColor: CoresApp.erro,
                        ),
                      );
                    }
                  }
                },
              ),
            ),
            DataCell(
              _buildDeadlineDateText(
                '$startFormatted - $endFormatted',
                overdue: dataVencida,
                normalColor: emAlerta
                    ? CoresApp.destaqueAmarelo
                    : CoresApp.textoSecundario,
                fontWeight: emAlerta ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            DataCell(
              _buildCellText(
                project.estimatedHours,
                color: emAlerta
                    ? CoresApp.destaqueAmarelo
                    : CoresApp.textoSecundario,
              ),
            ),
            DataCell(
              _buildCellText(
                project.leader,
                color:
                    emAlerta ? AppPalette.secondary : CoresApp.textoSecundario,
              ),
            ),
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCellText(
                    project.hourType,
                    color: emAlerta
                        ? AppPalette.secondary
                        : CoresApp.textoSecundario,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(5),
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: CoresApp.erro,
                      size: TamanhosApp.iconeAcao,
                    ),
                    tooltip: 'Excluir Trabalho',
                    onPressed: () => widget.onDeleteProject(project),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      if (isExpanded && project.subTasks != null) {
        for (final sub in project.subTasks!) {
          final subTargetId = '${project.id}_${sub.subId}';
          final isSubTargetActive = widget.activeTimerTargetId == subTargetId;
          final isSubRowSelected = widget.selectedTargetId == subTargetId;

          final subStartFormatted = _formatDate(sub.startDate);
          final subEndFormatted = sub.planEnd != null
              ? _formatDate(sub.planEnd!)
              : subStartFormatted;
          final bool subDataVencida = _taskIsOverdue(sub);

          rows.add(
            DataRow(
              selected: isSubRowSelected || isSubTargetActive,
              onSelectChanged: (_) => widget.onSelectTarget(
                subTargetId,
              ),
              color: WidgetStateProperty.resolveWith<Color?>(
                (states) {
                  if (isSubTargetActive) {
                    return CoresDashboard.tabelaLinhaExecucao;
                  }

                  if (isSubRowSelected) {
                    return CoresDashboard.tabelaLinhaSelecionada;
                  }

                  return CoresDashboard.tabelaLinhaEtapa;
                },
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
                      sub.subId,
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
                      project.client,
                      color: CoresApp.textoSecundario.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                DataCell(
                  _buildCellText(
                    project.serviceType,
                    color: CoresApp.textoSecundario.withValues(alpha: 0.65),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 210,
                    child: Row(
                      children: [
                        Expanded(
                          child: Tooltip(
                            message: sub.stage,
                            child: _buildCellText(
                              sub.stage,
                              color: _getStageColor(sub.status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildSubTaskActionControls(
                          project: project,
                          task: sub,
                          targetId: subTargetId,
                          title: 'Etapa ${sub.subId} - ${sub.stage}',
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  _buildStatusBadge(
                    status: sub.status,
                    onChanged: (newStatus) async {
                      if (newStatus != null) {
                        sub.status = newStatus;

                        try {
                          await widget.firebaseService.salvarProjeto(project);

                          widget.onSubTaskStatusChanged(
                            sub,
                            newStatus,
                          );
                        } catch (e) {
                          if (!mounted || !context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Erro ao atualizar status da etapa: $e',
                              ),
                              backgroundColor: CoresApp.erro,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                DataCell(
                  _buildDeadlineDateText(
                    '$subStartFormatted - $subEndFormatted',
                    overdue: subDataVencida,
                    normalColor: CoresApp.textoSecundario,
                  ),
                ),
                DataCell(
                  _buildCellText(
                    sub.estimatedHours,
                    color: CoresApp.textoSecundario,
                  ),
                ),
                DataCell(
                  _buildCellText(
                    project.leader,
                    color: CoresApp.textoSecundario,
                  ),
                ),
                DataCell(
                  _buildCellText(
                    sub.hourType,
                    color: CoresApp.textoSecundario,
                  ),
                ),
              ],
            ),
          );

          if (isSubTargetActive) {
            final startTimeFormatted = widget.activeStartTime != null
                ? '${widget.activeStartTime!.hour.toString().padLeft(2, '0')}:'
                    '${widget.activeStartTime!.minute.toString().padLeft(2, '0')}'
                : '';

            rows.add(
              _buildActiveRecordRow(
                project: project,
                task: sub,
                id: project.id,
                id2: sub.subId,
                client: project.client,
                serviceType: project.serviceType,
                todayFormatted: todayFormatted,
                startTimeFormatted: startTimeFormatted,
                durationFormatted: widget.formatDuration(
                  widget.secondsElapsed,
                ),
                targetId: subTargetId,
                title: 'Etapa ${sub.subId} - ${sub.stage}',
              ),
            );
          }

          final completedLogsSub = _localTimeLogs
              .where(
                (l) => l.targetId == subTargetId,
              )
              .toList();

          for (final log in completedLogsSub) {
            if (log.isRegistered) continue;

            rows.add(
              _buildSavedRecordRow(
                project: project,
                id: project.id,
                id2: sub.subId,
                client: project.client,
                serviceType: project.serviceType,
                log: log,
                estimatedHours: sub.estimatedHours,
                hourType: sub.hourType,
                targetId: subTargetId,
              ),
            );
          }
        }
      }
    }

    return rows;
  }

  DataRow _buildActiveRecordRow({
    required ProjectModel project,
    required TaskModel task,
    required String id,
    required String id2,
    required String client,
    required String serviceType,
    required String todayFormatted,
    required String startTimeFormatted,
    required String durationFormatted,
    required String targetId,
    required String title,
  }) {
    final activeColor = CoresDashboard.tabelaLinhaExecucao;

    return DataRow(
      color: WidgetStateProperty.all(activeColor),
      cells: [
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 7,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: CoresApp.destaque.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: CoresApp.destaque.withValues(alpha: 0.65),
              ),
            ),
            child: Text(
              id,
              style: TextStyle(
                color: CoresApp.destaque,
                fontSize: TamanhosApp.tabelaFonteSecundaria,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        DataCell(
          Text(
            id2,
            style: TextStyle(
              color: CoresApp.destaque,
              fontSize: TamanhosApp.tabelaFonteSecundaria,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        DataCell(
          _buildCellText(
            client,
            color: CoresApp.textoPrincipal,
          ),
        ),
        DataCell(
          _buildCellText(
            serviceType,
            color: CoresApp.textoPrincipal,
          ),
        ),
        const DataCell(
          SizedBox.shrink(),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: CoresApp.destaque,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              'EA',
              style: TextStyle(
                color: AppPalette.onPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        DataCell(
          Tooltip(
            message: 'Início: $startTimeFormatted | Tempo: $durationFormatted',
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: CoresApp.aviso,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'EM EXECUÇÃO  $startTimeFormatted | $durationFormatted',
                style: TextStyle(
                  color: AppPalette.onPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '-',
                style: TextStyle(
                  color: CoresApp.textoFraco,
                ),
              ),
              const SizedBox(width: 6),
              if (widget.timerState == TimerState.running) ...[
                _buildActionIconButton(
                  icon: Icons.pause_circle_filled_rounded,
                  color: CoresApp.destaqueAmarelo,
                  tooltip: 'Pausar',
                  onPressed: widget.onPauseTimer,
                ),
                _buildActionIconButton(
                  icon: Icons.stop_circle_rounded,
                  color: CoresApp.erro,
                  tooltip: 'Stop',
                  onPressed: widget.onStopTimer,
                ),
              ] else if (widget.timerState == TimerState.paused) ...[
                _buildActionIconButton(
                  icon: Icons.play_circle_fill_rounded,
                  color: CoresDashboard.statusTrabalhando,
                  tooltip: 'Retomar',
                  onPressed: () => widget.onStartTimer(
                    targetId,
                  ),
                ),
                _buildActionIconButton(
                  icon: Icons.stop_circle_rounded,
                  color: CoresApp.erro,
                  tooltip: 'Stop',
                  onPressed: widget.onStopTimer,
                ),
              ],
              _buildActionIconButton(
                icon: Icons.more_time_rounded,
                color: CoresApp.destaque,
                tooltip: 'Adicionar Horas Manualmente',
                onPressed: () => widget.onManualTime(
                  title,
                ),
              ),
              _buildActionIconButton(
                icon: Icons.delete_outline_rounded,
                color: CoresApp.erro,
                tooltip: 'Descartar Execução Atual',
                onPressed: () {
                  widget.onStopTimer();
                  setState(() {});
                },
              ),
              const SizedBox(width: 2),
              IconButton(
                icon: Icon(
                  Icons.task_alt_rounded,
                  color: CoresApp.destaque,
                  size: TamanhosApp.iconeAcao,
                ),
                tooltip: 'Marcar Etapa como Realizada',
                onPressed: () async {
                  task.status = 'TRAB';

                  try {
                    await widget.firebaseService.salvarProjeto(project);

                    widget.onMarkTaskCompleted(
                      task,
                    );

                    if (mounted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Etapa ${task.subId} marcada como realizada e salva!',
                          ),
                          backgroundColor: CoresApp.sucesso,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Erro ao salvar no Firebase: $e',
                          ),
                          backgroundColor: CoresApp.erro,
                        ),
                      );
                    }
                  }
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.playlist_add_check_rounded,
                  color: CoresDashboard.statusTrabalhando,
                  size: 21,
                ),
                tooltip: 'Adicionar e Salvar Tempo',
                onPressed: widget.onStopTimer,
              ),
            ],
          ),
        ),
        DataCell(
          Text(
            '-',
            style: TextStyle(
              color: CoresApp.textoFraco,
            ),
          ),
        ),
        DataCell(
          _buildCellText(
            '-',
            color: CoresApp.textoSecundario,
          ),
        ),
      ],
    );
  }

  DataRow _buildSavedRecordRow({
    required ProjectModel project,
    required String id,
    required String id2,
    required String client,
    required String serviceType,
    required TimeLog log,
    required String estimatedHours,
    required String hourType,
    required String targetId,
  }) {
    final dateFormatted = _formatDate(log.date);
    final bool showCadastrarHere = !log.isRegistered;

    return DataRow(
      color: WidgetStateProperty.all(
        CoresDashboard.tabelaLinhaRegistrada,
      ),
      cells: [
        DataCell(
          _buildCellText(
            id,
            color: CoresApp.textoSecundario,
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
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            serviceType,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          SizedBox(
            width: 150,
            height: 30,
            child: TextField(
              controller: _getLogCommentController(
                log,
              ),
              style: TextStyle(
                color: CoresApp.textoPrincipal,
                fontSize: TamanhosApp.tabelaFonte,
              ),
              decoration: InputDecoration(
                hintText: 'Comentário do registro...',
                hintStyle: TextStyle(
                  color: CoresApp.textoSecundario.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                filled: true,
                fillColor: CoresTelas.campoFormulario.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: CoresApp.bordaSuave,
                    width: TamanhosApp.espessuraBorda,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: CoresApp.bordaSuave,
                    width: TamanhosApp.espessuraBorda,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: CoresApp.destaque,
                    width: TamanhosApp.espessuraBorda,
                  ),
                ),
              ),
              onSubmitted: (value) async {
                log.description = value.trim();

                try {
                  await widget.firebaseService.salvarProjeto(project);

                  widget.onEditLog(log);

                  if (!mounted || !context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Comentário do registro salvo com sucesso!',
                      ),
                      backgroundColor: CoresApp.sucesso,
                      duration: const Duration(
                        seconds: 1,
                      ),
                    ),
                  );
                } catch (e) {
                  if (!mounted || !context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao salvar comentário: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                    ),
                  );
                }
              },
            ),
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: CoresApp.sucesso.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: CoresApp.sucesso.withValues(alpha: 0.7),
              ),
            ),
            child: Text(
              'TRAB',
              style: TextStyle(
                color: CoresDashboard.statusTrabalhando,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        DataCell(
          // CORREÇÃO APLICADA: Uso de Flexible/Overflow gerencimento na célula de data/hora + botão
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '$dateFormatted (${log.startTime} - ${log.endTime} | ${log.durationFormatted})',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CoresDashboard.statusTrabalhando,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (showCadastrarHere) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    minimumSize: const Size(0, 28),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        TamanhosApp.raioBotao,
                      ),
                    ),
                  ),
                  icon: const Icon(
                    Icons.cloud_upload_outlined,
                    size: 14,
                  ),
                  label: const Text(
                    'Cadastrar',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () => _handleRegisterLog(
                    log,
                  ),
                ),
              ],
            ],
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCellText(
                estimatedHours,
                color: CoresApp.textoSecundario,
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.check_circle_rounded,
                color: CoresApp.sucesso,
                size: 19,
              ),
              const SizedBox(width: 5),
              IconButton(
                icon: Icon(
                  Icons.edit_rounded,
                  color: CoresApp.destaqueAmarelo,
                  size: 18,
                ),
                tooltip: 'Editar Horário',
                onPressed: () => widget.onEditLog(
                  log,
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: CoresApp.erro,
                  size: 18,
                ),
                tooltip: 'Excluir Apontamento',
                onPressed: () {
                  setState(() {
                    _localTimeLogs.remove(log);
                  });

                  widget.onDeleteLog(log);
                },
              ),
            ],
          ),
        ),
        DataCell(
          _buildCellText(
            '-',
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            hourType,
            color: CoresApp.textoSecundario,
          ),
        ),
      ],
    );
  }

  Widget _buildProjectActionControls({
    required ProjectModel project,
    VoidCallback? onDelete,
    VoidCallback? onAddSubTask,
    VoidCallback? onActionSelected,
  }) {
    final hasFolder =
        project.folderPath != null && project.folderPath!.trim().isNotEmpty;
    final hasExcel =
        project.excelLink != null && project.excelLink!.trim().isNotEmpty;

    final user = Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser;
    if (PilotFeatureAccess.allows(uid: user?.uid, email: user?.email)) {
      void run(VoidCallback action) {
        final current = FirebaseAuth.instance.currentUser;
        if (current?.uid != user?.uid || !PilotFeatureAccess.allows(uid: current?.uid, email: current?.email)) return;
        onActionSelected?.call();
        action();
      }
      return ProjectActionsPilot(hasFolder: hasFolder, hasExcel: hasExcel,
        onFolder: () => run(() async {
          try {
            final reference = project.folderPath!;
            if (ProjectStorageService.isStorageReference(reference)) {
              await showProjectStorageFilesDialog(context, folderReference: reference);
            } else {
              await ProjectFileService.openFile(reference, projectId: project.id, field: 'folderPath');
            }
          } catch (e) { if (mounted && context.mounted) showLocalFileError(context, e, resource: 'a pasta'); }
        }),
        onExcel: () => run(() async {
          try { await ProjectFileService.openFile(project.excelLink!, projectId: project.id, field: 'excelLink'); }
          catch (e) { if (mounted && context.mounted) showLocalFileError(context, e, resource: 'a planilha'); }
        }),
        onEditSpreadsheet: () => run(() { ProjectSpreadsheetDialog.show(context, project); }),
        onEditWork: () => run(() => _showLinksDialog(project)),
        onChecklist: () => run(() => _showCheckListDialog(project)),
        onComment: () => run(() { ComentarioModal.show(context, project); }),
        onEmail: () => run(() { ProjectEmailModal.show(context, project); }),
        onAudit: () => run(() { WorkAuditDialog.show(context, widget.auditProjects ?? widget.projects, selectedProject: project); }));
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 3,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: CoresApp.textoPrincipal.withValues(alpha: 0.018),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.folder_rounded,
              color: hasFolder
                  ? CoresApp.destaque
                  : CoresApp.textoSecundario.withValues(alpha: 0.3),
              size: TamanhosApp.iconeAcao,
            ),
            tooltip: hasFolder
                ? 'Abrir Pasta: ${project.folderPath}'
                : 'Nenhuma pasta definida',
            onPressed: hasFolder
                ? () async {
                    onActionSelected?.call();
                    try {
                      final reference = project.folderPath!;
                      if (ProjectStorageService.isStorageReference(reference)) {
                        if (kIsWeb && !WebConfig.storageEnabled) {
                          throw StateError(
                              'O armazenamento de anexos não está configurado.');
                        }
                        await showProjectStorageFilesDialog(context,
                            folderReference: reference);
                      } else {
                        await ProjectFileService.openFile(reference, projectId: project.id, field: 'folderPath');
                      }
                    } catch (e) {
                      if (mounted && context.mounted) {
                        showLocalFileError(context, e, resource: 'a pasta');
                      }
                    }
                  }
                : null,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.insert_drive_file_rounded,
              color: hasExcel
                  ? CoresDashboard.statusTrabalhando
                  : CoresApp.textoSecundario.withValues(alpha: 0.3),
              size: TamanhosApp.iconeAcao,
            ),
            tooltip: hasExcel
                ? 'Abrir Arquivo/Excel: ${project.excelLink}'
                : 'Nenhum arquivo/link definido',
            onPressed: hasExcel
                ? () async {
                    onActionSelected?.call();
                    try {
                      await ProjectFileService.openFile(project.excelLink!, projectId: project.id, field: 'excelLink');
                    } catch (e) {
                      if (mounted && context.mounted) {
                        showLocalFileError(context, e, resource: 'o arquivo ou planilha');
                      }
                    }
                  }
                : null,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.edit_rounded,
              color: AppPalette.secondary,
              size: TamanhosApp.iconeAcao,
            ),
            tooltip: 'Editar Trabalho',
            onPressed: () {
              onActionSelected?.call();
              _showLinksDialog(project);
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.checklist_rounded,
              color: AppPalette.secondary,
              size: TamanhosApp.iconeAcao,
            ),
            tooltip: 'Checklist',
            onPressed: () {
              onActionSelected?.call();
              _showCheckListDialog(project);
            },
          ),

          //////////////////////////////////////////////
          /// Enviar comentário para o E-desk
          /// ///////////////////////////////////////////

          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Enviar Comentário E-desk',
            icon: Icon(
              Icons.comment_rounded,
              color: AppPalette.secondary,
              size: TamanhosApp.iconeAcao,
            ),
            onPressed: () {
              onActionSelected?.call();
              ComentarioModal.show(context, project);
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'E-mails do projeto',
            icon: CustomPaint(
              size: Size.square(TamanhosApp.iconeAcao),
              painter: _ProjectEmailIconPainter(AppPalette.secondary),
            ),
            onPressed: () {
              onActionSelected?.call();
              ProjectEmailModal.show(context, project);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSubTaskActionControls({
    required ProjectModel project,
    required TaskModel task,
    required String targetId,
    required String title,
  }) {
    final isCurrentTarget = widget.activeTimerTargetId == targetId;
    final isRunning =
        isCurrentTarget && widget.timerState == TimerState.running;
    final isPaused = isCurrentTarget && widget.timerState == TimerState.paused;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isRunning) ...[
          _buildActionIconButton(
            icon: Icons.pause_circle_filled_rounded,
            color: CoresApp.destaqueAmarelo,
            tooltip: 'Pausar',
            onPressed: widget.onPauseTimer,
          ),
          _buildActionIconButton(
            icon: Icons.stop_circle_rounded,
            color: CoresApp.erro,
            tooltip: 'Stop',
            onPressed: widget.onStopTimer,
          ),
        ] else if (isPaused) ...[
          _buildActionIconButton(
            icon: Icons.play_circle_fill_rounded,
            color: CoresDashboard.statusTrabalhando,
            tooltip: 'Retomar',
            onPressed: () => widget.onStartTimer(
              targetId,
            ),
          ),
          _buildActionIconButton(
            icon: Icons.stop_circle_rounded,
            color: CoresApp.erro,
            tooltip: 'Stop',
            onPressed: widget.onStopTimer,
          ),
        ] else ...[
          _buildActionIconButton(
            icon: Icons.play_circle_fill_rounded,
            color: CoresDashboard.statusTrabalhando,
            tooltip: 'Iniciar Cronômetro',
            onPressed: () => widget.onStartTimer(
              targetId,
            ),
          ),
        ],
        _buildActionIconButton(
          icon: Icons.more_time_rounded,
          color: AppPalette.secondary,
          tooltip: 'Adicionar Horas Manualmente',
          onPressed: () => widget.onManualTime(
            title,
          ),
        ),
        _buildActionIconButton(
          icon: Icons.delete_outline_rounded,
          color: CoresApp.erro,
          tooltip: 'Excluir Subtrabalho',
          onPressed: () async {
            final bool? confirmar = await showDialog<bool>(
              context: context,
              builder: (BuildContext dialogContext) {
                AppAppearance.watch(dialogContext);

                return AlertDialog(
                  backgroundColor: CoresTelas.fundoModal,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      16,
                    ),
                    side: BorderSide(
                      color: CoresApp.borda,
                    ),
                  ),
                  title: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: CoresApp.erro,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Confirmar Exclusão',
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  content: Text(
                    'Deseja realmente excluir a etapa "${task.subId} - ${task.stage}"? Esta ação não poderá ser desfeita.',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                      fontSize: 13,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(false),
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
                        foregroundColor: AppPalette.foregroundOn(CoresApp.erro),
                      ),
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(true),
                      child: const Text(
                        'Excluir',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );

            if (confirmar != true) return;

            project.subTasks?.removeWhere(
              (s) => s.subId == task.subId,
            );

            setState(() {});

            try {
              await widget.firebaseService.salvarProjeto(project);

              widget.onEditProject(
                project,
              );

              if (mounted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Etapa excluída com sucesso!',
                    ),
                    backgroundColor: CoresApp.sucesso,
                  ),
                );
              }
            } catch (e) {
              if (mounted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Erro ao excluir etapa: $e',
                    ),
                    backgroundColor: CoresApp.erro,
                  ),
                );
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildActionIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(5),
      constraints: const BoxConstraints(
        minWidth: 30,
        minHeight: 30,
      ),
      icon: Icon(
        icon,
        color: color,
        size: TamanhosApp.iconeAcao,
      ),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final rows = _generateRows(widget.projects);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: CoresDashboard.tabelaFundo,
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioTabela,
        ),
        border: Border.all(
          color: CoresDashboard.tabelaBorda,
          width: TamanhosApp.espessuraBorda,
        ),
        boxShadow: AppVisuals.shadows,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 1,
            decoration: BoxDecoration(
              color: AppVisuals.divider,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(
                  TamanhosApp.raioTabela,
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 350,
              maxHeight: 700,
            ),
            child: Scrollbar(
              controller: widget.verticalController,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller: widget.verticalController,
                scrollDirection: Axis.vertical,
                child: Scrollbar(
                  controller: widget.horizontalController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: SingleChildScrollView(
                    controller: widget.horizontalController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 20),
                    child: SizedBox(
                      width: 1500,
                      child: DataTable(
                        showCheckboxColumn: false,
                        columnSpacing: 16.0,
                        horizontalMargin: 16.0,
                        headingRowHeight: 48,
                        dataRowMinHeight: 32,
                        dataRowMaxHeight: 40,
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
                            label: _buildTableHeader('Etapa / Ações'),
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
                        ],
                        rows: rows,
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
}
