import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import '../widgets/edesk_phase_send_button.dart';
import 'package:gerenciador_horas/core/platform/local_files.dart';
import 'package:gerenciador_horas/data/services/project_file_service.dart';
import 'package:gerenciador_horas/data/services/project_reference_save.dart';
import 'package:gerenciador_horas/data/services/browser_local_files_service.dart';
import '../widgets/project_reference_field.dart';
import 'package:gerenciador_horas/core/config/web_config.dart';
import 'package:gerenciador_horas/features/projects/widgets/project_storage_files_dialog.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'project_archive_dialog.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/data/services/edesk_service.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/project_storage_service.dart';
import 'package:gerenciador_horas/domain/models/checklist_format_model.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';

class ProjectFormDialog extends StatefulWidget {
  final List<WorkFormat> workFormats;
  final ProjectModel? projectToEdit;

  const ProjectFormDialog({
    super.key,
    required this.workFormats,
    this.projectToEdit,
    Object? firebaseService,
  });

  @override
  State<ProjectFormDialog> createState() => _ProjectFormDialogState();
}

///
/// Formata a entrada de horas:
///
/// 1    -> 00:01
/// 10   -> 00:10
/// 100  -> 01:00
/// 130  -> 01:30
/// 1230 -> 12:30
///
class HoursInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 4) {
      digits = digits.substring(0, 4);
    }

    String formatted = digits;

    if (digits.length >= 3) {
      formatted =
          '${digits.substring(0, digits.length - 2)}:${digits.substring(digits.length - 2)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: formatted.length,
      ),
    );
  }
}

class _ProjectFormDialogState extends State<ProjectFormDialog> {
  final FirebaseService _firebaseService = FirebaseService();

  final TextEditingController _idController = TextEditingController();
  final TextEditingController _clientController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _leaderController = TextEditingController();
  final TextEditingController _excelLinkController = TextEditingController();
  final TextEditingController _folderPathController = TextEditingController();
  late final String? _initialFolderReference, _initialExcelReference;

  final EdeskService _edeskService = EdeskService();

  WorkFormat? _selectedWorkFormat;

  String _status = 'INI_PRI';
  String _hourType = 'Hs Cobradas';

  late DateTime _startDate;

  List<Map<String, dynamic>> _internalWorks = [];

  bool _isSaving = false;

  // ============================================================
  // E-DESK
  // ============================================================

  bool _isUpdatingEdesk = false;
  final Set<int> _selectedEdeskPhaseIndices = {};

  // ============================================================
  // CHECKLIST
  // ============================================================

  List<ChecklistFormat> _checklistFormats = [];

  ChecklistFormat? _selectedChecklistFormat;

  List<Map<String, dynamic>> _checklistItems = [];

  bool _loadingChecklistFormats = true;

  final TextEditingController _newChecklistItemController =
      TextEditingController();

  bool get _isEditing => widget.projectToEdit != null;

  // ============================================================
  // INIT STATE
  // ============================================================

  @override
  void initState() {
    super.initState();

    final project = widget.projectToEdit;
    _initialFolderReference = project?.folderPath;
    _initialExcelReference = project?.excelLink;

    // ----------------------------------------------------------
    // VALORES DO PROJETO
    // ----------------------------------------------------------

    if (project != null) {
      _idController.text = project.id;
      _clientController.text = project.client;
      _emailController.text = project.email ?? '';
      _leaderController.text = project.leader;

      _status = project.status;
      _hourType = project.hourType;

      _excelLinkController.text = project.excelLink ?? '';
      _folderPathController.text = project.folderPath ?? '';

      // --------------------------------------------------------
      // DATA INICIAL
      // --------------------------------------------------------

      _startDate = _onlyDate(project.startDate);

      if (project.subTasks != null && project.subTasks!.isNotEmpty) {
        final firstTask = project.subTasks!.first;

        _startDate = _onlyDate(
          firstTask.planStart ?? firstTask.startDate,
        );
      }

      debugPrint('====================================');
      debugPrint('EDITANDO PROJETO');
      debugPrint('ID: ${project.id}');
      debugPrint('CLIENTE: ${project.client}');
      debugPrint('DATA PROJETO: ${project.startDate}');
      debugPrint('SUBTASKS: ${project.subTasks?.length}');
      debugPrint(
        'CHECKLIST EXISTENTE: ${project.checklist.length}',
      );
      debugPrint('====================================');

      if (project.subTasks != null) {
        for (final task in project.subTasks!) {
          debugPrint(
            'ETAPA: ${task.stage} | '
            'subId: ${task.subId} | '
            'startDate: ${task.startDate} | '
            'planStart: ${task.planStart} | '
            'planEnd: ${task.planEnd} | '
            'E-Desk Solicitação: ${task.edeskSolicitacao} | '
            'E-Desk Trabalho: ${task.edeskIdTrabalho} | '
            'E-Desk URL: ${task.edeskUrl}',
          );
        }
      }

      // --------------------------------------------------------
      // CHECKLIST EXISTENTE
      // --------------------------------------------------------

      if (project.checklist.isNotEmpty) {
        _checklistItems = project.checklist
            .map(
              (item) => Map<String, dynamic>.from(item),
            )
            .toList();

        debugPrint(
          'CHECKLIST CARREGADO DO PROJETO: ${_checklistItems.length}',
        );
      }
    } else {
      // --------------------------------------------------------
      // NOVO PROJETO
      // --------------------------------------------------------

      final now = DateTime.now();

      _startDate = DateTime(
        now.year,
        now.month,
        now.day,
      );
    }

    // ------------------------------------------------------------
    // TIPO DE SERVIÇO
    // ------------------------------------------------------------

    if (widget.workFormats.isNotEmpty) {
      if (project != null) {
        _selectedWorkFormat = widget.workFormats.firstWhere(
          (wf) =>
              wf.name.trim().toLowerCase() ==
              project.serviceType.trim().toLowerCase(),
          orElse: () => widget.workFormats.first,
        );
      } else {
        _selectedWorkFormat = widget.workFormats.first;
      }

      _updateInternalWorks(
        _selectedWorkFormat!,
        existingProject: project,
      );
    }

    // ------------------------------------------------------------
    // CHECKLIST
    // ------------------------------------------------------------

    _loadChecklistFormats();
  }

  // ============================================================
  // CHECKLIST - CARREGAR MODELOS
  // ============================================================

