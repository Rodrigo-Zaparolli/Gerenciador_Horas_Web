import 'package:flutter/material.dart';
import 'comment_stage.dart';

class CommentStagePanel extends StatefulWidget {
  const CommentStagePanel(
      {super.key,
      required this.load,
      required this.onSelected,
      required this.allowed,
      this.onInvalidated,
      this.disabled = false});
  final Future<List<CommentStage>> Function() load;
  final ValueChanged<CommentStage> onSelected;
  final bool Function() allowed;
  final bool disabled;
  final VoidCallback? onInvalidated;
  @override
  State<CommentStagePanel> createState() => _CommentStagePanelState();
}

class _CommentStagePanelState extends State<CommentStagePanel> {
  List<CommentStage> stages = [];
  CommentStage? selected;
  String? error;
  bool loading = false;

  Future<void> load() async {
    if (loading || widget.disabled || !widget.allowed()) return;
    widget.onInvalidated?.call();
    setState(() {
      loading = true;
      error = null;
      stages = [];
      selected = null;
    });
    try {
      final result = await widget.load();
      if (!mounted || !widget.allowed()) return;
      setState(() => stages = result);
    } catch (e) {
      if (mounted && widget.allowed()) {
        setState(() => error = 'Não foi possível carregar as etapas. $e');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                      key: ValueKey(stages),
                      initialValue: selected?.name,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Etapa do comentário',
                          isDense: true,
                          border: OutlineInputBorder()),
                      hint: const Text('Carregue as etapas da planilha'),
                      items: stages
                          .map((s) => DropdownMenuItem(
                              value: s.name,
                              child: Text(s.name,
                                  overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: loading || widget.disabled || !widget.allowed()
                          ? null
                          : (name) {
                              if (name == null || !widget.allowed()) return;
                              final stage =
                                  stages.singleWhere((s) => s.name == name);
                              widget.onSelected(stage);
                              setState(() => selected = stage);
                            })),
              if (selected != null)
                Text(
                    'Fim: ${selected!.date}   •   Realizado: ${selected!.percent}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              TextButton.icon(
                  onPressed: loading || widget.disabled ? null : load,
                  icon: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync, size: 18),
                  label: Text(loading
                      ? 'Lendo Status Projeto…'
                      : stages.isEmpty
                          ? 'Carregar etapas'
                          : 'Atualizar etapas')),
            ]),
        const SizedBox(height: 6),
        Text(
            error ??
                (selected == null
                    ? 'Escolha uma etapa para preencher nome, finalização e percentual no texto.'
                    : 'Dados da tabela Status Projeto aplicados ao texto. Agenda e demais informações preservadas.'),
            style: TextStyle(
                fontSize: 12,
                color: error == null ? colors.onSurfaceVariant : colors.error)),
      ]),
    );
  }
}
