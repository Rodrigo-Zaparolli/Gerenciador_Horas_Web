import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
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
  });

  @override
  State<ChecklistFormatsScreen> createState() => _ChecklistFormatsScreenState();
}

class _ChecklistFormatsScreenState extends State<ChecklistFormatsScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  List<ChecklistFormat> _checklistFormats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChecklistFormats();
  }

  Future<void> _loadChecklistFormats() async {
    setState(() => _isLoading = true);
    try {
      final formats = await _firebaseService.getChecklistFormats();
      setState(() {
        _checklistFormats = formats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar modelos de check list: $e'),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }
  }

  Future<void> _deleteFormat(String id) async {
    try {
      await _firebaseService.deleteChecklistFormat(id);
      await _loadChecklistFormats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Modelo excluído com sucesso!'),
            backgroundColor: CoresApp.sucesso,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir modelo: $e'),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }
  }

  void _openFormatDetailDialog({ChecklistFormat? format}) {
    final isEditing = format != null;
    final idController = TextEditingController(text: format?.id ?? '');
    final nameController = TextEditingController(text: format?.name ?? '');

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

    if (itemOrderController.text.isEmpty) {
      itemOrderController.text = '${currentItemsWithOrder.length + 1}';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            AppAppearance.watch(context);
            void addItem() {
              final orderText = itemOrderController.text.trim();
              final nameText = itemNameController.text.trim();

              if (nameText.isNotEmpty) {
                setDialogState(() {
                  currentItemsWithOrder.add({
                    'order': orderText.isEmpty
                        ? '${currentItemsWithOrder.length + 1}'
                        : orderText,
                    'name': nameText,
                    'completed': false,
                  });
                  itemNameController.clear();
                  final nextVal =
                      (double.tryParse(orderText.replaceAll(',', '.')) ??
                              currentItemsWithOrder.length.toDouble()) +
                          1.0;
                  itemOrderController.text = nextVal % 1 == 0
                      ? nextVal.toInt().toString()
                      : nextVal.toString();
                });
              }
            }

            void removeItem(int index) {
              setDialogState(() {
                currentItemsWithOrder.removeAt(index);
              });
            }

            void editItem(int index) {
              final item = currentItemsWithOrder[index];
              final editOrderController =
                  TextEditingController(text: item['order']?.toString() ?? '');
              final editNameController =
                  TextEditingController(text: item['name']?.toString() ?? '');

              showDialog(
                context: context,
                builder: (innerContext) {
                  AppAppearance.watch(innerContext);

                  return AlertDialog(
                    backgroundColor: CoresTelas.fundoModal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: CoresApp.borda.withValues(alpha: 0.5)),
                    ),
                    title: Text(
                      'Editar Item do Check List',
                      style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: editOrderController,
                          style: TextStyle(
                              color: CoresApp.textoPrincipal, fontSize: 13),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Nº / Ordem',
                            labelStyle: TextStyle(
                                color: CoresApp.textoSecundario, fontSize: 12),
                            filled: true,
                            fillColor: CoresTelas.campoFormulario,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: CoresApp.borda),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: CoresApp.primaria),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: editNameController,
                          style: TextStyle(
                              color: CoresApp.textoPrincipal, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Descrição do Item',
                            labelStyle: TextStyle(
                                color: CoresApp.textoSecundario, fontSize: 12),
                            filled: true,
                            fillColor: CoresTelas.campoFormulario,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: CoresApp.borda),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: CoresApp.primaria),
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(innerContext),
                        child: Text('Cancelar',
                            style: TextStyle(color: CoresApp.textoSecundario)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CoresApp.primaria,
                          foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          final newOrder = editOrderController.text.trim();
                          final newName = editNameController.text.trim();

                          if (newName.isNotEmpty) {
                            setDialogState(() {
                              currentItemsWithOrder[index] = {
                                'order': newOrder.isEmpty
                                    ? '${index + 1}'
                                    : newOrder,
                                'name': newName,
                                'completed': item['completed'] ?? false,
                              };
                            });
                            Navigator.pop(innerContext);
                          }
                        },
                        child: const Text('Atualizar',
                            style: TextStyle(fontWeight: FontWeight.bold)),
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
                side: BorderSide(color: CoresApp.borda.withValues(alpha: 0.6)),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: CoresApp.primaria.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.checklist_rounded,
                            color: CoresApp.primaria, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isEditing
                            ? 'Editar Modelo de Check List'
                            : 'Novo Modelo de Check List',
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: CoresApp.textoSecundario),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 130,
                            child: TextField(
                              controller: idController,
                              style: TextStyle(
                                  color: CoresApp.textoPrincipal, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'ID do Modelo',
                                labelStyle: TextStyle(
                                    color: CoresApp.textoSecundario,
                                    fontSize: 12),
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      BorderSide(color: CoresApp.bordaSuave),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      BorderSide(color: CoresApp.primaria),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: nameController,
                              style: TextStyle(
                                  color: CoresApp.textoPrincipal, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'Nome do Modelo / Tipo de Serviço',
                                labelStyle: TextStyle(
                                    color: CoresApp.textoSecundario,
                                    fontSize: 12),
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      BorderSide(color: CoresApp.bordaSuave),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      BorderSide(color: CoresApp.primaria),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Itens de Verificação',
                            style: TextStyle(
                              color: CoresApp.secundaria,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: CoresTelas.fundoModalSecundario,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: CoresApp.bordaSuave),
                            ),
                            child: Text(
                              'Total: ${currentItemsWithOrder.length}',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: TextField(
                              controller: itemOrderController,
                              style: TextStyle(
                                  color: CoresApp.textoPrincipal, fontSize: 13),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*[.,]?\d{0,5}'))
                              ],
                              decoration: InputDecoration(
                                labelText: 'Nº',
                                labelStyle: TextStyle(
                                    color: CoresApp.textoSecundario,
                                    fontSize: 12),
                                isDense: true,
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      BorderSide(color: CoresApp.bordaSuave),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      BorderSide(color: CoresApp.primaria),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: itemNameController,
                              style: TextStyle(
                                  color: CoresApp.textoPrincipal, fontSize: 13),
                              decoration: InputDecoration(
                                hintText:
                                    'Descrição do item (ex: Verificar normas)',
                                hintStyle: TextStyle(
                                    color: CoresApp.textoSecundario
                                        .withValues(alpha: 0.5),
                                    fontSize: 12),
                                isDense: true,
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      BorderSide(color: CoresApp.bordaSuave),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      BorderSide(color: CoresApp.primaria),
                                ),
                              ),
                              onSubmitted: (_) => addItem(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CoresApp.primaria,
                              foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: addItem,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Incluir',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 260),
                        decoration: BoxDecoration(
                          color: CoresTelas.fundoModalSecundario,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: CoresApp.bordaSuave),
                        ),
                        child: currentItemsWithOrder.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Text(
                                    'Nenhum item cadastrado neste modelo.',
                                    style: TextStyle(
                                        color: CoresApp.textoSecundario,
                                        fontSize: 12),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: currentItemsWithOrder.length,
                                separatorBuilder: (_, __) => Divider(
                                    color: CoresApp.bordaSuave, height: 1),
                                itemBuilder: (context, index) {
                                  final entry = currentItemsWithOrder[index];
                                  return InkWell(
                                    onTap: () => editItem(index),
                                    child: Padding(
                                      // [AJUSTE UI]: Altere o padding vertical (ex: 8 para 12) para ajustar a altura da linha dos itens no modal
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: CoresApp.primaria
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              entry['order']?.toString() ?? '',
                                              style: TextStyle(
                                                color: CoresApp.secundaria,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              entry['name']?.toString() ?? '',
                                              style: TextStyle(
                                                  color:
                                                      CoresApp.textoPrincipal,
                                                  fontSize: 13),
                                            ),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                // [AJUSTE UI]: Ajuste o tamanho visual e constraints dos botões de ação do item se necessário
                                                constraints:
                                                    const BoxConstraints(
                                                        minWidth: 32,
                                                        minHeight: 32),
                                                padding: EdgeInsets.zero,
                                                icon: Icon(Icons.edit_outlined,
                                                    color: CoresApp
                                                        .textoSecundario,
                                                    size: 18),
                                                tooltip: 'Editar item',
                                                onPressed: () =>
                                                    editItem(index),
                                              ),
                                              const SizedBox(width: 4),
                                              IconButton(
                                                constraints:
                                                    const BoxConstraints(
                                                        minWidth: 32,
                                                        minHeight: 32),
                                                padding: EdgeInsets.zero,
                                                icon: Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    color: CoresApp.erro,
                                                    size: 18),
                                                tooltip: 'Excluir item',
                                                onPressed: () =>
                                                    removeItem(index),
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
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('Cancelar',
                      style: TextStyle(color: CoresApp.textoSecundario)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(TamanhosApp.raioBotao)),
                  ),
                  onPressed: () async {
                    if (idController.text.trim().isEmpty ||
                        nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              const Text('Preencha o ID e o Nome do modelo.'),
                          backgroundColor: CoresApp.erro,
                        ),
                      );
                      return;
                    }

                    if (isEditing && format.id != idController.text.trim()) {
                      try {
                        await _firebaseService.deleteChecklistFormat(format.id);
                      } catch (_) {}
                    }

                    final updatedFormat = ChecklistFormat(
                      id: idController.text.trim(),
                      name: nameController.text.trim(),
                      items: currentItemsWithOrder,
                    );

                    try {
                      await _firebaseService.saveChecklistFormat(updatedFormat);
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                        _loadChecklistFormats();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Modelo salvo com sucesso!'),
                            backgroundColor: CoresApp.sucesso,
                          ),
                        );
                      }
                    } catch (e) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erro ao salvar modelo: $e'),
                            backgroundColor: CoresApp.erro,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Salvar alterações',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    return Scaffold(
      backgroundColor: CoresTelas.fundoPrincipal,
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
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: CoresApp.primaria.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: CoresApp.primaria.withValues(alpha: 0.3)),
                      ),
                      child: Icon(Icons.checklist_rounded,
                          color: CoresApp.primaria, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Modelos de Check List',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Gerencie os modelos de verificação para os serviços',
                          style: TextStyle(
                            fontSize: 13,
                            color: CoresApp.textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(TamanhosApp.raioBotao),
                    ),
                  ),
                  onPressed: () => _openFormatDetailDialog(),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text(
                    'Novo Modelo',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: CoresTelas.fundoCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CoresApp.borda.withValues(alpha: 0.6)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      // [AJUSTE UI]: Altere o padding vertical do cabeçalho da tabela se desejar ajustar a altura dele
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: CoresTelas.cabecalhoTabela,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
                        border: Border(
                          bottom: BorderSide(
                              color: CoresApp.borda.withValues(alpha: 0.6)),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text('ID',
                                style: TextStyle(
                                    color: CoresApp.textoPrincipal,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ),
                          SizedBox(
                            width: 130,
                            child: Text('Nº Itens',
                                style: TextStyle(
                                    color: CoresApp.textoPrincipal,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ),
                          Expanded(
                            child: Text('Nome do Modelo',
                                style: TextStyle(
                                    color: CoresApp.textoPrincipal,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ),
                          SizedBox(
                            width: 110,
                            child: Text('Ações',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: CoresApp.textoPrincipal,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _isLoading
                          ? Center(
                              child: CircularProgressIndicator(
                                  color: CoresApp.primaria))
                          : _checklistFormats.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.inbox_rounded,
                                          size: 48, color: CoresApp.textoFraco),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Nenhum modelo de check list cadastrado.',
                                        style: TextStyle(
                                            color: CoresApp.textoSecundario,
                                            fontSize: 14),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _checklistFormats.length,
                                  separatorBuilder: (_, __) => Divider(
                                      color: CoresApp.bordaSuave, height: 1),
                                  itemBuilder: (context, index) {
                                    final item = _checklistFormats[index];
                                    return InkWell(
                                      onTap: () =>
                                          _openFormatDetailDialog(format: item),
                                      child: Padding(
                                        // [AJUSTE UI]: Reduza ou aumente o padding vertical (ex: de 10 a 14) para diminuir/aumentar a altura das linhas da tabela
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24, vertical: 10),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 120,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: CoresApp.primaria
                                                      .withValues(alpha: 0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  item.id,
                                                  style: TextStyle(
                                                      color:
                                                          CoresApp.secundaria,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 130,
                                              child: Text(
                                                  '${item.items.length} iten(s)',
                                                  style: TextStyle(
                                                      color: CoresApp
                                                          .textoSecundario,
                                                      fontSize: 13)),
                                            ),
                                            Expanded(
                                              child: Text(item.name,
                                                  style: TextStyle(
                                                      color: CoresApp
                                                          .textoPrincipal,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      fontSize: 13)),
                                            ),
                                            SizedBox(
                                              width: 110,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  IconButton(
                                                    // [AJUSTE UI]: Ajuste o tamanho visual e constraints dos botões de ação da linha se necessário
                                                    constraints:
                                                        const BoxConstraints(
                                                            minWidth: 32,
                                                            minHeight: 32),
                                                    padding: EdgeInsets.zero,
                                                    icon: Icon(
                                                        Icons.edit_outlined,
                                                        color:
                                                            CoresApp.secundaria,
                                                        size: 18),
                                                    tooltip: 'Editar modelo',
                                                    onPressed: () =>
                                                        _openFormatDetailDialog(
                                                            format: item),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  IconButton(
                                                    constraints:
                                                        const BoxConstraints(
                                                            minWidth: 32,
                                                            minHeight: 32),
                                                    padding: EdgeInsets.zero,
                                                    icon: Icon(
                                                        Icons
                                                            .delete_outline_rounded,
                                                        color: CoresApp.erro,
                                                        size: 18),
                                                    tooltip: 'Excluir modelo',
                                                    onPressed: () =>
                                                        _deleteFormat(item.id),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
