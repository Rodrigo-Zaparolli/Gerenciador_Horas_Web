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
      this.busy = false});
  final List<Widget> children;
  final List<Widget> actions;
  final VoidCallback? onManual, onClose;
  final bool busy;
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
                              const Text('Importar do E-Desk pelo ID'),
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
          color: Color.alphaBlend(
              colors.surfaceContainerHighest.withValues(alpha: .55),
              colors.surface),
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
      this.busy = false,
      this.found = false});
  final TextEditingController controller;
  final VoidCallback? onSearch;
  final String message;
  final bool busy, found;
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
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(found ? Icons.check_circle_outline : Icons.info_outline,
              size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(message)),
        ]),
      ]));
}
