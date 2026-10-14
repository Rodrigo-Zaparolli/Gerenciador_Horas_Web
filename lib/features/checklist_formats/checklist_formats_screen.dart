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
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/domain/models/checklist_format_model.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

class ChecklistFormatsScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  const ChecklistFormatsScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required TimeLogStore timeLogStore,
    required String userName,
  });

  @override
  State<ChecklistFormatsScreen> createState() => _ChecklistFormatsScreenState();
}

class _ChecklistFormatsScreenState extends State<ChecklistFormatsScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  List<ChecklistFormat> _checklistFormats = [];

  bool _isLoading = true;
  bool _isExporting = false;
  bool _isImporting = false;

  String _searchQuery = '';

  // ============================================================
  // CICLO DE VIDA
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadChecklistFormats();
  }

  // ============================================================
  // CARREGAMENTO
  // ============================================================

  Future<void> _loadChecklistFormats() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final formats = await _firebaseService.getChecklistFormats();

      if (!mounted) return;

      setState(() {
        _checklistFormats = formats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnackBar(
        'Erro ao carregar modelos de check list: $e',
        isError: true,
      );
    }
  }

  // ============================================================
  // SNACKBAR
  // ============================================================

  void _showSnackBar(
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppPalette.text.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: AppPalette.foregroundOn(isError ? CoresApp.erro : CoresApp.sucesso),
                  size: 17,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: AppPalette.foregroundOn(isError ? CoresApp.erro : CoresApp.sucesso),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: isError ? CoresApp.erro : CoresApp.sucesso,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(18),
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  // ============================================================
  // EXPORTAÇÃO
  // ============================================================

  Future<void> _exportChecklistFormats() async {
    if (_isExporting) return;

    if (_checklistFormats.isEmpty) {
      _showSnackBar(
        'Não existem modelos de checklist para exportar.',
      );
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final List<Map<String, dynamic>> formatsData =
          _checklistFormats.map((format) {
        return {
          'id': format.id,
          'name': format.name,
          'items': format.items,
        };
      }).toList();

      final Map<String, dynamic> exportData = {
        'format': 'gerenciador_horas_checklist_formats',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'total': formatsData.length,
        'checklistFormats': formatsData,
      };

      final String jsonString =
          const JsonEncoder.withIndent('  ').convert(exportData);

      if (kIsWeb) {
        downloadBytes(
          fileName: 'modelos_checklist.json',
          bytes: Uint8List.fromList(utf8.encode(jsonString)),
          mimeType: 'application/json',
        );
        _showSnackBar('Download dos modelos de checklist iniciado.');
      } else {
        final String? outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Exportar modelos de checklist',
          fileName: 'modelos_checklist.json',
          type: FileType.custom,
          allowedExtensions: ['json'],
        );

        if (outputPath == null || outputPath.trim().isEmpty) return;

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

  // ============================================================
  // IMPORTAÇÃO
  // ============================================================

  Future<void> _importChecklistFormats() async {
    if (_isImporting) return;

    setState(() {
      _isImporting = true;
    });

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Importar modelos de checklist',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

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
        throw Exception('O arquivo JSON está vazio.');
      }

      final dynamic decoded = jsonDecode(jsonString);

      if (decoded is! Map) {
        throw Exception('Formato de arquivo inválido.');
      }

      final Map<String, dynamic> jsonData = Map<String, dynamic>.from(decoded);

      final dynamic rawFormats =
          jsonData['checklistFormats'] ?? jsonData['workFormats'];

      if (rawFormats is! List) {
        throw Exception(
          'O arquivo não contém a lista de modelos de checklist.',
        );
      }

      final List<ChecklistFormat> importedFormats = [];

      for (final dynamic item in rawFormats) {
        if (item is! Map) continue;

        final Map<String, dynamic> data = Map<String, dynamic>.from(item);

        final String id = data['id']?.toString().trim() ?? '';

        final String name = data['name']?.toString().trim() ?? '';

        if (id.isEmpty || name.isEmpty) continue;

        final List<Map<String, dynamic>> items = [];

        final dynamic rawItems = data['items'] ?? data['steps'];

        if (rawItems is List) {
          for (int i = 0; i < rawItems.length; i++) {
            final dynamic step = rawItems[i];

            if (step is Map) {
              final Map<String, dynamic> stepMap =
                  Map<String, dynamic>.from(step);

              items.add({
                'order': stepMap['order']?.toString() ?? '${i + 1}',
                'name': stepMap['name']?.toString() ??
                    stepMap['title']?.toString() ??
                    '',
                'completed': stepMap['completed'] == true,
              });
            } else if (step is String) {
              items.add({
                'order': '${i + 1}',
                'name': step,
                'completed': false,
              });
            }
          }
        }

        importedFormats.add(
          ChecklistFormat(
            id: id,
            name: name,
            items: items,
          ),
        );
      }

      if (importedFormats.isEmpty) {
        throw Exception(
          'Nenhum modelo válido foi encontrado no arquivo.',
        );
      }

      if (!mounted) return;

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          AppAppearance.watch(dialogContext);

          return AlertDialog(
            backgroundColor: CoresTelas.fundoModal,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: CoresApp.destaque.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.file_upload_outlined,
                    color: CoresApp.destaque,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Importar modelos',
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            content: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: CoresTelas.fundoModalSecundario,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: CoresApp.bordaSuave,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: CoresApp.destaque,
                    size: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${importedFormats.length} modelo(s) foram encontrados no arquivo.\n\nDeseja importá-los?',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
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
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CoresApp.destaque,
                  foregroundColor: AppPalette.foregroundOn(CoresApp.destaque),
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
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(
                  Icons.file_download_done_rounded,
                  size: 17,
                ),
                label: const Text(
                  'Importar',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return;

      int count = 0;

      for (final format in importedFormats) {
        await _firebaseService.saveChecklistFormat(format);
        count++;
      }

      await _loadChecklistFormats();

      _showSnackBar(
        '$count modelo(s) importado(s) com sucesso.',
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

  // ============================================================
  // EXCLUSÃO
  // ============================================================

  Future<void> _deleteFormat(String id) async {
    try {
      await _firebaseService.deleteChecklistFormat(id);

      await _loadChecklistFormats();

      if (!mounted) return;

      _showSnackBar(
        'Modelo excluído com sucesso!',
      );
    } catch (e) {
      if (!mounted) return;

      _showSnackBar(
        'Erro ao excluir modelo: $e',
        isError: true,
      );
    }
  }

  Future<void> _confirmDelete(
    ChecklistFormat format,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return AlertDialog(
          backgroundColor: CoresTelas.fundoModal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(
            24,
            22,
            20,
            8,
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            24,
            8,
            24,
            10,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            18,
            4,
            18,
            17,
          ),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: CoresApp.erro.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: CoresApp.erro,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Excluir modelo',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CoresApp.erro.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: CoresApp.erro.withValues(alpha: 0.12),
              ),
            ),
            child: Text(
              'Deseja realmente excluir o modelo '
              '"${format.name}"?\n\n'
              'Essa ação não poderá ser desfeita.',
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: 12.5,
                height: 1.5,
              ),
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
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                foregroundColor: AppPalette.foregroundOn(CoresApp.erro),
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
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 17,
              ),
              label: const Text(
                'Excluir',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteFormat(format.id);
    }
  }

  // ============================================================
  // DECORAÇÃO DOS CAMPOS
  // ============================================================

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: CoresTelas.campoFormulario,
      labelStyle: TextStyle(
        color: CoresApp.textoSecundario,
        fontSize: 11.5,
      ),
      hintStyle: TextStyle(
        color: CoresApp.textoSecundario.withValues(alpha: 0.42),
        fontSize: 11.5,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 13,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: CoresApp.bordaSuave,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: CoresApp.destaque,
          width: 1.2,
        ),
      ),
    );
  }

  // ============================================================
  // MODAL DE NOVO / EDIÇÃO
  // ============================================================

  void _openFormatDetailDialog({
    ChecklistFormat? format,
  }) {
    final bool isEditing = format != null;

    final idController = TextEditingController(
      text: format?.id ?? '',
    );

    final nameController = TextEditingController(
      text: format?.name ?? '',
    );

    final itemOrderController = TextEditingController();
    final itemNameController = TextEditingController();

    final List<Map<String, dynamic>> currentItemsWithOrder = [];

    if (format?.items != null) {
      for (int i = 0; i < format!.items.length; i++) {
        final itemData = format.items[i];

        currentItemsWithOrder.add({
          'order': itemData['order']?.toString() ?? '${i + 1}',
          'name': itemData['name']?.toString() ?? '',
          'completed': itemData['completed'] == true,
        });
      }
    }

    itemOrderController.text = '${currentItemsWithOrder.length + 1}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            AppAppearance.watch(context);

            void addItem() {
              final String orderText = itemOrderController.text.trim();

              final String nameText = itemNameController.text.trim();

              if (nameText.isEmpty) {
                return;
              }

              setDialogState(() {
                currentItemsWithOrder.add({
                  'order': orderText.isEmpty
                      ? '${currentItemsWithOrder.length + 1}'
                      : orderText,
                  'name': nameText,
                  'completed': false,
                });

                itemNameController.clear();

                final double nextVal = (double.tryParse(
                          orderText.replaceAll(',', '.'),
                        ) ??
                        currentItemsWithOrder.length.toDouble()) +
                    1.0;

                itemOrderController.text = nextVal % 1 == 0
                    ? nextVal.toInt().toString()
                    : nextVal.toString();
              });
            }

            void removeItem(int index) {
              setDialogState(() {
                currentItemsWithOrder.removeAt(index);

                if (currentItemsWithOrder.isEmpty) {
                  itemOrderController.text = '1';
                }
              });
            }

            void editItem(int index) {
              final item = currentItemsWithOrder[index];

              final editOrderController = TextEditingController(
                text: item['order']?.toString() ?? '',
              );

              final editNameController = TextEditingController(
                text: item['name']?.toString() ?? '',
              );

              showDialog(
                context: context,
                builder: (innerContext) {
                  AppAppearance.watch(innerContext);

                  return AlertDialog(
                    backgroundColor: CoresTelas.fundoModal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    titlePadding: const EdgeInsets.fromLTRB(
                      22,
                      20,
                      18,
                      8,
                    ),
                    contentPadding: const EdgeInsets.fromLTRB(
                      22,
                      8,
                      22,
                      8,
                    ),
                    title: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: CoresApp.destaque.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.edit_outlined,
                            color: CoresApp.destaque,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            'Editar item',
                            style: TextStyle(
                              color: CoresApp.textoPrincipal,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    content: SizedBox(
                      width: 420,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: editOrderController,
                            style: TextStyle(
                              color: CoresApp.textoPrincipal,
                              fontSize: 13,
                            ),
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
                            decoration: _inputDecoration(
                              label: 'Nº / Ordem',
                              prefixIcon: const Icon(
                                Icons.format_list_numbered,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: editNameController,
                            autofocus: true,
                            maxLines: 2,
                            style: TextStyle(
                              color: CoresApp.textoPrincipal,
                              fontSize: 13,
                            ),
                            decoration: _inputDecoration(
                              label: 'Descrição do item',
                              hint: 'Descreva a etapa',
                              prefixIcon: const Icon(
                                Icons.check_circle_outline,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(
                            innerContext,
                          );
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
                          backgroundColor: CoresApp.destaque,
                          foregroundColor: AppPalette.foregroundOn(CoresApp.destaque),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              9,
                            ),
                          ),
                        ),
                        onPressed: () {
                          final String newOrder =
                              editOrderController.text.trim();

                          final String newName = editNameController.text.trim();

                          if (newName.isEmpty) {
                            return;
                          }

                          setDialogState(() {
                            currentItemsWithOrder[index] = {
                              'order':
                                  newOrder.isEmpty ? '${index + 1}' : newOrder,
                              'name': newName,
                              'completed': item['completed'] ?? false,
                            };
                          });

                          Navigator.pop(
                            innerContext,
                          );
                        },
                        icon: const Icon(
                          Icons.check_rounded,
                          size: 17,
                        ),
                        label: const Text(
                          'Atualizar',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            }

            return AlertDialog(
              backgroundColor: CoresTelas.fundoModal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              titlePadding: const EdgeInsets.fromLTRB(
                24,
                20,
                16,
                8,
              ),
              contentPadding: const EdgeInsets.fromLTRB(
                24,
                8,
                24,
                8,
              ),
              actionsPadding: const EdgeInsets.fromLTRB(
                18,
                4,
                18,
                17,
              ),
              title: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: CoresApp.destaque.withValues(
                        alpha: 0.10,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isEditing
                          ? Icons.edit_note_rounded
                          : Icons.playlist_add_check_rounded,
                      color: CoresApp.destaque,
                      size: 22,
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
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isEditing
                              ? 'Atualize as informações e etapas'
                              : 'Crie um modelo reutilizável',
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
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      color: CoresApp.textoSecundario,
                      size: 20,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 700,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ------------------------------------------------
                      // INFORMAÇÕES DO MODELO
                      // ------------------------------------------------

                      _buildDialogSectionHeader(
                        icon: Icons.info_outline_rounded,
                        title: 'Informações do modelo',
                        subtitle: 'Identifique o modelo e o tipo de serviço.',
                      ),

                      const SizedBox(height: 11),

                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: CoresTelas.fundoModalSecundario,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 125,
                              child: TextField(
                                controller: idController,
                                style: TextStyle(
                                  color: CoresApp.textoPrincipal,
                                  fontSize: 13,
                                ),
                                decoration: _inputDecoration(
                                  label: 'ID do modelo',
                                  prefixIcon: const Icon(
                                    Icons.tag_rounded,
                                    size: 17,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: nameController,
                                style: TextStyle(
                                  color: CoresApp.textoPrincipal,
                                  fontSize: 13,
                                ),
                                decoration: _inputDecoration(
                                  label: 'Nome do modelo / tipo de serviço',
                                  hint: 'Ex.: Implantação, Treinamento...',
                                  prefixIcon: const Icon(
                                    Icons.category_outlined,
                                    size: 17,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 23),

                      // ------------------------------------------------
                      // CABEÇALHO DOS ITENS
                      // ------------------------------------------------

                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 19,
                            decoration: BoxDecoration(
                              color: CoresApp.destaque,
                              borderRadius: BorderRadius.circular(
                                3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Etapas do checklist',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: CoresApp.destaque.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(
                                20,
                              ),
                            ),
                            child: Text(
                              '${currentItemsWithOrder.length} ${currentItemsWithOrder.length == 1 ? 'etapa' : 'etapas'}',
                              style: TextStyle(
                                color: CoresApp.destaque,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 11),

                      // ------------------------------------------------
                      // ADICIONAR ITEM
                      // ------------------------------------------------

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: CoresApp.destaque.withValues(alpha: 0.035),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: CoresApp.destaque.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 68,
                              child: TextField(
                                controller: itemOrderController,
                                style: TextStyle(
                                  color: CoresApp.textoPrincipal,
                                  fontSize: 13,
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(
                                      r'^\d*[.,]?\d{0,5}',
                                    ),
                                  ),
                                ],
                                decoration: _inputDecoration(
                                  label: 'Nº',
                                ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: TextField(
                                controller: itemNameController,
                                maxLines: 2,
                                style: TextStyle(
                                  color: CoresApp.textoPrincipal,
                                  fontSize: 13,
                                ),
                                decoration: _inputDecoration(
                                  label: 'Nova etapa',
                                  hint: 'Descreva o item de verificação...',
                                ),
                                onSubmitted: (_) => addItem(),
                              ),
                            ),
                            const SizedBox(width: 9),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: CoresApp.destaque,
                                  foregroundColor: AppPalette.foregroundOn(CoresApp.destaque),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      10,
                                    ),
                                  ),
                                ),
                                onPressed: addItem,
                                icon: const Icon(
                                  Icons.add_rounded,
                                  size: 19,
                                ),
                                label: const Text(
                                  'Adicionar',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ------------------------------------------------
                      // LISTA DE ITENS
                      // ------------------------------------------------

                      Container(
                        constraints: const BoxConstraints(
                          maxHeight: 300,
                        ),
                        decoration: BoxDecoration(
                          color: CoresTelas.fundoModalSecundario,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                        child: currentItemsWithOrder.isEmpty
                            ? _buildEmptyItems()
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: currentItemsWithOrder.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: CoresApp.bordaSuave,
                                ),
                                itemBuilder: (context, index) {
                                  final entry = currentItemsWithOrder[index];

                                  return _buildChecklistItem(
                                    entry: entry,
                                    index: index,
                                    onEdit: () => editItem(index),
                                    onDelete: () => removeItem(index),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
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
                const SizedBox(width: 5),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.destaque,
                    foregroundColor: AppPalette.foregroundOn(CoresApp.destaque),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    final String id = idController.text.trim();

                    final String name = nameController.text.trim();

                    if (id.isEmpty || name.isEmpty) {
                      _showSnackBar(
                        'Preencha o ID e o Nome do modelo.',
                        isError: true,
                      );
                      return;
                    }

                    if (isEditing && format.id != id) {
                      try {
                        await _firebaseService.deleteChecklistFormat(
                          format.id,
                        );
                      } catch (_) {}
                    }

                    final updatedFormat = ChecklistFormat(
                      id: id,
                      name: name,
                      items: currentItemsWithOrder,
                    );

                    try {
                      await _firebaseService.saveChecklistFormat(
                        updatedFormat,
                      );

                      if (!dialogContext.mounted) {
                        return;
                      }

                      Navigator.pop(dialogContext);

                      await _loadChecklistFormats();

                      if (!mounted) return;

                      _showSnackBar(
                        'Modelo salvo com sucesso!',
                      );
                    } catch (e) {
                      if (!dialogContext.mounted) {
                        return;
                      }

                      _showSnackBar(
                        'Erro ao salvar modelo: $e',
                        isError: true,
                      );
                    }
                  },
                  icon: const Icon(
                    Icons.check_rounded,
                    size: 18,
                  ),
                  label: Text(
                    isEditing ? 'Salvar alterações' : 'Criar modelo',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
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
  // CABEÇALHO DE SEÇÃO DO MODAL
  // ============================================================

  Widget _buildDialogSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
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
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: CoresApp.textoSecundario.withValues(alpha: 0.70),
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // ITEM DO CHECKLIST
  // ============================================================

  Widget _buildChecklistItem({
    required Map<String, dynamic> entry,
    required int index,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        hoverColor: CoresApp.destaque.withValues(alpha: 0.035),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 7,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CoresApp.destaque.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: CoresApp.destaque.withValues(alpha: 0.10),
                  ),
                ),
                child: Text(
                  entry['order']?.toString() ?? '${index + 1}',
                  style: TextStyle(
                    color: CoresApp.destaque,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry['name']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Etapa ${index + 1}',
                      style: TextStyle(
                        color: CoresApp.textoSecundario.withValues(alpha: 0.55),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Editar',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 34,
                ),
                padding: EdgeInsets.zero,
                onPressed: onEdit,
                icon: Icon(
                  Icons.edit_outlined,
                  color: CoresApp.textoSecundario,
                  size: 17,
                ),
              ),
              IconButton(
                tooltip: 'Excluir',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 34,
                ),
                padding: EdgeInsets.zero,
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: CoresApp.erro,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ESTADO VAZIO DOS ITENS
  // ============================================================

  Widget _buildEmptyItems() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 38,
        horizontal: 20,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CoresApp.destaque.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.playlist_add_check_outlined,
                color: CoresApp.destaque.withValues(alpha: 0.65),
                size: 24,
              ),
            ),
            const SizedBox(height: 11),
            Text(
              'Nenhuma etapa cadastrada',
              style: TextStyle(
                color: CoresApp.textoPrincipal,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Adicione as etapas acima para montar seu checklist.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CoresApp.textoSecundario.withValues(alpha: 0.65),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CARD DE ESTATÍSTICA
  // ============================================================

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required String description,
  }) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        decoration: BoxDecoration(
          color: CoresTelas.fundoCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: CoresApp.borda,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CoresApp.destaque.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: CoresApp.destaque.withValues(alpha: 0.14),
                ),
              ),
              child: Icon(
                icon,
                color: CoresApp.destaque,
                size: 18,
              ),
            ),
            const SizedBox(width: 11),
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
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CoresApp.textoSecundario.withValues(alpha: 0.75),
                      fontSize: 8.5,
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

  // ============================================================
  // TÍTULO DA PÁGINA
  // ============================================================

  Widget _buildPageTitle() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CoresApp.destaque.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: CoresApp.destaque.withValues(alpha: 0.18),
            ),
          ),
          child: Icon(
            Icons.checklist_rounded,
            color: CoresApp.destaque,
            size: 22,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Modelos de Check List',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Gerenciamento de Etapas',
                style: TextStyle(
                  color: CoresApp.destaque,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Crie, organize e reutilize modelos com suas respectivas etapas.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoSecundario.withValues(alpha: 0.80),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BOTÕES DO TOPO
  // ============================================================

  Widget _buildActionButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppPalette.primary,
            side: BorderSide(
              color: CoresApp.borda,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 10,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          onPressed: _isImporting ? null : _importChecklistFormats,
          icon: _isImporting
              ? SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: CoresApp.destaque,
                  ),
                )
              : Icon(
                  Icons.file_upload_outlined,
                  color: CoresApp.destaque,
                  size: 16,
                ),
          label: const Text(
            'Importar',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppPalette.primary,
            side: BorderSide(
              color: CoresApp.borda,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 10,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          onPressed: _isExporting ? null : _exportChecklistFormats,
          icon: _isExporting
              ? SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: CoresApp.destaque,
                  ),
                )
              : Icon(
                  Icons.file_download_outlined,
                  color: CoresApp.destaque,
                  size: 16,
                ),
          label: const Text(
            'Exportar',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: CoresApp.destaque,
            foregroundColor: AppPalette.foregroundOn(CoresApp.destaque),
            padding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 11,
            ),
            elevation: 2,
            shadowColor: CoresApp.destaque.withValues(alpha: 0.20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          onPressed: () => _openFormatDetailDialog(),
          icon: const Icon(
            Icons.add_rounded,
            size: 17,
          ),
          label: const Text(
            'Novo Modelo',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CAMPO DE PESQUISA
  // ============================================================

  Widget _buildSearchField() {
    return TextField(
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
        });
      },
      style: TextStyle(
        color: CoresApp.textoPrincipal,
        fontSize: 12.5,
      ),
      decoration: InputDecoration(
        hintText: 'Buscar por ID ou nome do modelo...',
        hintStyle: TextStyle(
          color: CoresApp.textoSecundario.withValues(alpha: 0.45),
          fontSize: 12,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: CoresApp.textoSecundario,
          size: 19,
        ),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                tooltip: 'Limpar',
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                  });
                },
                icon: Icon(
                  Icons.close_rounded,
                  color: CoresApp.textoSecundario,
                  size: 17,
                ),
              )
            : null,
        filled: true,
        fillColor: CoresTelas.campoFormulario,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: CoresApp.bordaSuave,
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
    );
  }

  // ============================================================
  // CABEÇALHO DA TABELA
  // ============================================================

  Widget _buildTableHeader(bool compact) {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(
        horizontal: 22,
      ),
      decoration: BoxDecoration(
        color: CoresTelas.cabecalhoTabela,
        border: Border(
          top: BorderSide(
            color: CoresApp.borda,
          ),
          bottom: BorderSide(
            color: CoresApp.borda,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: compact ? 82 : 100,
            child: Text(
              'ID MODELO',
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          SizedBox(
            width: compact ? 80 : 105,
            child: Text(
              'ETAPAS',
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'MODELO DE PROJETO',
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          SizedBox(
            width: compact ? 76 : 95,
            child: Text(
              'AÇÕES',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LINHA DA TABELA
  // ============================================================

  Widget _buildTableRow(
    ChecklistFormat item,
    bool compact,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openFormatDetailDialog(
          format: item,
        ),
        hoverColor: CoresApp.destaque.withValues(
          alpha: 0.035,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 5,
          ),
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                SizedBox(
                  width: compact ? 82 : 100,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: CoresApp.fundoSecundario,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CoresApp.textoSecundario,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: compact ? 80 : 105,
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CoresApp.destaque.withValues(
                            alpha: 0.08,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${item.items.length}',
                          style: TextStyle(
                            color: CoresApp.destaque,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CoresApp.destaque.withValues(
                            alpha: 0.07,
                          ),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          Icons.folder_outlined,
                          color: CoresApp.destaque,
                          size: 18,
                        ),
                      ),
                      const SizedBox(
                        width: 11,
                      ),
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
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(
                              height: 3,
                            ),
                            Text(
                              '${item.items.length} ${item.items.length == 1 ? 'etapa configurada' : 'etapas configuradas'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: CoresApp.textoSecundario.withValues(
                                  alpha: 0.62,
                                ),
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: compact ? 76 : 95,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildRowAction(
                        icon: Icons.edit_outlined,
                        tooltip: 'Editar',
                        onPressed: () => _openFormatDetailDialog(
                          format: item,
                        ),
                      ),
                      const SizedBox(width: 2),
                      _buildRowAction(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Excluir',
                        isDanger: true,
                        onPressed: () => _confirmDelete(item),
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
  }

  // ============================================================
  // AÇÃO DA LINHA
  // ============================================================

  Widget _buildRowAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool isDanger = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(
          minWidth: 34,
          minHeight: 34,
        ),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 17,
          color: isDanger ? CoresApp.erro : CoresApp.textoSecundario,
        ),
      ),
    );
  }

  // ============================================================
  // ESTADO VAZIO DA TABELA
  // ============================================================

  Widget _buildEmptyFormats() {
    final bool hasSearch = _searchQuery.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 58,
        horizontal: 20,
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CoresApp.destaque.withValues(
                alpha: 0.08,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              hasSearch
                  ? Icons.search_off_rounded
                  : Icons.playlist_add_check_rounded,
              color: CoresApp.destaque.withValues(alpha: 0.75),
              size: 27,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            hasSearch ? 'Nenhum modelo encontrado' : 'Nenhum modelo cadastrado',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            hasSearch
                ? 'Tente buscar por outro ID ou nome.'
                : 'Crie seu primeiro modelo de checklist para começar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CoresApp.textoSecundario.withValues(alpha: 0.72),
              fontSize: 10.5,
            ),
          ),
          if (hasSearch) ...[
            const SizedBox(height: 15),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                });
              },
              icon: const Icon(
                Icons.clear_rounded,
                size: 16,
              ),
              label: const Text(
                'Limpar pesquisa',
                style: TextStyle(
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final List<ChecklistFormat> filteredFormats =
        _checklistFormats.where((format) {
      final String query = _searchQuery.toLowerCase().trim();

      return format.id.toLowerCase().contains(query) ||
          format.name.toLowerCase().contains(query);
    }).toList();

    final int totalItems = _checklistFormats.fold<int>(
      0,
      (total, format) => total + format.items.length,
    );

    final double avgItems = _checklistFormats.isNotEmpty
        ? totalItems / _checklistFormats.length
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: Cabecalho(
          selectedIndex: widget.selectedIndex,
          onSelectTab: widget.onSelectTab,
          searchQuery: '',
          onSearchChanged: (String value) {},
          userName: '',
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          AppAppearance.watch(context);
          final bool compact = constraints.maxWidth < 1000;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 18 : 28,
              vertical: 22,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ==================================================
                // HERO
                // ==================================================

                Container(
                  padding: const EdgeInsets.all(
                    20,
                  ),
                  decoration: BoxDecoration(
                    color: CoresTelas.fundoCard,
                    borderRadius: BorderRadius.circular(
                      18,
                    ),
                    border: Border.all(
                      color: CoresApp.borda,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: 0.12,
                        ),
                        blurRadius: 18,
                        offset: const Offset(
                          0,
                          6,
                        ),
                      ),
                    ],
                  ),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPageTitle(),
                            const SizedBox(
                              height: 17,
                            ),
                            _buildActionButtons(),
                            const SizedBox(
                              height: 17,
                            ),
                            Row(
                              children: [
                                _buildStatCard(
                                  icon: Icons.checklist_rtl_rounded,
                                  label: 'Modelos',
                                  value: '${_checklistFormats.length}',
                                  description: 'cadastrados',
                                ),
                                const SizedBox(
                                  width: 9,
                                ),
                                _buildStatCard(
                                  icon: Icons.format_list_bulleted_rounded,
                                  label: 'Etapas',
                                  value: '$totalItems',
                                  description: 'configuradas',
                                ),
                              ],
                            ),
                            const SizedBox(
                              height: 9,
                            ),
                            Row(
                              children: [
                                _buildStatCard(
                                  icon: Icons.analytics_outlined,
                                  label: 'Média',
                                  value: avgItems.toStringAsFixed(
                                    1,
                                  ),
                                  description: 'etapas/modelo',
                                ),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildPageTitle(),
                                  const SizedBox(
                                    height: 15,
                                  ),
                                  _buildActionButtons(),
                                ],
                              ),
                            ),
                            const SizedBox(
                              width: 20,
                            ),
                            Expanded(
                              flex: 4,
                              child: Row(
                                children: [
                                  _buildStatCard(
                                    icon: Icons.checklist_rtl_rounded,
                                    label: 'Modelos',
                                    value: '${_checklistFormats.length}',
                                    description: 'cadastrados',
                                  ),
                                  const SizedBox(
                                    width: 9,
                                  ),
                                  _buildStatCard(
                                    icon: Icons.format_list_bulleted_rounded,
                                    label: 'Etapas',
                                    value: '$totalItems',
                                    description: 'configuradas',
                                  ),
                                  const SizedBox(
                                    width: 9,
                                  ),
                                  _buildStatCard(
                                    icon: Icons.analytics_outlined,
                                    label: 'Média',
                                    value: avgItems.toStringAsFixed(
                                      1,
                                    ),
                                    description: 'etapas/modelo',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),

                const SizedBox(
                  height: 22,
                ),

                // ==================================================
                // LISTAGEM
                // ==================================================

                Container(
                  decoration: BoxDecoration(
                    color: CoresTelas.fundoCard,
                    borderRadius: BorderRadius.circular(
                      18,
                    ),
                    border: Border.all(
                      color: CoresApp.borda,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: 0.11,
                        ),
                        blurRadius: 18,
                        offset: const Offset(
                          0,
                          7,
                        ),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // --------------------------------------------
                      // TÍTULO + CONTADOR
                      // --------------------------------------------

                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          22,
                          19,
                          22,
                          12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: CoresApp.destaque.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(
                                Icons.view_list_rounded,
                                color: CoresApp.destaque,
                                size: 17,
                              ),
                            ),
                            const SizedBox(
                              width: 10,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Modelos cadastrados',
                                    style: TextStyle(
                                      color: CoresApp.textoPrincipal,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(
                                    height: 2,
                                  ),
                                  Text(
                                    'Gerencie seus modelos e respectivas etapas',
                                    style: TextStyle(
                                      color: CoresApp.textoSecundario,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: CoresApp.destaque.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${filteredFormats.length} exibindo',
                                style: TextStyle(
                                  color: CoresApp.destaque,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // --------------------------------------------
                      // PESQUISA
                      // --------------------------------------------

                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          22,
                          0,
                          22,
                          15,
                        ),
                        child: _buildSearchField(),
                      ),

                      // --------------------------------------------
                      // CABEÇALHO
                      // --------------------------------------------

                      _buildTableHeader(
                        compact,
                      ),

                      // --------------------------------------------
                      // CONTEÚDO
                      // --------------------------------------------

                      if (_isLoading)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 65,
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                width: 23,
                                height: 23,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: CoresApp.destaque,
                                ),
                              ),
                              SizedBox(
                                height: 12,
                              ),
                              Text(
                                'Carregando modelos...',
                                style: TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (filteredFormats.isEmpty)
                        _buildEmptyFormats()
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredFormats.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: CoresApp.bordaSuave,
                          ),
                          itemBuilder: (context, index) {
                            return _buildTableRow(
                              filteredFormats[index],
                              compact,
                            );
                          },
                        ),
                    ],
                  ),
                ),

                const SizedBox(
                  height: 15,
                ),

                // ==================================================
                // RODAPÉ INFORMATIVO
                // ==================================================

                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: CoresApp.textoSecundario,
                      size: 14,
                    ),
                    const SizedBox(
                      width: 7,
                    ),
                    Expanded(
                      child: Text(
                        'Os modelos podem ser reutilizados ao criar novos projetos e suas etapas ficam salvas no Firebase.',
                        style: TextStyle(
                          color: CoresApp.textoSecundario.withValues(alpha: 0.62),
                          fontSize: 9.5,
                        ),
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
