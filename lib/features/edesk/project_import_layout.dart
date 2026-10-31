import 'package:flutter/material.dart';

class ProjectImportLayout extends StatefulWidget {
  const ProjectImportLayout(
      {super.key,
      required this.children,
      required this.actions,
      this.onManual,
      this.onClose,
      this.summary,
      this.message,
      this.reviewReady = false,
      this.busy = false});
  final List<Widget> children;
  final List<Widget> actions;
  final VoidCallback? onManual, onClose;
  final bool busy;
  final bool reviewReady;
  final Widget? summary;
  final Widget? message;
  @override
  State<ProjectImportLayout> createState() => _ProjectImportLayoutState();
}

class _ProjectImportLayoutState extends State<ProjectImportLayout> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
        canPop: !widget.busy,
        child: Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: SizedBox(
            width: 1200,
            height: MediaQuery.sizeOf(context).height * .94,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(12)),
                            child: Icon(Icons.download_rounded,
                                color: colors.onPrimaryContainer)),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('Novo trabalho',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('Importar do E-Desk pelo ID',
                                  style: TextStyle(
                                      color: colors.onSurfaceVariant)),
                            ])),
                        IconButton(
                            tooltip: 'Fechar',
                            onPressed: widget.busy ? null : widget.onClose,
                            icon: const Icon(Icons.close))
                      ]),
                      const SizedBox(height: 12),
                      Wrap(spacing: 4, children: [
                        OutlinedButton(
                            onPressed: widget.busy ? null : widget.onManual,
                            child: const Text('Cadastro manual')),
                        FilledButton.tonal(
                            onPressed: null,
                            style: ButtonStyle(
                                foregroundColor:
                                    WidgetStatePropertyAll(colors.primary),
                                backgroundColor: WidgetStatePropertyAll(colors
                                    .primaryContainer
                                    .withValues(alpha: .35))),
                            child: const Text('Importar pelo ID')),
                      ]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        for (final (index, label) in const [
                          (1, 'Buscar solicita\u00e7\u00e3o'),
                          (2, 'Conferir dados e etapas'),
                          (3, 'Cadastrar no app')
                        ])
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                  color: (widget.reviewReady
                                          ? index == 2
                                          : index == 1)
                                      ? colors.primaryContainer
                                      : colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text('$index  $label',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: (widget.reviewReady
                                              ? index == 2
                                              : index == 1)
                                          ? colors.onPrimaryContainer
                                          : colors.onSurfaceVariant))),
                      ]),
                      const SizedBox(height: 14),
                      if (widget.busy) const LinearProgressIndicator(),
                      Expanded(
                          child: Scrollbar(
                              controller: _scroll,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                  controller: _scroll,
                                  padding: const EdgeInsets.only(right: 10),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: widget.children)))),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      if (widget.message != null) ...[
                        widget.message!,
                        const SizedBox(height: 8),
                      ],
                      LayoutBuilder(builder: (context, constraints) {
                        final actions = Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 12,
                            runSpacing: 8,
                            children: widget.actions);
                        if (widget.summary == null) return actions;
                        return constraints.maxWidth < 650
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                    widget.summary!,
                                    const SizedBox(height: 10),
                                    actions
                                  ])
                            : Row(children: [
                                Expanded(child: widget.summary!),
                                const SizedBox(width: 12),
                                actions
                              ]);
                      }),
                    ])),
          ),
        ));
  }
}

class ProjectImportSection extends StatelessWidget {
  const ProjectImportSection(
      {super.key,
      required this.number,
      required this.title,
      required this.child,
      this.trailing});
  final int number;
  final String title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
          color: colors.surface,
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                CircleAvatar(
                    radius: 13,
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    child: Text('$number')),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (trailing != null) trailing!,
              ]),
          const SizedBox(height: 10),
          child,
        ]));
  }
}

class ProjectImportQuery extends StatelessWidget {
  const ProjectImportQuery(
      {super.key,
      required this.controller,
      required this.onSearch,
      required this.message,
      this.hasError = false,
      this.busy = false,
      this.found = false});
  final TextEditingController controller;
  final VoidCallback? onSearch;
  final String message;
  final bool busy, found;
  final bool hasError;
  @override
  Widget build(BuildContext context) => ProjectImportSection(
      number: 1,
      title: 'Consultar solicitação',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, constraints) {
          final field = TextField(
              key: const ValueKey('import-request-id'),
              controller: controller,
              enabled: !busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'ID da solicitação no E-Desk',
                  hintText: 'Ex.: 2265123',
                  border: OutlineInputBorder(),
                  isDense: true),
              onSubmitted: busy ? null : (_) => onSearch?.call());
          final button = FilledButton.icon(
              onPressed: busy ? null : onSearch,
              icon: const Icon(Icons.search),
              label: const Text('Buscar no E-Desk'));
          return constraints.maxWidth < 550
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [field, const SizedBox(height: 10), button])
              : Row(children: [
                  Expanded(child: field),
                  const SizedBox(width: 12),
                  button
                ]);
        }),
        const SizedBox(height: 12),
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: hasError
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(
                  hasError
                      ? Icons.error_outline
                      : found
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                  size: 18,
                  color: hasError
                      ? Theme.of(context).colorScheme.onErrorContainer
                      : Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                  child: SelectableText(message,
                      style: TextStyle(
                          color: hasError
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : null))),
            ])),
      ]));
}

class ProjectImportMappingRow extends StatelessWidget {
  const ProjectImportMappingRow(
      {super.key,
      required this.title,
      required this.selected,
      required this.linked,
      required this.checkbox,
      required this.work,
      required this.hours,
      required this.start,
      required this.end});
  final String title;
  final bool selected, linked;
  final Widget checkbox, work, hours, start, end;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: .035)
              : colors.surfaceContainerLow,
          border: Border.all(
              color: selected && !linked
                  ? colors.tertiary
                  : colors.outlineVariant),
          borderRadius: BorderRadius.circular(10)),
      child: LayoutBuilder(builder: (context, box) {
        final name =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(
              linked
                  ? 'Trabalho vinculado'
                  : 'Selecione o trabalho correspondente',
              style: TextStyle(
                  fontSize: 11,
                  color: selected && !linked
                      ? colors.tertiary
                      : colors.onSurfaceVariant)),
        ]);
        if (box.maxWidth < 960) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  checkbox,
                  const SizedBox(width: 6),
                  Expanded(child: name)
                ]),
                const SizedBox(height: 12),
                work,
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  SizedBox(width: 100, child: hours),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('In\u00edcio',
                            style: TextStyle(fontSize: 11)),
                        start
                      ]),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Fim', style: TextStyle(fontSize: 11)),
                        end
                      ]),
                ]),
              ]);
        }
        return Row(children: [
          SizedBox(width: 36, child: checkbox),
          Expanded(flex: 3, child: name),
          const SizedBox(width: 12),
          Expanded(flex: 4, child: work),
          const SizedBox(width: 12),
          SizedBox(width: 100, child: hours),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('In\u00edcio', style: TextStyle(fontSize: 11)),
            start
          ]),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Fim', style: TextStyle(fontSize: 11)),
            end
          ]),
        ]);
      }),
    );
  }
}
