import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'dart:convert';
import 'package:gerenciador_horas/core/platform/local_files.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/file_download.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

class WorkFormatsScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  const WorkFormatsScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required String userName,
  });

  @override
  State<WorkFormatsScreen> createState() => _WorkFormatsScreenState();
}

class _WorkFormatsScreenState extends State<WorkFormatsScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  List<WorkFormat> _workFormats = [];

  bool _isLoading = true;
  bool _isExporting = false;
  bool _isImporting = false;

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadWorkFormats();
  }

  // ===============================================================
  // DADOS
  // ===============================================================

  List<WorkFormat> get _filteredWorkFormats {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return _workFormats;
    }

    return _workFormats.where((format) {
      return format.id.toLowerCase().contains(query) ||
          format.name.toLowerCase().contains(query);
    }).toList();
  }

  int get _totalSteps {
    return _workFormats.fold<int>(
      0,
      (total, format) => total + format.steps.length,
    );
  }

  double get _averageSteps {
    if (_workFormats.isEmpty) {
      return 0;
    }

    return _totalSteps / _workFormats.length;
  }

  WorkFormat? get _largestWorkFormat {
    if (_workFormats.isEmpty) {
      return null;
    }

    WorkFormat result = _workFormats.first;

    for (final format in _workFormats.skip(1)) {
      if (format.steps.length > result.steps.length) {
        result = format;
      }
    }

    return result;
  }

  // ===============================================================
  // CARREGAR
  // ===============================================================

  Future<void> _loadWorkFormats() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final formats = await _firebaseService.getWorkFormats();

      if (mounted) {
        setState(() {
          _workFormats = formats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        _showSnackBar(
          'Erro ao carregar modelos: $e',
          isError: true,
        );
      }
    }
  }

  // ===============================================================
  // SNACKBAR
  // ===============================================================

  void _showSnackBar(
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppPalette.text.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: AppPalette.foregroundOn(isError ? CoresApp.erro : CoresApp.sucesso),
                  size: 18,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: AppPalette.foregroundOn(isError ? CoresApp.erro : CoresApp.sucesso),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: isError ? CoresApp.erro : CoresApp.sucesso,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  // ===============================================================
  // EXPORTAR
  // ===============================================================

  Future<void> _exportWorkFormats() async {
    if (_isExporting) {
      return;
    }

    if (_workFormats.isEmpty) {
      _showSnackBar(
        'Não existem modelos de trabalho cadastrados para exportar.',
      );
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final List<Map<String, dynamic>> formatsData = _workFormats.map((format) {
        return {
          'id': format.id,
          'name': format.name,
          'steps': format.steps.map((step) {
            if (step is Map) {
              return Map<String, dynamic>.from(step);
            }

            return {
              'order': format.steps.indexOf(step) + 1,
              'name': step.toString(),
            };
          }).toList(),
        };
      }).toList();

      final Map<String, dynamic> exportData = {
        'format': 'gerenciador_horas_work_formats',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'total': formatsData.length,
        'workFormats': formatsData,
      };

      final String jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(exportData);

      if (kIsWeb) {
        downloadBytes(
          fileName: 'modelos_trabalho.json',
          bytes: Uint8List.fromList(utf8.encode(jsonString)),
          mimeType: 'application/json',
        );
        _showSnackBar('Download dos modelos de trabalho iniciado.');
      } else {
        final String? outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Exportar modelos de trabalho',
          fileName: 'modelos_trabalho.json',
          type: FileType.custom,
          allowedExtensions: ['json'],
        );

        if (outputPath == null || outputPath.trim().isEmpty) {
          return;
        }

        String finalPath = outputPath;

        if (!finalPath.toLowerCase().endsWith('.json')) {
          finalPath = '$finalPath.json';
        }

        await writeLocalBytes(
            finalPath, Uint8List.fromList(utf8.encode(jsonString)));
      }
    } catch (e) {
      _showSnackBar(
        'Erro ao exportar modelos: $e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  // ===============================================================
  // IMPORTAR
  // ===============================================================

  Future<void> _importWorkFormats() async {
    if (_isImporting) {
      return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Importar modelos de trabalho',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final PlatformFile pickedFile = result.files.first;

      String jsonString;

      if (pickedFile.bytes != null) {
        jsonString = utf8.decode(
          pickedFile.bytes!,
          allowMalformed: false,
        );
      } else if (!kIsWeb && pickedFile.path != null) {
        jsonString = await readLocalText(pickedFile.path!);
      } else {
        throw Exception(
          'Não foi possível acessar o arquivo selecionado.',
        );
      }

      if (jsonString.trim().isEmpty) {
        throw Exception(
          'O arquivo JSON está vazio.',
        );
      }

      final dynamic decoded = jsonDecode(jsonString);

      if (decoded is! Map) {
        throw Exception(
          'Formato de arquivo inválido.',
        );
      }

      final Map<String, dynamic> jsonData = Map<String, dynamic>.from(decoded);

      final dynamic rawFormats = jsonData['workFormats'];

      if (rawFormats is! List) {
        throw Exception(
          'O arquivo não contém a lista de modelos de trabalho.',
        );
      }

      final List<WorkFormat> importedFormats = [];

      for (final dynamic item in rawFormats) {
        if (item is! Map) {
          continue;
        }

        final Map<String, dynamic> data = Map<String, dynamic>.from(item);

        final String id = data['id']?.toString().trim() ?? '';

        final String name = data['name']?.toString().trim() ?? '';

        if (id.isEmpty || name.isEmpty) {
          continue;
        }

        final List<String> steps = [];

        final dynamic rawSteps = data['steps'];

        if (rawSteps is List) {
          for (final dynamic step in rawSteps) {
            if (step is String) {
              final String value = step.trim();

              if (value.isNotEmpty) {
                steps.add(value);
              }
            } else if (step is Map) {
              final Map<String, dynamic> stepMap =
                  Map<String, dynamic>.from(step);

              final dynamic stepName = stepMap['name'] ??
                  stepMap['stage'] ??
                  stepMap['title'] ??
                  stepMap['descricao'] ??
                  stepMap['description'];

              if (stepName != null) {
                final String value = stepName.toString().trim();

                if (value.isNotEmpty) {
                  steps.add(value);
                }
              }
            }
          }
        }

        importedFormats.add(
          WorkFormat(
            id: id,
            name: name,
            steps: steps,
          ),
        );
      }

      if (importedFormats.isEmpty) {
        throw Exception(
          'Nenhum modelo válido foi encontrado no arquivo.',
        );
      }

      if (!mounted) {
        return;
      }

      final bool? confirmed = await _showImportConfirmation(
        importedFormats.length,
      );

      if (confirmed != true) {
        return;
      }

      int importedCount = 0;

      for (final WorkFormat format in importedFormats) {
        await _firebaseService.saveWorkFormat(format);
        importedCount++;
      }

      await _loadWorkFormats();

      _showSnackBar(
        '$importedCount modelo(s) importado(s) com sucesso.',
      );
    } on FormatException {
      _showSnackBar(
        'O arquivo selecionado não possui um JSON válido.',
        isError: true,
      );
    } catch (e) {
      _showSnackBar(
        'Erro ao importar modelos: $e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  // ===============================================================
  // CONFIRMAÇÃO IMPORTAÇÃO
  // ===============================================================

  Future<bool?> _showImportConfirmation(int total) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return AlertDialog(
          backgroundColor: CoresTelas.fundoModal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: CoresApp.borda,
            ),
          ),
          titlePadding: const EdgeInsets.fromLTRB(
            24,
            24,
            20,
            10,
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            24,
            5,
            24,
            12,
          ),
          title: Row(
            children: [
              _buildIconBox(
                Icons.file_download_outlined,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Importar modelos',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                icon: Icon(
                  Icons.close_rounded,
                  color: CoresApp.textoSecundario,
                ),
              ),
            ],
          ),
          content: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  CoresApp.primaria.withValues(alpha: 0.08),
                  CoresApp.fundoSecundario.withValues(alpha: 0.35),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: CoresApp.primaria.withValues(alpha: 0.14),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: CoresApp.primaria.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$total',
                        style: TextStyle(
                          color: CoresApp.primaria,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'modelos encontrados',
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Text(
                  'Os modelos serão adicionados ou atualizados '
                  'na sua conta.',
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                    height: 1.45,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Modelos existentes que não estiverem no arquivo '
                  'não serão excluídos.',
                  style: TextStyle(
                    color: CoresApp.textoFraco,
                    height: 1.45,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            20,
            8,
            20,
            18,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.primaria,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              icon: Icon(
                Icons.file_download_done_rounded,
                color: CoresApp.textoPrincipal,
                size: 18,
              ),
              label: Text(
                'Importar',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ===============================================================
  // EXCLUIR
  // ===============================================================

  Future<void> _deleteFormat(String id) async {
    final bool? confirmed = await _showDeleteConfirmation();

    if (confirmed != true) {
      return;
    }

    try {
      await _firebaseService.deleteWorkFormat(id);
      await _loadWorkFormats();

      _showSnackBar(
        'Modelo excluído com sucesso.',
      );
    } catch (e) {
      _showSnackBar(
        'Erro ao excluir modelo: $e',
        isError: true,
      );
    }
  }

  Future<bool?> _showDeleteConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return AlertDialog(
          backgroundColor: CoresTelas.fundoModal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: CoresApp.borda,
            ),
          ),
          title: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CoresApp.erro.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: CoresApp.erro,
                  size: 22,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  'Excluir modelo?',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Esta ação removerá o modelo e suas etapas. '
            'Deseja realmente continuar?',
            style: TextStyle(
              color: CoresApp.textoSecundario,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: Text(
                'Excluir',
                style: TextStyle(
                  color: AppPalette.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ===============================================================
  // MODAL PRINCIPAL
  // ===============================================================

  void _openFormatDetailDialog({
    WorkFormat? format,
  }) {
    final bool isEditing = format != null;

    final idController = TextEditingController(
      text: format?.id ?? '',
    );

    final nameController = TextEditingController(
      text: format?.name ?? '',
    );

    final stepOrderController = TextEditingController();

    final stepNameController = TextEditingController();

    final List<Map<String, String>> currentStepsWithOrder = [];

    if (format?.steps != null) {
      for (int i = 0; i < format!.steps.length; i++) {
        final stepData = format.steps[i];

        if (stepData is Map) {
          currentStepsWithOrder.add({
            'order': stepData['order']?.toString() ?? '${i + 1}',
            'name': stepData['name']?.toString() ?? '',
          });
        } else {
          currentStepsWithOrder.add({
            'order': '${i + 1}',
            'name': stepData.toString(),
          });
        }
      }
    }

    stepOrderController.text = '${currentStepsWithOrder.length + 1}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return StatefulBuilder(
          builder: (
            dialogContext,
            setDialogState,
          ) {
            AppAppearance.watch(dialogContext);

            void addStep() {
              final orderText = stepOrderController.text.trim();

              final nameText = stepNameController.text.trim();

              if (nameText.isEmpty) {
                return;
              }

              setDialogState(() {
                currentStepsWithOrder.add({
                  'order': orderText.isEmpty
                      ? '${currentStepsWithOrder.length + 1}'
                      : orderText,
                  'name': nameText,
                });

                stepNameController.clear();

                final nextVal = (double.tryParse(
                          orderText.replaceAll(
                            ',',
                            '.',
                          ),
                        ) ??
                        currentStepsWithOrder.length.toDouble()) +
                    1.0;

                stepOrderController.text = nextVal % 1 == 0
                    ? nextVal.toInt().toString()
                    : nextVal.toString();
              });
            }

            void removeStep(int index) {
              setDialogState(() {
                currentStepsWithOrder.removeAt(index);
              });
            }

            void editStep(int index) {
              final currentEntry = currentStepsWithOrder[index];

              final editController = TextEditingController(
                text: currentEntry['name'],
              );

              final orderController = TextEditingController(
                text: currentEntry['order'],
              );

              showDialog(
                context: dialogContext,
                builder: (editContext) {
                  AppAppearance.watch(editContext);

                  return AlertDialog(
                    backgroundColor: CoresTelas.fundoModalSecundario,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: CoresApp.borda,
                      ),
                    ),
                    title: Row(
                      children: [
                        _buildIconBox(
                          Icons.edit_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Editar etapa',
                            style: TextStyle(
                              color: CoresApp.textoPrincipal,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    content: SizedBox(
                      width: 400,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildDialogTextField(
                            controller: orderController,
                            label: 'Número / Posição',
                            icon: Icons.format_list_numbered,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(
                                  r'^\d*[.,]?\d{0,5}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _buildDialogTextField(
                            controller: editController,
                            label: 'Descrição da Etapa',
                            icon: Icons.label_outline_rounded,
                            autofocus: true,
                          ),
                        ],
                      ),
                    ),
                    actionsPadding: const EdgeInsets.fromLTRB(
                      20,
                      4,
                      20,
                      18,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(editContext);
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
                          backgroundColor: CoresApp.primaria,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          final newText = editController.text.trim();

                          final newOrder = orderController.text.trim();

                          if (newText.isEmpty || newOrder.isEmpty) {
                            return;
                          }

                          setDialogState(() {
                            currentStepsWithOrder[index] = {
                              'order': newOrder,
                              'name': newText,
                            };
                          });

                          Navigator.pop(editContext);
                        },
                        icon: Icon(
                          Icons.check_rounded,
                          color: CoresApp.textoPrincipal,
                          size: 17,
                        ),
                        label: Text(
                          'Salvar',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            }

            return LayoutBuilder(
              builder: (
                context,
                constraints,
              ) {
                AppAppearance.watch(context);

                final bool small = MediaQuery.of(context).size.width < 700;

                return Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: EdgeInsets.symmetric(
                    horizontal: small ? 10 : 24,
                    vertical: small ? 12 : 24,
                  ),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: 900,
                      maxHeight: MediaQuery.of(context).size.height * 0.92,
                    ),
                    decoration: BoxDecoration(
                      color: CoresTelas.fundoModal,
                      borderRadius: BorderRadius.circular(
                        small ? 18 : 26,
                      ),
                      border: Border.all(
                        color: CoresApp.borda,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: 0.45,
                          ),
                          blurRadius: 40,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // =================================================
                        // HEADER
                        // =================================================

                        _buildModalHeader(
                          dialogContext,
                          isEditing,
                          small,
                        ),

                        // =================================================
                        // CONTEÚDO
                        // =================================================

                        Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.all(
                              small ? 16 : 26,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionHeader(
                                  icon: Icons.info_outline_rounded,
                                  title: 'Informações do modelo',
                                  subtitle: 'Identificação do tipo de projeto',
                                ),

                                const SizedBox(
                                  height: 14,
                                ),

                                Container(
                                  padding: EdgeInsets.all(
                                    small ? 13 : 16,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        CoresApp.primaria.withValues(
                                          alpha: 0.055,
                                        ),
                                        CoresApp.fundoSecundario.withValues(
                                          alpha: 0.22,
                                        ),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      16,
                                    ),
                                    border: Border.all(
                                      color: CoresApp.primaria.withValues(
                                        alpha: 0.12,
                                      ),
                                    ),
                                  ),
                                  child: small
                                      ? Column(
                                          children: [
                                            _buildDialogTextField(
                                              controller: idController,
                                              label: 'ID do modelo',
                                              icon: Icons.tag_rounded,
                                            ),
                                            const SizedBox(
                                              height: 12,
                                            ),
                                            _buildDialogTextField(
                                              controller: nameController,
                                              label: 'Nome do modelo',
                                              icon:
                                                  Icons.folder_special_outlined,
                                            ),
                                          ],
                                        )
                                      : Row(
                                          children: [
                                            SizedBox(
                                              width: 150,
                                              child: _buildDialogTextField(
                                                controller: idController,
                                                label: 'ID do modelo',
                                                icon: Icons.tag_rounded,
                                              ),
                                            ),
                                            const SizedBox(
                                              width: 14,
                                            ),
                                            Expanded(
                                              child: _buildDialogTextField(
                                                controller: nameController,
                                                label: 'Nome do modelo',
                                                icon: Icons
                                                    .folder_special_outlined,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),

                                const SizedBox(
                                  height: 28,
                                ),

                                // =================================================
                                // ETAPAS
                                // =================================================

                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildSectionHeader(
                                        icon: Icons.account_tree_outlined,
                                        title: 'Fluxo de trabalho',
                                        subtitle:
                                            'Organize as etapas deste modelo',
                                      ),
                                    ),
                                    _buildCounterBadge(
                                      currentStepsWithOrder.length,
                                      label: 'etapas',
                                    ),
                                  ],
                                ),

                                const SizedBox(
                                  height: 14,
                                ),

                                // =================================================
                                // ADICIONAR ETAPA
                                // =================================================

                                Container(
                                  padding: EdgeInsets.all(
                                    small ? 13 : 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CoresApp.fundoSecundario.withValues(
                                      alpha: 0.38,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      16,
                                    ),
                                    border: Border.all(
                                      color: CoresApp.borda,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 30,
                                            height: 30,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color:
                                                  CoresApp.primaria.withValues(
                                                alpha: 0.10,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                9,
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.add_rounded,
                                              color: CoresApp.primaria,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(
                                            width: 10,
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Adicionar etapa',
                                                style: TextStyle(
                                                  color:
                                                      CoresApp.textoPrincipal,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              SizedBox(
                                                height: 2,
                                              ),
                                              Text(
                                                'Inclua uma nova etapa no fluxo',
                                                style: TextStyle(
                                                  color: CoresApp.textoFraco,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(
                                        height: 14,
                                      ),
                                      small
                                          ? Column(
                                              children: [
                                                _buildDialogTextField(
                                                  controller:
                                                      stepOrderController,
                                                  label: 'Nº / Posição',
                                                  icon: Icons
                                                      .format_list_numbered,
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                    decimal: true,
                                                  ),
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter
                                                        .allow(
                                                      RegExp(
                                                        r'^\d*[.,]?\d{0,5}',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(
                                                  height: 10,
                                                ),
                                                _buildDialogTextField(
                                                  controller:
                                                      stepNameController,
                                                  label: 'Descrição da etapa',
                                                  icon: Icons
                                                      .subdirectory_arrow_right_rounded,
                                                  onSubmitted: (_) {
                                                    addStep();
                                                  },
                                                ),
                                                const SizedBox(
                                                  height: 10,
                                                ),
                                                SizedBox(
                                                  width: double.infinity,
                                                  height: 48,
                                                  child: _buildAddStepButton(
                                                    onPressed: addStep,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                SizedBox(
                                                  width: 105,
                                                  child: _buildDialogTextField(
                                                    controller:
                                                        stepOrderController,
                                                    label: 'Nº / Posição',
                                                    icon: Icons
                                                        .format_list_numbered,
                                                    keyboardType:
                                                        const TextInputType
                                                            .numberWithOptions(
                                                      decimal: true,
                                                    ),
                                                    inputFormatters: [
                                                      FilteringTextInputFormatter
                                                          .allow(
                                                        RegExp(
                                                          r'^\d*[.,]?\d{0,5}',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(
                                                  width: 10,
                                                ),
                                                Expanded(
                                                  child: _buildDialogTextField(
                                                    controller:
                                                        stepNameController,
                                                    label: 'Descrição da etapa',
                                                    icon: Icons
                                                        .subdirectory_arrow_right_rounded,
                                                    onSubmitted: (_) {
                                                      addStep();
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(
                                                  width: 10,
                                                ),
                                                SizedBox(
                                                  height: 48,
                                                  child: _buildAddStepButton(
                                                    onPressed: addStep,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ],
                                  ),
                                ),

                                const SizedBox(
                                  height: 14,
                                ),

                                // =================================================
                                // LISTA DE ETAPAS
                                // =================================================

                                _buildStepsContainer(
                                  currentStepsWithOrder,
                                  editStep,
                                  removeStep,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // =================================================
                        // RODAPÉ
                        // =================================================

                        _buildModalFooter(
                          dialogContext,
                          idController,
                          nameController,
                          currentStepsWithOrder,
                          isEditing,
                          format,
                          small,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ===============================================================
  // HEADER DO MODAL
  // ===============================================================

  Widget _buildModalHeader(
    BuildContext dialogContext,
    bool isEditing,
    bool small,
  ) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        small ? 17 : 26,
        small ? 17 : 22,
        small ? 14 : 20,
        small ? 17 : 22,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            CoresDashboard.cabecalhoTabela,
            CoresApp.primaria.withValues(alpha: 0.045),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(
            small ? 18 : 26,
          ),
        ),
        border: Border(
          bottom: BorderSide(
            color: CoresApp.borda,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: small ? 42 : 48,
            height: small ? 42 : 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  CoresApp.primaria.withValues(alpha: 0.18),
                  CoresApp.primaria.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: CoresApp.primaria.withValues(alpha: 0.22),
              ),
            ),
            child: Icon(
              isEditing ? Icons.edit_note_rounded : Icons.add_box_outlined,
              color: CoresApp.primaria,
              size: small ? 21 : 23,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Editar modelo' : 'Novo modelo',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: small ? 17 : 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isEditing
                      ? 'Atualize as informações e o fluxo do modelo.'
                      : 'Crie um modelo reutilizável para seus projetos.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                    fontSize: small ? 10.5 : 11.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            icon: Icon(
              Icons.close_rounded,
              color: CoresApp.textoSecundario,
            ),
          ),
        ],
      ),
    );
  }

  // ===============================================================
  // BOTÃO ADICIONAR ETAPA
  // ===============================================================

  Widget _buildAddStepButton({
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: CoresApp.primaria,
        foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
        ),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
      ),
      onPressed: onPressed,
      icon: const Icon(
        Icons.add_rounded,
        size: 18,
      ),
      label: const Text(
        'Adicionar etapa',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11.5,
        ),
      ),
    );
  }

  // ===============================================================
  // LISTA DE ETAPAS DO MODAL
  // ===============================================================

  Widget _buildStepsContainer(
    List<Map<String, String>> steps,
    void Function(int) editStep,
    void Function(int) removeStep,
  ) {
    if (steps.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          vertical: 38,
          horizontal: 20,
        ),
        decoration: BoxDecoration(
          color: CoresDashboard.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CoresApp.borda,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    CoresApp.primaria.withValues(alpha: 0.10),
                    CoresApp.primaria.withValues(alpha: 0.035),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.account_tree_outlined,
                color: CoresApp.textoFraco,
                size: 29,
              ),
            ),
            const SizedBox(height: 13),
            Text(
              'Seu fluxo ainda está vazio',
              style: TextStyle(
                color: CoresApp.textoPrincipal,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Adicione as etapas acima para montar o fluxo do projeto.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CoresApp.textoFraco,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(
        minHeight: 100,
        maxHeight: 330,
      ),
      decoration: BoxDecoration(
        color: CoresDashboard.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CoresApp.borda,
        ),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        shrinkWrap: true,
        itemCount: steps.length,
        separatorBuilder: (_, __) {
          return const SizedBox(height: 5);
        },
        itemBuilder: (context, index) {
          final entry = steps[index];

          return _buildStepCard(
            entry: entry,
            index: index,
            total: steps.length,
            onEdit: () {
              editStep(index);
            },
            onDelete: () {
              removeStep(index);
            },
          );
        },
      ),
    );
  }

  // ===============================================================
  // CARD DE ETAPA
  // ===============================================================

  Widget _buildStepCard({
    required Map<String, String> entry,
    required int index,
    required int total,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(13),
        hoverColor: CoresDashboard.cardHover,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: CoresApp.fundoSecundario.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: CoresApp.bordaSuave,
            ),
          ),
          child: Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          CoresApp.primaria.withValues(alpha: 0.18),
                          CoresApp.primaria.withValues(alpha: 0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: CoresApp.primaria.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      entry['order'] ?? '${index + 1}',
                      style: TextStyle(
                        color: CoresApp.primaria,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (index < total - 1)
                    Container(
                      width: 1,
                      height: 8,
                      color: CoresApp.borda,
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ETAPA ${entry['order'] ?? index + 1}',
                      style: TextStyle(
                        color: CoresApp.primaria,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry['name'] ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _buildActionIconButton(
                tooltip: 'Editar etapa',
                icon: Icons.edit_outlined,
                onPressed: onEdit,
              ),
              _buildActionIconButton(
                tooltip: 'Excluir etapa',
                icon: Icons.delete_outline_rounded,
                isDanger: true,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===============================================================
  // RODAPÉ DO MODAL
  // ===============================================================

  Widget _buildModalFooter(
    BuildContext dialogContext,
    TextEditingController idController,
    TextEditingController nameController,
    List<Map<String, String>> currentStepsWithOrder,
    bool isEditing,
    WorkFormat? format,
    bool small,
  ) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        small ? 16 : 26,
        13,
        small ? 16 : 26,
        small ? 16 : 20,
      ),
      decoration: BoxDecoration(
        color: CoresDashboard.cabecalhoTabela,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(
            small ? 18 : 26,
          ),
        ),
        border: Border(
          top: BorderSide(
            color: CoresApp.borda,
          ),
        ),
      ),
      child: small
          ? Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    child: Text(
                      'Cancelar',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: double.infinity,
                  child: _buildSaveButton(
                    onPressed: () {
                      _saveWorkFormat(
                        dialogContext,
                        idController,
                        nameController,
                        currentStepsWithOrder,
                        isEditing,
                        format,
                      );
                    },
                    isEditing: isEditing,
                  ),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _buildSaveButton(
                  onPressed: () {
                    _saveWorkFormat(
                      dialogContext,
                      idController,
                      nameController,
                      currentStepsWithOrder,
                      isEditing,
                      format,
                    );
                  },
                  isEditing: isEditing,
                ),
              ],
            ),
    );
  }

  Widget _buildSaveButton({
    required VoidCallback onPressed,
    required bool isEditing,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: CoresApp.primaria,
        foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 13,
        ),
        elevation: 2,
        shadowColor: CoresApp.primaria.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
      ),
      onPressed: onPressed,
      icon: const Icon(
        Icons.save_outlined,
        size: 18,
      ),
      label: Text(
        isEditing ? 'Salvar alterações' : 'Criar modelo',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11.5,
        ),
      ),
    );
  }

  // ===============================================================
  // SALVAR MODELO
  // ===============================================================

  Future<void> _saveWorkFormat(
    BuildContext dialogContext,
    TextEditingController idController,
    TextEditingController nameController,
    List<Map<String, String>> currentStepsWithOrder,
    bool isEditing,
    WorkFormat? format,
  ) async {
    if (idController.text.trim().isEmpty ||
        nameController.text.trim().isEmpty) {
      _showDialogValidationMessage(
        dialogContext,
        'Preencha o ID e o nome do modelo.',
      );
      return;
    }

    if (isEditing && format != null && format.id != idController.text.trim()) {
      try {
        await _firebaseService.deleteWorkFormat(
          format.id,
        );
      } catch (_) {}
    }

    final updatedFormat = WorkFormat(
      id: idController.text.trim(),
      name: nameController.text.trim(),
      steps: currentStepsWithOrder,
    );

    try {
      await _firebaseService.saveWorkFormat(
        updatedFormat,
      );

      if (dialogContext.mounted) {
        Navigator.pop(dialogContext);

        await _loadWorkFormats();
      }
    } catch (e) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao salvar: $e',
            ),
            backgroundColor: CoresApp.erro,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ===============================================================
  // COMPONENTES
  // ===============================================================

  Widget _buildIconBox(
    IconData icon, {
    double size = 20,
  }) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: CoresApp.primaria.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CoresApp.primaria.withValues(alpha: 0.20),
        ),
      ),
      child: Icon(
        icon,
        color: CoresApp.primaria,
        size: size,
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CoresApp.primaria.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            icon,
            color: CoresApp.primaria,
            size: 17,
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
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: CoresApp.textoFraco,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCounterBadge(
    int value, {
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: CoresApp.primaria.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: CoresApp.primaria.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: CoresApp.primaria,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: CoresApp.textoSecundario,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool autofocus = false,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onSubmitted: onSubmitted,
      style: TextStyle(
        color: CoresApp.textoPrincipal,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: CoresApp.textoSecundario,
          fontSize: 11.5,
        ),
        prefixIcon: Icon(
          icon,
          color: CoresApp.textoFraco,
          size: 18,
        ),
        filled: true,
        fillColor: CoresTelas.campoFormulario,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(
            color: CoresApp.borda,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(
            color: CoresApp.primaria,
            width: 1.3,
          ),
        ),
      ),
    );
  }

  void _showDialogValidationMessage(
    BuildContext dialogContext,
    String message,
  ) {
    ScaffoldMessenger.of(dialogContext).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CoresApp.erro,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ===============================================================
  // ESTATÍSTICA
  // ===============================================================

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required String description,
  }) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 92,
      ),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            CoresDashboard.card,
            CoresApp.fundoSecundario.withValues(alpha: 0.30),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: CoresApp.borda,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  CoresApp.primaria.withValues(alpha: 0.16),
                  CoresApp.primaria.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: CoresApp.primaria.withValues(alpha: 0.16),
              ),
            ),
            child: Icon(
              icon,
              color: CoresApp.primaria,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: CoresApp.textoFraco,
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  description,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===============================================================
  // DESTAQUE
  // ===============================================================

  Widget _buildHighlightCard() {
    final largest = _largestWorkFormat;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            CoresApp.primaria.withValues(alpha: 0.14),
            CoresDashboard.card,
            CoresDashboard.card,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: CoresApp.primaria.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  CoresApp.primaria.withValues(alpha: 0.18),
                  CoresApp.primaria.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: CoresApp.primaria,
              size: 21,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MODELO EM DESTAQUE',
                  style: TextStyle(
                    color: CoresApp.primaria,
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  largest?.name ?? 'Nenhum modelo cadastrado',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (largest != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'ID ${largest.id}',
                    style: TextStyle(
                      color: CoresApp.textoFraco,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (largest != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: CoresApp.primaria.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: CoresApp.primaria.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.layers_outlined,
                    color: CoresApp.primaria,
                    size: 14,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${largest.steps.length} etapas',
                    style: TextStyle(
                      color: CoresApp.primaria,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ===============================================================
  // TÍTULO
  // ===============================================================

  Widget _buildPageTitle() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                CoresApp.primaria.withValues(alpha: 0.20),
                CoresApp.primaria.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: CoresApp.primaria.withValues(alpha: 0.22),
            ),
          ),
          child: Icon(
            Icons.account_tree_rounded,
            color: CoresApp.primaria,
            size: 25,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cadastro de Trabalho',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'MODELOS DE PROJETOS',
                style: TextStyle(
                  color: CoresApp.primaria,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Crie, organize e reutilize fluxos de trabalho.',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===============================================================
  // AÇÕES
  // ===============================================================

  Widget _buildActionButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppPalette.text,
            side: BorderSide(
              color: CoresApp.borda.withValues(alpha: 0.9),
            ),
            backgroundColor: CoresApp.fundoSecundario.withValues(alpha: 0.25),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          onPressed: _isImporting ? null : _importWorkFormats,
          icon: _isImporting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: CoresApp.primaria,
                  ),
                )
              : Icon(
                  Icons.file_upload_outlined,
                  color: CoresApp.primaria,
                  size: 17,
                ),
          label: const Text(
            'Importar',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11.5,
            ),
          ),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppPalette.text,
            side: BorderSide(
              color: CoresApp.borda.withValues(alpha: 0.9),
            ),
            backgroundColor: CoresApp.fundoSecundario.withValues(alpha: 0.25),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          onPressed: _isExporting ? null : _exportWorkFormats,
          icon: _isExporting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: CoresApp.primaria,
                  ),
                )
              : Icon(
                  Icons.file_download_outlined,
                  color: CoresApp.primaria,
                  size: 17,
                ),
          label: const Text(
            'Exportar',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11.5,
            ),
          ),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: CoresApp.primaria,
            foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            elevation: 3,
            shadowColor: CoresApp.primaria.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          onPressed: () {
            _openFormatDetailDialog();
          },
          icon: const Icon(
            Icons.add_rounded,
            size: 18,
          ),
          label: const Text(
            'Novo Modelo',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }

// ===============================================================
// CARD DE MODELO — COMPACTO
// ===============================================================

  Widget _buildModelCard(
    WorkFormat item, {
    required bool compact,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        hoverColor: CoresDashboard.cardHover,
        onTap: () {
          _openFormatDetailDialog(
            format: item,
          );
        },
        child: Container(
          height: 78,
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                CoresDashboard.card,
                CoresApp.fundoSecundario.withValues(alpha: 0.16),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: CoresApp.borda,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // -------------------------------------------------------
              // ÍCONE
              // -------------------------------------------------------

              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      CoresApp.primaria.withValues(alpha: 0.16),
                      CoresApp.primaria.withValues(alpha: 0.045),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: CoresApp.primaria.withValues(alpha: 0.15),
                  ),
                ),
                child: Icon(
                  Icons.folder_special_outlined,
                  color: CoresApp.primaria,
                  size: 19,
                ),
              ),

              const SizedBox(width: 11),

              // -------------------------------------------------------
              // NOME + ID
              // -------------------------------------------------------

              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'ID ${item.id}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: CoresApp.textoFraco,
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: CoresApp.textoFraco,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.account_tree_outlined,
                          color: CoresApp.textoFraco,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${item.steps.length} etapa${item.steps.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // -------------------------------------------------------
              // BADGE DE ETAPAS
              // -------------------------------------------------------

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: CoresApp.primaria.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: CoresApp.primaria.withValues(alpha: 0.14),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${item.steps.length}',
                      style: TextStyle(
                        color: CoresApp.primaria,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ETAPAS',
                      style: TextStyle(
                        color: CoresApp.textoFraco,
                        fontSize: 6.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 5),

              // -------------------------------------------------------
              // EDITAR
              // -------------------------------------------------------

              _buildActionIconButton(
                tooltip: 'Editar',
                icon: Icons.edit_outlined,
                onPressed: () {
                  _openFormatDetailDialog(
                    format: item,
                  );
                },
              ),

              // -------------------------------------------------------
              // EXCLUIR
              // -------------------------------------------------------

              _buildActionIconButton(
                tooltip: 'Excluir',
                icon: Icons.delete_outline_rounded,
                isDanger: true,
                onPressed: () {
                  _deleteFormat(item.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  // ===============================================================
  // BOTÃO DE AÇÃO
  // ===============================================================

  Widget _buildActionIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool isDanger = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          hoverColor: isDanger
              ? CoresApp.erro.withValues(alpha: 0.08)
              : CoresApp.primaria.withValues(alpha: 0.08),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(
              icon,
              color: isDanger ? CoresApp.erro : CoresApp.textoSecundario,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  // ===============================================================
  // ESTADO VAZIO
  // ===============================================================

  Widget _buildEmptyState() {
    final bool hasSearch = _searchQuery.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 30,
        vertical: 58,
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  CoresApp.primaria.withValues(alpha: 0.12),
                  CoresApp.primaria.withValues(alpha: 0.035),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: CoresApp.primaria.withValues(alpha: 0.15),
              ),
            ),
            child: Icon(
              hasSearch
                  ? Icons.search_off_rounded
                  : Icons.account_tree_outlined,
              color: CoresApp.textoFraco,
              size: 31,
            ),
          ),
          const SizedBox(height: 17),
          Text(
            hasSearch ? 'Nenhum modelo encontrado' : 'Nenhum modelo cadastrado',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasSearch
                ? 'Tente buscar por outro ID ou nome.'
                : 'Crie seu primeiro modelo para começar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CoresApp.textoFraco,
              fontSize: 11,
            ),
          ),
          if (!hasSearch) ...[
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.primaria,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                _openFormatDetailDialog();
              },
              icon: Icon(
                Icons.add_rounded,
                color: CoresApp.textoPrincipal,
                size: 17,
              ),
              label: Text(
                'Criar primeiro modelo',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===============================================================
  // BUILD
  // ===============================================================

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final filteredFormats = _filteredWorkFormats;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: Cabecalho(
          selectedIndex: widget.selectedIndex,
          onSelectTab: widget.onSelectTab,
          searchQuery: '',
          onSearchChanged: (_) {},
          userName: '',
        ),
      ),
      body: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          AppAppearance.watch(context);

          final bool compact = constraints.maxWidth < 900;

          final bool veryCompact = constraints.maxWidth < 600;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              veryCompact
                  ? 12
                  : compact
                      ? 18
                      : 28,
              20,
              veryCompact
                  ? 12
                  : compact
                      ? 18
                      : 28,
              25,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // =================================================
                // PAINEL SUPERIOR
                // =================================================

                Container(
                  padding: EdgeInsets.all(
                    veryCompact ? 16 : 22,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        CoresDashboard.card,
                        CoresApp.primaria.withValues(alpha: 0.035),
                        CoresDashboard.card,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(21),
                    border: Border.all(
                      color: CoresApp.borda,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (compact)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPageTitle(),
                            const SizedBox(
                              height: 18,
                            ),
                            _buildActionButtons(),
                          ],
                        )
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildPageTitle(),
                            ),
                            const SizedBox(
                              width: 20,
                            ),
                            Flexible(
                              flex: 2,
                              child: _buildActionButtons(),
                            ),
                          ],
                        ),
                      const SizedBox(height: 18),
                      if (veryCompact)
                        Column(
                          children: [
                            _buildStatCard(
                              icon: Icons.layers_outlined,
                              label: 'Modelos',
                              value: '${_workFormats.length}',
                              description: 'cadastrados',
                            ),
                            const SizedBox(
                              height: 9,
                            ),
                            _buildStatCard(
                              icon: Icons.account_tree_outlined,
                              label: 'Etapas',
                              value: '$_totalSteps',
                              description: 'configuradas',
                            ),
                            const SizedBox(
                              height: 9,
                            ),
                            _buildStatCard(
                              icon: Icons.analytics_outlined,
                              label: 'Média',
                              value: _averageSteps.toStringAsFixed(
                                1,
                              ),
                              description: 'por modelo',
                            ),
                          ],
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.layers_outlined,
                                label: 'Modelos',
                                value: '${_workFormats.length}',
                                description: 'modelos cadastrados',
                              ),
                            ),
                            const SizedBox(
                              width: 10,
                            ),
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.account_tree_outlined,
                                label: 'Etapas',
                                value: '$_totalSteps',
                                description: 'etapas cadastradas',
                              ),
                            ),
                            const SizedBox(
                              width: 10,
                            ),
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.analytics_outlined,
                                label: 'Média',
                                value: _averageSteps.toStringAsFixed(
                                  1,
                                ),
                                description: 'etapas por modelo',
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                _buildHighlightCard(),

                const SizedBox(height: 20),

                // =================================================
                // LISTA
                // =================================================

                Container(
                  decoration: BoxDecoration(
                    color: CoresDashboard.card,
                    borderRadius: BorderRadius.circular(21),
                    border: Border.all(
                      color: CoresApp.borda,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.13),
                        blurRadius: 20,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // ------------------------------------------------
                      // CABEÇALHO
                      // ------------------------------------------------

                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          veryCompact ? 15 : 22,
                          19,
                          veryCompact ? 15 : 22,
                          15,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    CoresApp.primaria.withValues(
                                      alpha: 0.15,
                                    ),
                                    CoresApp.primaria.withValues(
                                      alpha: 0.04,
                                    ),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(
                                  11,
                                ),
                              ),
                              child: Icon(
                                Icons.view_agenda_rounded,
                                color: CoresApp.primaria,
                                size: 20,
                              ),
                            ),
                            const SizedBox(
                              width: 11,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Modelos cadastrados',
                                    style: TextStyle(
                                      color: CoresApp.textoPrincipal,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(
                                    height: 3,
                                  ),
                                  Text(
                                    'Gerencie seus modelos e fluxos de trabalho',
                                    style: TextStyle(
                                      color: CoresApp.textoFraco,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _buildCounterBadge(
                              filteredFormats.length,
                              label: 'exibindo',
                            ),
                          ],
                        ),
                      ),

                      // ------------------------------------------------
                      // BUSCA
                      // ------------------------------------------------

                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          veryCompact ? 14 : 20,
                          0,
                          veryCompact ? 14 : 20,
                          17,
                        ),
                        child: TextField(
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Buscar por ID ou nome...',
                            hintStyle: TextStyle(
                              color: CoresApp.textoFraco,
                              fontSize: 11.5,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: CoresApp.textoSecundario,
                              size: 20,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    tooltip: 'Limpar busca',
                                    onPressed: () {
                                      setState(
                                        () {
                                          _searchQuery = '';
                                        },
                                      );
                                    },
                                    icon: Icon(
                                      Icons.close_rounded,
                                      color: CoresApp.textoSecundario,
                                      size: 18,
                                    ),
                                  )
                                : null,
                            filled: true,
                            fillColor: CoresTelas.campoFormulario,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                12,
                              ),
                              borderSide: BorderSide(
                                color: CoresApp.borda,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                12,
                              ),
                              borderSide: BorderSide(
                                color: CoresApp.primaria,
                                width: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ------------------------------------------------
                      // CONTEÚDO
                      // ------------------------------------------------

                      _isLoading
                          ? Padding(
                              padding: EdgeInsets.all(
                                60,
                              ),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: CoresApp.primaria,
                                  strokeWidth: 2.5,
                                ),
                              ),
                            )
                          : filteredFormats.isEmpty
                              ? _buildEmptyState()
                              : Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    veryCompact ? 10 : 16,
                                    0,
                                    veryCompact ? 10 : 16,
                                    16,
                                  ),
                                  child: LayoutBuilder(
                                    builder: (
                                      context,
                                      listConstraints,
                                    ) {
                                      AppAppearance.watch(context);

                                      final bool useGrid =
                                          listConstraints.maxWidth >= 760;

                                      if (useGrid) {
                                        return GridView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          itemCount: filteredFormats.length,
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount:
                                                listConstraints.maxWidth >= 1150
                                                    ? 3
                                                    : 2,
                                            crossAxisSpacing: 10,
                                            mainAxisSpacing: 8,
                                            mainAxisExtent: 78,
                                          ),
                                          itemBuilder: (
                                            context,
                                            index,
                                          ) {
                                            return _buildModelCard(
                                              filteredFormats[index],
                                              compact: false,
                                            );
                                          },
                                        );
                                      }

                                      return ListView.separated(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: filteredFormats.length,
                                        separatorBuilder: (
                                          _,
                                          __,
                                        ) {
                                          return const SizedBox(
                                            height: 10,
                                          );
                                        },
                                        itemBuilder: (
                                          context,
                                          index,
                                        ) {
                                          return _buildModelCard(
                                            filteredFormats[index],
                                            compact: true,
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                    ],
                  ),
                ),

                const SizedBox(height: 15),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.cloud_done_outlined,
                      color: CoresApp.textoFraco,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_workFormats.length} modelo(s) armazenado(s)',
                      style: TextStyle(
                        color: CoresApp.textoFraco,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
