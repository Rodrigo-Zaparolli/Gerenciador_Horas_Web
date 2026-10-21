import 'package:flutter/material.dart';

Future<Map<String, String>?> showExcelFieldEditDialog(
  BuildContext context,
  Map<String, String> field,
) async {
  final name = TextEditingController(text: field['nome'] ?? '');
  final range = TextEditingController(text: field['intervalo'] ?? '');
  final form = GlobalKey<FormState>();
  final route = DialogRoute<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar campo do Excel'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    decoration:
                        const InputDecoration(labelText: 'Nome do campo'),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Informe o nome do campo.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: range,
                    decoration: const InputDecoration(
                      labelText: 'Células / intervalo do Excel',
                      hintText: "'Checklist-Processo'!\$AD\$4:\$AH\$8",
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Informe o intervalo do Excel.'
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(context, {
                'nome': name.text.trim(),
                'intervalo': range.text.trim().toUpperCase(),
              });
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  try {
    return await Navigator.of(context, rootNavigator: true).push(route);
  } finally {
    await route.completed;
    name.dispose();
    range.dispose();
  }
}