  Future<void> _loadChecklistFormats() async {
    try {
      final formats = await _firebaseService.getChecklistFormats();

      if (!mounted || !context.mounted) {
        return;
      }

      setState(() {
        _checklistFormats = formats;
        _loadingChecklistFormats = false;
      });

      debugPrint('==========================================');
      debugPrint('MODELOS DE CHECKLIST CARREGADOS');
      debugPrint('TOTAL: ${formats.length}');

      for (final format in formats) {
        debugPrint(
          'MODELO: ${format.name} | '
          'ID: ${format.id} | '
          'ITENS: ${format.items.length}',
        );
      }

      debugPrint('==========================================');

      if (_isEditing &&
          _checklistItems.isNotEmpty &&
          _selectedChecklistFormat == null &&
          formats.isNotEmpty) {
        final ChecklistFormat? matchedFormat =
            _findMatchingChecklistFormat(formats);

        if (matchedFormat != null && mounted) {
          setState(() {
            _selectedChecklistFormat = matchedFormat;
          });
        }
      }
    } catch (e) {
      debugPrint(
        'ERRO AO CARREGAR MODELOS DE CHECKLIST: $e',
      );

      if (!mounted || !context.mounted) {
        return;
      }

      setState(() {
        _loadingChecklistFormats = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível carregar os modelos de Check List: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ============================================================
  // CHECKLIST - ENCONTRAR MODELO
  // ============================================================

  ChecklistFormat? _findMatchingChecklistFormat(
    List<ChecklistFormat> formats,
  ) {
    final existingNames = _checklistItems
        .map(
          (item) => item['name']?.toString().trim().toLowerCase() ?? '',
        )
        .where(
          (name) => name.isNotEmpty,
        )
        .toSet();

    if (existingNames.isEmpty) {
      return null;
    }

    ChecklistFormat? bestMatch;
    int bestMatchCount = 0;

    for (final format in formats) {
      int matchCount = 0;

      for (final item in format.items) {
        final name = item['name']?.toString().trim().toLowerCase() ?? '';

        if (name.isNotEmpty && existingNames.contains(name)) {
          matchCount++;
        }
      }

      if (matchCount > bestMatchCount) {
        bestMatchCount = matchCount;
        bestMatch = format;
      }
    }

    return bestMatch;
  }

  // ============================================================
  // CHECKLIST - APLICAR MODELO
  // ============================================================

  void _applyChecklistFormat(
    ChecklistFormat? format,
  ) {
    if (format == null || !mounted) {
      return;
    }

    debugPrint('==========================================');
    debugPrint('APLICANDO MODELO DE CHECKLIST');
    debugPrint('MODELO: ${format.name}');
    debugPrint('ID: ${format.id}');
    debugPrint('ITENS: ${format.items.length}');
    debugPrint('==========================================');

    final List<Map<String, dynamic>> newItems = [];

    for (int index = 0; index < format.items.length; index++) {
      final item = format.items[index];

      final String name = item['name']?.toString().trim() ?? '';

      if (name.isEmpty) {
        continue;
      }

      newItems.add(
        {
          'order': item['order']?.toString().isNotEmpty == true
              ? item['order'].toString()
              : (index + 1).toString(),
          'name': name,
          'completed': false,
          'source': 'model',
          'modelId': format.id,
          'modelName': format.name,
        },
      );
    }

    setState(() {
      _selectedChecklistFormat = format;
      _checklistItems = newItems;
    });

    debugPrint(
      'CHECKLIST APLICADO: ${_checklistItems.length} itens',
    );
  }

  // ============================================================
  // CHECKLIST - ADICIONAR ITEM
  // ============================================================

  Future<void> _addChecklistItem() async {
    _newChecklistItemController.clear();

    final String? itemName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return AlertDialog(
          backgroundColor: AppPalette.surface,
          title: Text(
            'Adicionar item ao Check List',
            style: TextStyle(
              color: AppPalette.text,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: _newChecklistItemController,
              autofocus: true,
              style: TextStyle(
                color: AppPalette.text,
              ),
              onSubmitted: (value) {
                final text = value.trim();

                if (text.isNotEmpty) {
                  Navigator.of(dialogContext).pop(text);
                }
              },
              decoration: InputDecoration(
                labelText: 'Descrição do item',
                labelStyle: TextStyle(
                  color: AppPalette.secondary,
                ),
                hintText: 'Digite o item do Check List',
                hintStyle: TextStyle(
                  color: AppPalette.border,
                ),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: AppPalette.secondary,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.accent,
                foregroundColor: AppPalette.foregroundOn(AppPalette.accent),
              ),
              onPressed: () {
                final text = _newChecklistItemController.text.trim();

                if (text.isNotEmpty) {
                  Navigator.of(dialogContext).pop(text);
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

    if (itemName == null || itemName.trim().isEmpty || !mounted) {
      return;
    }

    setState(() {
      _checklistItems.add(
        {
          'order': (_checklistItems.length + 1).toString(),
          'name': itemName.trim(),
          'completed': false,
          'source': 'manual',
          'modelId': null,
          'modelName': null,
        },
      );
    });
  }

  // ============================================================
  // CHECKLIST - REMOVER ITEM
  // ============================================================

  void _removeChecklistItem(
    int index,
  ) {
    if (index < 0 || index >= _checklistItems.length || !mounted) {
      return;
    }

    final item = _checklistItems[index];

    final String source = item['source']?.toString() ?? 'model';

    setState(() {
      _checklistItems.removeAt(index);

      for (int i = 0; i < _checklistItems.length; i++) {
        _checklistItems[i]['order'] = (i + 1).toString();
      }
    });

    debugPrint(
      'ITEM REMOVIDO DO PROJETO: '
      '${item['name']} | source=$source',
    );
  }

  // ============================================================
  // CHECKLIST - MARCAR
  // ============================================================

  void _toggleChecklistItem(
    int index,
    bool? value,
  ) {
    if (index < 0 || index >= _checklistItems.length || !mounted) {
      return;
    }

    setState(() {
      _checklistItems[index]['completed'] = value == true;
    });
  }

  // ============================================================
  // CHECKLIST - PREPARAR PARA SALVAR
  // ============================================================

  List<Map<String, dynamic>> _buildChecklistForSave() {
    final List<Map<String, dynamic>> result = [];

    for (int index = 0; index < _checklistItems.length; index++) {
      final item = Map<String, dynamic>.from(
        _checklistItems[index],
      );

      final String name = item['name']?.toString().trim() ?? '';

      if (name.isEmpty) {
        continue;
      }

      result.add(
        {
          'order': (index + 1).toString(),
          'name': name,
          'completed': item['completed'] == true,
          'source': item['source']?.toString() ?? 'manual',
          'modelId': item['modelId'],
          'modelName': item['modelName'],
        },
      );
    }

    return result;
  }

  // ============================================================
  // TRABALHO - OBTER NOME
  // ============================================================

  String _getWorkName(dynamic rawStep, int index) =>
      workStepName(rawStep, index);

  // ============================================================
  // DATAS
  // ============================================================

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year.toString().padLeft(4, '0')}';
  }

  DateTime _onlyDate(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    );
  }

  // ============================================================
  // SELETOR DE DATA
  // ============================================================

  Future<DateTime?> _selectDate({
    required DateTime initialDate,
  }) async {
    DateTime selectedDate = _onlyDate(initialDate);

    final DateTime firstDate = DateTime(
      2000,
      1,
      1,
    );

    final DateTime lastDate = DateTime(
      2100,
      12,
      31,
    );

    if (selectedDate.isBefore(firstDate)) {
      selectedDate = firstDate;
    }

    if (selectedDate.isAfter(lastDate)) {
      selectedDate = lastDate;
    }

    try {
      final DateTime? result = await showDialog<DateTime>(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext dialogContext) {
          AppAppearance.watch(dialogContext);

          DateTime temporaryDate = selectedDate;

          return Localizations.override(
            context: dialogContext,
            locale: const Locale('pt', 'BR'),
            child: Dialog(
              backgroundColor: AppPalette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: StatefulBuilder(
                builder: (
                  BuildContext context,
                  StateSetter setDialogState,
                ) {
                  AppAppearance.watch(context);

                  return ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 320,
                      maxWidth: 420,
                      minHeight: 430,
                      maxHeight: 560,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFF5252,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.calendar_month,
                                  color: Color(0xFFFF5252),
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Selecionar data',
                                  style: TextStyle(
                                    color: AppPalette.text,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Fechar',
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                },
                                icon: Icon(
                                  Icons.close,
                                  color: AppPalette.secondary,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppPalette.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppPalette.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.event,
                                  color: Color(0xFFFF5252),
                                  size: 19,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _formatDate(temporaryDate),
                                    style: TextStyle(
                                      color: AppPalette.text,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 330,
                            child: CalendarDatePicker(
                              initialDate: temporaryDate,
                              firstDate: firstDate,
                              lastDate: lastDate,
                              onDateChanged: (DateTime date) {
                                setDialogState(() {
                                  temporaryDate = _onlyDate(date);
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                },
                                child: Text(
                                  'Cancelar',
                                  style: TextStyle(
                                    color: AppPalette.secondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop(
                                    _onlyDate(temporaryDate),
                                  );
                                },
                                icon: const Icon(
                                  Icons.check,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Confirmar',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppPalette.accent,
                                  foregroundColor: AppPalette.foregroundOn(
                                      AppPalette.accent),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 11,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      );

      if (result == null) {
        return null;
      }

      return _onlyDate(result);
    } catch (e, stackTrace) {
      debugPrint('==========================================');
      debugPrint('ERRO AO ABRIR CALENDÁRIO');
      debugPrint('DATA RECEBIDA: $initialDate');
      debugPrint('DATA NORMALIZADA: $selectedDate');
      debugPrint('ERRO: $e');
      debugPrint('STACK TRACE: $stackTrace');
      debugPrint('==========================================');

      if (!mounted || !context.mounted) {
        return null;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível abrir o calendário: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );

      return null;
    }
  }

  // ============================================================
  // EDITAR DATA DE INÍCIO
  // ============================================================

  Future<void> _editStartDate(
    Map<String, dynamic> work,
  ) async {
    final dynamic rawStartDate = work['startDate'];
    final dynamic rawEndDate = work['endDate'];

    if (rawStartDate is! DateTime || rawEndDate is! DateTime) {
      debugPrint(
        'ERRO: datas inválidas no trabalho ${work['name']}',
      );

      if (!mounted || !context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível editar a data desta etapa.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );

      return;
    }

    final DateTime currentDate = _onlyDate(
      rawStartDate,
    );

    final DateTime endDate = _onlyDate(
      rawEndDate,
    );

    final DateTime? picked = await _selectDate(
      initialDate: currentDate,
    );

    if (picked == null || !mounted) {
      return;
    }

    if (picked.isAfter(endDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A data de início não pode ser posterior à data de término.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );

      return;
    }

    setState(() {
      work['startDate'] = picked;

      if (_internalWorks.isNotEmpty &&
          identical(
            work,
            _internalWorks.first,
          )) {
        _startDate = picked;
      }
    });
  }

  // ============================================================
  // EDITAR DATA DE TÉRMINO
  // ============================================================

  Future<void> _editEndDate(
    Map<String, dynamic> work,
  ) async {
    final dynamic rawStartDate = work['startDate'];
    final dynamic rawEndDate = work['endDate'];

    if (rawStartDate is! DateTime || rawEndDate is! DateTime) {
      if (!mounted || !context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível editar a data desta etapa.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );

      return;
    }

    final DateTime currentDate = _onlyDate(
      rawEndDate,
    );

    final DateTime startDate = _onlyDate(
      rawStartDate,
    );

    final DateTime? picked = await _selectDate(
      initialDate: currentDate,
    );

    if (picked == null || !mounted) {
      return;
    }

    if (picked.isBefore(startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A data de término não pode ser anterior à data de início.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );

      return;
    }

    setState(() {
      work['endDate'] = picked;
    });
  }

  // ============================================================
  // TRABALHOS INTERNOS
  // ============================================================

  void _disposeInternalControllers() {
    for (final work in _internalWorks) {
      final controller = work['controller'];

      if (controller is TextEditingController) {
        controller.dispose();
      }
    }
  }

  void _updateInternalWorks(
    WorkFormat workFormat, {
    ProjectModel? existingProject,
  }) {
    for (final work in _internalWorks) {
      final controller = work['controller'];

      if (controller is TextEditingController) {
        controller.dispose();
      }
    }

    DateTime baseDate = _onlyDate(_startDate);

    final List<TaskModel> existingTasks =
        existingProject?.subTasks ?? <TaskModel>[];

    _selectedEdeskPhaseIndices.clear();
    _internalWorks = List.generate(
      workFormat.steps.length,
      (index) {
        final dynamic rawStep = workFormat.steps[index];

        final String workName = _getWorkName(
          rawStep,
          index,
        );

        DateTime stepStart = baseDate;
        DateTime stepEnd = baseDate;

        String hoursText = '00:00';

        String subId = (index + 1).toString();

        TaskModel? existingTask;

        if (existingTasks.isNotEmpty) {
          for (final task in existingTasks) {
            if (task.stage.trim().toLowerCase() ==
                workName.trim().toLowerCase()) {
              existingTask = task;
              break;
            }
          }

          if (existingTask == null && index < existingTasks.length) {
            existingTask = existingTasks[index];
          }
        }

        if (existingTask != null) {
          stepStart = existingTask.planStart ?? existingTask.startDate;
          stepEnd = existingTask.planEnd ?? stepStart;

          hoursText = existingTask.estimatedHours.trim();

          if (hoursText.isEmpty) {
            hoursText = '00:00';
          }

          if (existingTask.subId.trim().isNotEmpty) {
            subId = existingTask.subId.trim();
          }
        }

        stepStart = _onlyDate(stepStart);
        stepEnd = _onlyDate(stepEnd);

        if (stepEnd.isBefore(stepStart)) {
          stepEnd = stepStart;
        }

        return {
          'subId': subId,
          'name': workName,
          'controller': TextEditingController(text: hoursText),
          'startDate': stepStart,
          'endDate': stepEnd,

          // ============================================================
          // E-DESK
          // Preserva os vínculos já cadastrados no projeto.
          // ============================================================
          'edeskSolicitacao': existingTask?.edeskSolicitacao,
          'edeskUrl': existingTask?.edeskUrl,
          'edeskIdTrabalho': existingTask?.edeskIdTrabalho,
        };
      },
    );

    if (_internalWorks.isNotEmpty) {
      final dynamic firstStart = _internalWorks.first['startDate'];

      if (firstStart is DateTime) {
        _startDate = _onlyDate(firstStart);
      }
    }
  }

// ============================================================
// ATUALIZAR DATAS DAS FASES NO E-DESK
// Usa ID + Cliente + Nome das etapas
// Mantém o botão sincronizando até o Python concluir
// ============================================================

  Future<void> _atualizarDatasEdesk({required bool enviarTodas}) async {
    if (_isUpdatingEdesk) {
      return;
    }

    final String id = _idController.text.trim();
    final String cliente = _clientController.text.trim();

    // ==========================================================
    // VALIDAÇÕES
    // ==========================================================

    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe o ID do trabalho antes de atualizar o E-Desk.',
          ),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    if (cliente.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe o Cliente antes de atualizar o E-Desk.',
          ),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    if (_internalWorks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhuma etapa encontrada para atualizar no E-Desk.',
          ),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    // ==========================================================
    // MONTA AS FASES
    // ==========================================================

    List<int> indices;
    try {
      indices = edeskPhaseIndices(
          _internalWorks.length, _selectedEdeskPhaseIndices,
          all: enviarTodas);
    } on StateError catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }

    final List<Map<String, String>> fases = [];

    for (final index in indices) {
      final dynamic rawWork = _internalWorks[index];
      if (rawWork is! Map) {
        continue;
      }

      final String nome = rawWork['name']?.toString().trim() ?? '';

      final dynamic rawStart = rawWork['startDate'];
      final dynamic rawEnd = rawWork['endDate'];

      if (nome.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('A fase ${index + 1} não possui um nome válido.'),
        ));
        return;
      }

      if (rawStart is! DateTime || rawEnd is! DateTime) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Confira as datas da fase ${index + 1} antes de enviar.'),
        ));
        return;
      }

      final DateTime dataInicial = _onlyDate(rawStart);
      final DateTime dataFinal = _onlyDate(rawEnd);

      fases.add(
        {
          'nome': nome,
          'dataInicial': _formatDate(dataInicial),
          'dataFinal': _formatDate(dataFinal),
        },
      );
    }

    if (fases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível encontrar datas válidas nas etapas.',
          ),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    // ==========================================================
    // INICIA SINCRONIZAÇÃO
    // ==========================================================

    setState(() {
      _isUpdatingEdesk = true;
    });

    try {
      final EdeskSendResult resultado =
          await _edeskService.atualizarFasesViaPython(
        id: id,
        cliente: cliente,
        fases: fases,
      );

      if (!mounted || !context.mounted) {
        return;
      }

      // ==========================================================
      // SUCESSO REAL
      //
      // O service só deve retornar depois que o Python emitir
      // o sinal de conclusão.
      // ==========================================================

      if (resultado.statusCode == 499) return;
      if (resultado.confirmed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              resultado.message.isNotEmpty
                  ? resultado.message
                  : 'Datas das fases atualizadas no E-Desk com sucesso.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(
              seconds: 4,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              resultado.message.isNotEmpty
                  ? resultado.message
                  : 'Não foi possível atualizar as datas no E-Desk.',
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(
              seconds: 5,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted || !context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao atualizar datas no E-Desk: $e',
          ),
          backgroundColor: Colors.redAccent,
          duration: const Duration(
            seconds: 6,
          ),
        ),
      );
    } finally {
      if (mounted && context.mounted) {
        setState(() {
          _isUpdatingEdesk = false;
        });
      }
    }
  }

  // ============================================================
  // HORAS
  // ============================================================

  String _calculateTotalEstimatedHours() {
    int totalMinutes = 0;

    for (final work in _internalWorks) {
      final controller = work['controller'];

      if (controller is! TextEditingController) {
        continue;
      }

      final String text = controller.text.replaceAll(
        RegExp(r'\D'),
        '',
      );

      if (text.isEmpty) {
        continue;
      }

      final int padded = int.tryParse(text) ?? 0;

      int hours = padded ~/ 100;
      int minutes = padded % 100;

      hours += minutes ~/ 60;
      minutes %= 60;

      totalMinutes += (hours * 60) + minutes;
    }

    final int finalHours = totalMinutes ~/ 60;
    final int finalMinutes = totalMinutes % 60;

    return '${finalHours.toString().padLeft(2, '0')}:'
        '${finalMinutes.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // SELECIONAR ARQUIVO
  // ============================================================

  Future<void> _pickExcelFile() async {
    try {
      final reference = await ProjectFileService.pickFile(_idController.text);
      if (reference == null || !mounted) return;
      setState(() {
        _excelLinkController.text = reference;
        if (kIsWeb &&
            WebConfig.storageEnabled &&
            _folderPathController.text.trim().isEmpty) {
          _folderPathController.text =
              ProjectFileService.cloudFolder(_idController.text);
        }
      });
    } catch (error) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  // ============================================================
  // CRIAR PASTA DO PROJETO
  // ============================================================

  String _sanitizarNomePasta(String valor) {
    return valor
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _criarPastaProjeto() async {
    final id = _idController.text.trim();
    final cliente = _clientController.text.trim();

    if (id.isEmpty || cliente.isEmpty) {
      if (!mounted || !context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preencha o ID e o Cliente antes de criar a pasta.',
          ),
        ),
      );
      return;
    }

    if (kIsWeb) {
      try {
        final reference =
            await BrowserLocalFiles.pickFolder(createName: '$id - $cliente');
        if (reference == null || !mounted) return;
        setState(() => _folderPathController.text = reference);
      } catch (error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
      return;
    }

    try {
      final diretorioBase = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Escolha onde a pasta do projeto será criada',
      );

      if (diretorioBase == null || diretorioBase.trim().isEmpty) {
        return;
      }

      final nomePasta = _sanitizarNomePasta('$id - $cliente');
      final caminhoCompleto = await createLocalFolder(diretorioBase, nomePasta);

      if (!mounted || !context.mounted) return;

      setState(() {
        _folderPathController.text = caminhoCompleto;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pasta vinculada com sucesso: $nomePasta',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted || !context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao criar a pasta do projeto: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ============================================================
  // ABRIR CAMINHO / ARQUIVO
  // ============================================================

  Future<void> _abrirCaminho(
    String? caminho,
  ) async {
    if (caminho == null || caminho.trim().isEmpty) {
      if (!mounted || !context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum caminho ou arquivo cadastrado para este projeto.',
          ),
        ),
      );

      return;
    }

    try {
      final path = caminho.trim();
      if (ProjectStorageService.isStorageReference(path) &&
          path.endsWith('/files/')) {
        if (kIsWeb && !WebConfig.storageEnabled) {
          throw StateError('O armazenamento de anexos não está configurado.');
        }
        await showProjectStorageFilesDialog(context, folderReference: path);
      } else {
        final isFolder = _folderPathController.text.trim() == path;
        final resolved = await ProjectFileService.openFile(path,
            projectId: widget.projectToEdit?.id,
            field: isFolder ? 'folderPath' : 'excelLink');
        if (resolved != null && mounted) {
          final controller =
              isFolder ? _folderPathController : _excelLinkController;
          if (controller.text.trim() == path) {
            setState(() => controller.text = resolved);
          }
        }
      }
    } catch (e) {
      if (!mounted || !context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao abrir arquivo/pasta: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ============================================================
  // SALVAR PROJETO
  // ============================================================

  Future<void> _saveProject() async {
    if (_isSaving || !mounted) {
      return;
    }

    final String id = _idController.text.trim();
    final String client = _clientController.text.trim();

    final email = _emailController.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Informe um e-mail válido ou deixe o campo vazio.')));
      return;
    }

    if (id.isEmpty || client.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe o ID e o Cliente.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );

      return;
    }

    for (final work in _internalWorks) {
      final dynamic rawSubId = work['subId'];
      final String subId = rawSubId?.toString().trim() ?? '';

      if (subId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Informe o número da atividade "${work['name']}".',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );

        return;
      }

      final dynamic rawStartDate = work['startDate'];
      final dynamic rawEndDate = work['endDate'];

      if (rawStartDate is! DateTime || rawEndDate is! DateTime) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'A etapa "${work['name']}" possui datas inválidas.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );

        return;
      }

      final DateTime startDate = _onlyDate(rawStartDate);
      final DateTime endDate = _onlyDate(rawEndDate);

      if (endDate.isBefore(startDate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'A etapa "${work['name']}" possui término '
              'anterior ao início.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );

        return;
      }
    }

    final List<TaskModel> customSubTasks = [];

    for (int index = 0; index < _internalWorks.length; index++) {
      final work = _internalWorks[index];

      final dynamic rawController = work['controller'];

      if (rawController is! TextEditingController) {
        continue;
      }

      final DateTime stepStart = _onlyDate(
        work['startDate'] as DateTime,
      );

      final DateTime stepEnd = _onlyDate(
        work['endDate'] as DateTime,
      );

      final String subId = work['subId']?.toString().trim().isNotEmpty == true
          ? work['subId'].toString().trim()
          : (index + 1).toString();

      // ==========================================================
      // E-DESK
      // ==========================================================

      final String? edeskSolicitacao =
          work['edeskSolicitacao']?.toString().trim().isNotEmpty == true
              ? work['edeskSolicitacao'].toString().trim()
              : null;

      final String? edeskUrl =
          work['edeskUrl']?.toString().trim().isNotEmpty == true
              ? work['edeskUrl'].toString().trim()
              : null;

      final String edeskIdTrabalho = subId;

      customSubTasks.add(
        TaskModel(
          subId: subId,
          stage: work['name'] as String,
          status: _status,
          startDate: stepStart,
          planStart: stepStart,
          planEnd: stepEnd,
          estimatedHours: rawController.text.trim().isNotEmpty
              ? rawController.text.trim()
              : '00:00',
          hourType: _hourType,

          // ========================================================
          // PRESERVAR E-DESK
          // ========================================================

          edeskSolicitacao: edeskSolicitacao,
          edeskUrl: edeskUrl,
          edeskIdTrabalho: edeskIdTrabalho,
        ),
      );
    }

    final DateTime globalStartDate = _internalWorks.isNotEmpty
        ? _onlyDate(
            _internalWorks.first['startDate'] as DateTime,
          )
        : _onlyDate(_startDate);

    final List<Map<String, dynamic>> checklistToSave = _buildChecklistForSave();

    setState(() {
      _isSaving = true;
    });

    try {
      final excelLink = ProjectFileService.editedReference(
        _excelLinkController.text,
        _initialExcelReference,
      );
      final folderPath = ProjectFileService.editedReference(
        _folderPathController.text,
        _initialFolderReference,
      );

      final ProjectModel savedProject = ProjectModel(
        id: id,
        id2: widget.projectToEdit?.id2 ?? '0',
        client: client,
        serviceType: _selectedWorkFormat?.name ?? 'Geral',
        stage: _internalWorks.isNotEmpty
            ? _internalWorks.first['name'] as String
            : 'Geral',
        task: widget.projectToEdit?.task ?? '',
        status: _status,
        startDate: globalStartDate,
        estimatedHours: _calculateTotalEstimatedHours(),
        leader: _leaderController.text.trim().isEmpty
            ? 'Equipe'
            : _leaderController.text.trim(),
        hourType: _hourType,
        excelLink: excelLink,
        folderPath: folderPath,
        email: email.isEmpty ? null : email,
        subTasks: customSubTasks,
        checklist: checklistToSave,
      );

      await _firebaseService.saveProject(
        savedProject,
        savedProject.id,
        ProjectReferenceChanges(
          previousFolder: _initialFolderReference,
          previousExcel: _initialExcelReference,
        ),
      );

      if (!mounted || !context.mounted) {
        return;
      }

      if (savedProject.status == 'TRAB_FIM' &&
          widget.projectToEdit?.status != 'TRAB_FIM' &&
          ProjectArchiveDialog.acceptsFolder(savedProject.folderPath ?? '') &&
          ProjectArchiveDialog.allowed) {
        final result = await ProjectArchiveDialog.show(context,
            projectId: savedProject.id,
            folder: savedProject.folderPath!,
            excel: savedProject.excelLink ?? '');
        if (result != null) {
          savedProject.folderPath = result['folderReference'] as String;
          savedProject.excelLink = result['excelReference'] as String;
        }
        if (!mounted || !context.mounted) return;
      }
      Navigator.of(context).pop(
        savedProject,
      );
    } catch (e) {
      if (!mounted || !context.mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      final errorMessage = 'Erro ao salvar o projeto: $e';

      if (!mounted || !context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _idController.dispose();
    _clientController.dispose();
    _emailController.dispose();
    _leaderController.dispose();
    _excelLinkController.dispose();
    _folderPathController.dispose();

    _newChecklistItemController.dispose();

    _disposeInternalControllers();

    _edeskService.dispose();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final String calculatedHours = _calculateTotalEstimatedHours();

    return AlertDialog(
      backgroundColor: AppPalette.surface,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              _isEditing
                  ? 'Editar Trabalho - ${widget.projectToEdit!.id}'
                  : 'Novo Trabalho',
              style: TextStyle(
                color: AppPalette.text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              color: AppPalette.secondary,
              size: 20,
            ),
            onPressed: _isSaving || _isUpdatingEdesk
                ? null
                : () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 820,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _idController,
                      style: TextStyle(
                        color: AppPalette.text,
                      ),
                      decoration: InputDecoration(
                        labelText: 'ID',
                        labelStyle: TextStyle(
                          color: AppPalette.secondary,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 4,
                    child: DropdownButtonFormField<String>(
                      initialValue: _status,
                      dropdownColor: AppPalette.surface,
                      style: TextStyle(
                        color: AppPalette.text,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Status',
                        labelStyle: TextStyle(
                          color: AppPalette.secondary,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'INI_PRI',
                          child: Text('INI_PRI'),
                        ),
                        DropdownMenuItem(
                          value: 'INI_PRO',
                          child: Text('INI_PRO'),
                        ),
                        DropdownMenuItem(
                          value: 'TRAB',
                          child: Text('TRAB'),
                        ),
                        DropdownMenuItem(
                          value: 'EA',
                          child: Text('EA'),
                        ),
                        DropdownMenuItem(
                          value: 'TRAB_FIM',
                          child: Text('TRAB_FIM'),
                        ),
                      ],
                      onChanged: (value) {
                        if (!mounted || !context.mounted) {
                          return;
                        }

                        setState(() {
                          _status = value ?? 'INI_PRI';
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: TextField(
                      controller: _clientController,
                      style: TextStyle(
                        color: AppPalette.text,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Cliente',
                        labelStyle: TextStyle(
                          color: AppPalette.secondary,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: DropdownButtonFormField<WorkFormat>(
                      initialValue: _selectedWorkFormat,
                      isExpanded: true,
                      dropdownColor: AppPalette.surface,
                      style: TextStyle(
                        color: AppPalette.text,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Tipo de Serviço',
                        labelStyle: TextStyle(
                          color: AppPalette.secondary,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: widget.workFormats
                          .map(
                            (wf) => DropdownMenuItem<WorkFormat>(
                              value: wf,
                              child: Text(
                                wf.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val == null || !mounted) {
                          return;
                        }

                        setState(() {
                          _selectedWorkFormat = val;

                          _updateInternalWorks(
                            val,
                            existingProject: widget.projectToEdit,
                          );
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: TextStyle(color: AppPalette.text),
                decoration: InputDecoration(
                  labelText: 'E-mail',
                  helperText: 'Opcional',
                  prefixIcon: const Icon(Icons.mail_outline),
                  labelStyle: TextStyle(color: AppPalette.secondary),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ProjectReferenceField(
                      controller: _folderPathController,
                      readOnly: !kIsWeb,
                      style: TextStyle(
                        color: AppPalette.text,
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        labelText: kIsWeb
                            ? 'Pasta local ou link compartilhado (opcional)'
                            : 'Pasta de Documentos',
                        labelStyle: TextStyle(
                          color: AppPalette.secondary,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: const Icon(
                          Icons.folder,
                          color: Colors.cyanAccent,
                          size: 20,
                        ),
                        suffixIcon: SizedBox(
                          width: kIsWeb ? 132 : 88,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Criar pasta do projeto',
                                icon: const Icon(
                                  Icons.create_new_folder_outlined,
                                  color: Colors.cyanAccent,
                                  size: 20,
                                ),
                                onPressed: _criarPastaProjeto,
                              ),
                              if (kIsWeb)
                                IconButton(
                                  tooltip: 'Selecionar pasta local',
                                  icon: const Icon(Icons.search,
                                      color: Colors.cyanAccent, size: 20),
                                  onPressed: () async {
                                    try {
                                      final reference =
                                          await BrowserLocalFiles.pickFolder();
                                      if (reference != null && mounted) {
                                        setState(() => _folderPathController
                                            .text = reference);
                                      }
                                    } catch (error) {
                                      if (mounted && context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(error
                                                    .toString()
                                                    .replaceFirst(
                                                        'Bad state: ', ''))));
                                      }
                                    }
                                  },
                                ),
                              IconButton(
                                tooltip: 'Abrir pasta',
                                icon: const Icon(
                                  Icons.folder_open,
                                  color: Colors.cyanAccent,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    _abrirCaminho(_folderPathController.text),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ProjectReferenceField(
                      controller: _excelLinkController,
                      readOnly: !kIsWeb,
                      onTap: kIsWeb ? null : _pickExcelFile,
                      style: TextStyle(
                        color: AppPalette.text,
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        labelText: kIsWeb
                            ? 'Arquivo local ou link compartilhado'
                            : 'Arquivo (Excel / Word / Link)',
                        labelStyle: TextStyle(
                          color: AppPalette.secondary,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: const Icon(
                          Icons.insert_drive_file,
                          color: Colors.cyanAccent,
                          size: 20,
                        ),
                        suffixIcon: IconButton(
                          tooltip: kIsWeb
                              ? 'Selecionar anexo'
                              : 'Selecionar arquivo',
                          onPressed: _pickExcelFile,
                          icon: const Icon(
                            Icons.attach_file,
                            color: Colors.cyanAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Check List',
                        style: TextStyle(
                          color: AppPalette.secondary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Selecione um modelo para aplicar os itens ao trabalho.',
                        style: TextStyle(
                          color: AppPalette.secondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (_checklistItems.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppPalette.accent.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Text(
                        '${_checklistItems.where((item) => item['completed'] == true).length}/${_checklistItems.length}',
                        style: TextStyle(
                          color: AppPalette.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppPalette.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.playlist_add_check,
                      color: AppPalette.accent,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _loadingChecklistFormats
                          ? Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppPalette.accent,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Carregando modelos de Check List...',
                                  style: TextStyle(
                                    color: AppPalette.secondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          : DropdownButtonFormField<ChecklistFormat>(
                              initialValue: _selectedChecklistFormat,
                              isExpanded: true,
                              dropdownColor: AppPalette.surface,
                              style: TextStyle(
                                color: AppPalette.text,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Modelo de Check List',
                                labelStyle: TextStyle(
                                  color: AppPalette.secondary,
                                ),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              hint: Text(
                                'Selecione um modelo',
                                style: TextStyle(
                                  color: AppPalette.secondary,
                                ),
                              ),
                              items: _checklistFormats
                                  .map(
                                    (format) =>
                                        DropdownMenuItem<ChecklistFormat>(
                                      value: format,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              format.name,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(
                                            width: 8,
                                          ),
                                          Text(
                                            '${format.items.length} itens',
                                            style: TextStyle(
                                              color: AppPalette.secondary,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }

                                _applyChecklistFormat(
                                  value,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppPalette.border,
                  ),
                ),
                child: _checklistItems.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.checklist,
                              color: AppPalette.border,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Nenhum item no Check List deste trabalho.',
                                style: TextStyle(
                                  color: AppPalette.secondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _addChecklistItem,
                              icon: const Icon(
                                Icons.add,
                                size: 18,
                              ),
                              label: const Text('Adicionar'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(
                                  0xFF00FFCC,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          ...List.generate(
                            _checklistItems.length,
                            (index) {
                              final item = _checklistItems[index];

                              final String itemName =
                                  item['name']?.toString() ?? '';

                              final bool completed = item['completed'] == true;

                              final String source =
                                  item['source']?.toString() ?? 'model';

                              final bool isManual = source == 'manual';

                              return Container(
                                margin: EdgeInsets.only(
                                  bottom: index == _checklistItems.length - 1
                                      ? 0
                                      : 6,
                                ),
                                decoration: BoxDecoration(
                                  color: completed
                                      ? const Color(
                                          0xFF00FFCC,
                                        ).withValues(alpha: 0.06)
                                      : AppPalette.text.withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(
                                    6,
                                  ),
                                  border: Border.all(
                                    color: completed
                                        ? const Color(
                                            0xFF00FFCC,
                                          ).withValues(alpha: 0.25)
                                        : AppPalette.text
                                            .withValues(alpha: 0.08),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: completed,
                                      activeColor: const Color(
                                        0xFF00FFCC,
                                      ),
                                      checkColor: AppPalette.onPrimary,
                                      onChanged: (value) {
                                        _toggleChecklistItem(
                                          index,
                                          value,
                                        );
                                      },
                                    ),
                                    Container(
                                      width: 25,
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          color: AppPalette.secondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        itemName,
                                        style: TextStyle(
                                          color: completed
                                              ? AppPalette.secondary
                                              : AppPalette.text,
                                          fontSize: 12,
                                          decoration: completed
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                          decorationColor: AppPalette.secondary,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isManual
                                            ? Colors.orangeAccent.withValues(
                                                alpha: 0.10,
                                              )
                                            : Colors.cyanAccent.withValues(
                                                alpha: 0.08,
                                              ),
                                        borderRadius: BorderRadius.circular(
                                          10,
                                        ),
                                      ),
                                      child: Text(
                                        isManual ? 'Adicional' : 'Modelo',
                                        style: TextStyle(
                                          color: isManual
                                              ? Colors.orangeAccent
                                              : Colors.cyanAccent,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 4,
                                    ),
                                    IconButton(
                                      tooltip: 'Remover item deste trabalho',
                                      icon: Icon(
                                        Icons.close,
                                        color: AppPalette.border,
                                        size: 17,
                                      ),
                                      onPressed: () {
                                        _removeChecklistItem(
                                          index,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: _addChecklistItem,
                              icon: const Icon(
                                Icons.add,
                                size: 17,
                              ),
                              label: const Text(
                                'Adicionar item',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(
                                  0xFF00FFCC,
                                ),
                                side: BorderSide(
                                  color: const Color(
                                    0xFF00FFCC,
                                  ).withValues(alpha: 0.50),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 18),
              Text(
                'Trabalhos Internos do Serviço',
                style: TextStyle(
                  color: AppPalette.secondary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Edite o número e clique nas datas em vermelho para editar o início e o término de cada etapa.',
                style: TextStyle(
                  color: AppPalette.secondary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppPalette.border,
                  ),
                ),
                child: _internalWorks.isEmpty
                    ? Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Nenhum trabalho interno cadastrado para este serviço.',
                          style: TextStyle(
                            color: AppPalette.secondary,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : Column(
                        children: _internalWorks.map(
                          (work) {
                            final dynamic rawStart = work['startDate'];
                            final dynamic rawEnd = work['endDate'];

                            if (rawStart is! DateTime || rawEnd is! DateTime) {
                              return const SizedBox.shrink();
                            }

                            final DateTime sDate = _onlyDate(rawStart);
                            final DateTime eDate = _onlyDate(rawEnd);

                            final dynamic rawController = work['controller'];

                            if (rawController is! TextEditingController) {
                              return const SizedBox.shrink();
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Tooltip(
                                      message:
                                          'Selecionar esta fase para enviar ao E-Desk',
                                      child: Checkbox(
                                          value: _selectedEdeskPhaseIndices
                                              .contains(
                                                  _internalWorks.indexOf(work)),
                                          onChanged: (_isSaving ||
                                                  _isUpdatingEdesk)
                                              ? null
                                              : (selected) {
                                                  setState(() {
                                                    final index = _internalWorks
                                                        .indexOf(work);
                                                    if (selected == true) {
                                                      _selectedEdeskPhaseIndices
                                                          .add(index);
                                                    } else {
                                                      _selectedEdeskPhaseIndices
                                                          .remove(index);
                                                    }
                                                  });
                                                })),

                                  // ------------------------------------------------
                                  // NÚMERO DA ATIVIDADE - EDITÁVEL
                                  // ------------------------------------------------
                                  SizedBox(
                                    width: 70,
                                    child: TextField(
                                      controller: TextEditingController(
                                        text: work['subId']?.toString() ?? '',
                                      ),
                                      style: TextStyle(
                                        color: AppPalette.text,
                                        fontSize: 13,
                                      ),
                                      textAlign: TextAlign.center,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      onChanged: (value) {
                                        work['subId'] = value;
                                        work['edeskIdTrabalho'] = value.trim();
                                      },
                                      decoration: InputDecoration(
                                        labelText: 'Nº',
                                        labelStyle: TextStyle(
                                          color: AppPalette.secondary,
                                          fontSize: 11,
                                        ),
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // ------------------------------------------------
                                  // ETAPA
                                  // ------------------------------------------------
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      work['name']?.toString() ?? 'Etapa',
                                      style: TextStyle(
                                        color: AppPalette.text,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // ------------------------------------------------
                                  // DATA DE INÍCIO
                                  // ------------------------------------------------
                                  Expanded(
                                    flex: 2,
                                    child: InkWell(
                                      onTap: () => _editStartDate(
                                        work,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        4,
                                      ),
                                      child: InputDecorator(
                                        decoration: InputDecoration(
                                          labelText: 'Início',
                                          labelStyle: TextStyle(
                                            color: AppPalette.secondary,
                                            fontSize: 11,
                                          ),
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 10,
                                          ),
                                          suffixIcon: Icon(
                                            Icons.calendar_month,
                                            color: Color(
                                              0xFFFF5252,
                                            ),
                                            size: 17,
                                          ),
                                        ),
                                        child: Text(
                                          _formatDate(sDate),
                                          style: const TextStyle(
                                            color: Color(
                                              0xFFFF5252,
                                            ),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // ------------------------------------------------
                                  // DATA DE TÉRMINO
                                  // ------------------------------------------------
                                  Expanded(
                                    flex: 2,
                                    child: InkWell(
                                      onTap: () => _editEndDate(
                                        work,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        4,
                                      ),
                                      child: InputDecorator(
                                        decoration: InputDecoration(
                                          labelText: 'Término',
                                          labelStyle: TextStyle(
                                            color: AppPalette.secondary,
                                            fontSize: 11,
                                          ),
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 10,
                                          ),
                                          suffixIcon: Icon(
                                            Icons.calendar_month,
                                            color: Color(
                                              0xFFFF5252,
                                            ),
                                            size: 17,
                                          ),
                                        ),
                                        child: Text(
                                          _formatDate(eDate),
                                          style: const TextStyle(
                                            color: Color(
                                              0xFFFF5252,
                                            ),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // ------------------------------------------------
                                  // HORAS
                                  // ------------------------------------------------
                                  SizedBox(
                                    width: 100,
                                    child: TextField(
                                      controller: rawController,
                                      style: TextStyle(
                                        color: AppPalette.text,
                                        fontSize: 13,
                                      ),
                                      textAlign: TextAlign.center,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        HoursInputFormatter(),
                                      ],
                                      onChanged: (_) {
                                        if (!mounted || !context.mounted) {
                                          return;
                                        }

                                        setState(() {});
                                      },
                                      decoration: InputDecoration(
                                        labelText: 'Horas',
                                        labelStyle: TextStyle(
                                          color: AppPalette.secondary,
                                          fontSize: 11,
                                        ),
                                        hintText: '00:00',
                                        hintStyle: TextStyle(
                                          color: AppPalette.border,
                                        ),
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ).toList(),
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Hs Estimadas (Calc.)',
                        labelStyle: TextStyle(
                          color: AppPalette.secondary,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: Text(
                        calculatedHours,
                        style: TextStyle(
                          color: AppPalette.text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _hourType,
                      isExpanded: true,
                      dropdownColor: AppPalette.surface,
                      style: TextStyle(
                        color: AppPalette.text,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Tipo de Horas',
                        labelStyle: TextStyle(
                          color: AppPalette.secondary,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Hs Cobradas',
                          child: Text(
                            'Hs Cobradas',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Hs Investimento',
                          child: Text(
                            'Hs Investimento',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Hs Não Cobradas',
                          child: Text(
                            'Hs Não Cobradas',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Hs Internas',
                          child: Text(
                            'Hs Internas',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Outras',
                          child: Text(
                            'Outras',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Hs Não Informadas',
                          child: Text(
                            'Hs Não Informadas',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (!mounted || !context.mounted) {
                          return;
                        }

                        setState(() {
                          _hourType = value ?? 'Hs Cobradas';
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _leaderController,
                      style: TextStyle(
                        color: AppPalette.text,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Líder Prj',
                        labelStyle: TextStyle(
                          color: AppPalette.secondary,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving || _isUpdatingEdesk
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(
            'Cancelar',
            style: TextStyle(
              color: AppPalette.secondary,
            ),
          ),
        ),

        // ========================================================
        // ATUALIZAR E-DESK
        // ========================================================

        EdeskPhaseSendButton(
          total: _internalWorks.length,
          selectedCount: _selectedEdeskPhaseIndices.length,
          busy: _isUpdatingEdesk,
          enabled: !_isSaving,
          onSend: (enviarTodas) =>
              _atualizarDatasEdesk(enviarTodas: enviarTodas),
        ),

        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppPalette.accent,
            foregroundColor: AppPalette.foregroundOn(AppPalette.accent),
          ),
          onPressed: _isSaving || _isUpdatingEdesk ? null : _saveProject,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Text(
                  _isEditing ? 'Salvar Alterações' : 'Salvar',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }
}
