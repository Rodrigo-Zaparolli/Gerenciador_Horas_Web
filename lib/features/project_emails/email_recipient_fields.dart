import 'package:flutter/material.dart';
import 'email_document.dart';

class EmailRecipientFields extends StatefulWidget {
  final List<EmailContact> contacts;
  final VoidCallback onChanged;
  const EmailRecipientFields({super.key, required this.contacts, required this.onChanged});
  @override
  State<EmailRecipientFields> createState() => EmailRecipientFieldsState();
}

class EmailRecipientFieldsState extends State<EmailRecipientFields> {
  final _controllers = {'Para': TextEditingController(), 'Cc': TextEditingController()};
  final _errors = <String, String?>{};

  bool _available(EmailContact contact) => validEmail(contact.email) &&
      !widget.contacts.any((c) => ['Para', 'Cc'].contains(c.destination) &&
          c.email.trim().toLowerCase() == contact.email.trim().toLowerCase());

  bool commitPending() {
    final entries = <String, List<String>>{};
    for (final entry in _controllers.entries) {
      final emails = entry.value.text.split(RegExp(r'[;,\n]+'))
          .map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (emails.any((e) => !validEmail(e))) {
        setState(() => _errors[entry.key] = 'Informe e-mails válidos, separados por ponto e vírgula.');
        return false;
      }
      entries[entry.key] = emails;
    }
    for (final entry in entries.entries) {
      final opposite = entry.key == 'Para' ? 'Cc' : 'Para';
      if (entry.value.any((email) =>
          widget.contacts.any((c) => c.destination == opposite &&
              c.email.trim().toLowerCase() == email.toLowerCase()) ||
          entries[opposite]!.any((other) => other.toLowerCase() == email.toLowerCase()))) {
        setState(() => _errors[entry.key] =
            'Este endereço já está em $opposite. Remova-o de lá antes de adicionar aqui.');
        return false;
      }
    }
    for (final entry in entries.entries) {
      for (final email in entry.value) {
        _select(email, entry.key);
      }
      _controllers[entry.key]!.clear();
    }
    setState(() => _errors.clear());
    return true;
  }

  void _select(String email, String destination) {
    final matches = widget.contacts.where((c) => c.email.trim().toLowerCase() == email.toLowerCase());
    if (matches.isEmpty) {
      widget.contacts.add(EmailContact(email: email, destination: destination,
          group: 'Cliente'));
    } else {
      for (final c in matches) { c.destination = 'Não incluir'; }
      matches.first.destination = destination;
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    for (final destination in ['Para', 'Cc']) ...[
      InputDecorator(
          key: ValueKey('recipient-container-$destination'),
          decoration: InputDecoration(labelText: destination,
              errorText: _errors[destination],
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
          child: Row(children: [
            Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal,
                child: Row(children: [
        for (final contact in widget.contacts.where((c) => c.destination == destination))
          Padding(padding: const EdgeInsets.only(right: 6),
              child: InputChip(label: Tooltip(message: '${contact.name} <${contact.email}>',
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(contact.name.trim().isEmpty ? contact.email : contact.name,
                          overflow: TextOverflow.ellipsis))),
              onDeleted: () { contact.destination = 'Não incluir'; widget.onChanged(); }),
          ),
      SizedBox(width: 220, child: TextField(
          key: ValueKey('recipient-input-$destination'),
          controller: _controllers[destination],
          keyboardType: TextInputType.emailAddress, autocorrect: false,
          decoration: const InputDecoration(
              hintText: 'Digite um e-mail e pressione Enter',
              border: InputBorder.none, enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none, filled: false, isDense: true),
          onSubmitted: (_) => commitPending())),
              ]))),
                PopupMenuButton<String>(tooltip: 'Adicionar em $destination',
                    icon: const Icon(Icons.add),
                    itemBuilder: (_) => [
                      if (widget.contacts.any(_available)) ...[
                        const PopupMenuItem(value: '__all__',
                            child: Row(children: [Icon(Icons.group_add_outlined),
                              SizedBox(width: 8), Text('Adicionar todos')])),
                        const PopupMenuDivider(),
                      ],
                      if (!widget.contacts.any(_available))
                        const PopupMenuItem(enabled: false,
                            child: Text('Nenhum contato disponível. Importe a planilha ou remova um destinatário para adicioná-lo novamente.')),
                      for (final c in widget.contacts.where(_available))
                        PopupMenuItem(value: c.email.trim(),
                            child: Text(c.name.isEmpty ? c.email : '${c.name} — ${c.email}'))
                    ],
                    onSelected: (email) {
                      if (email == '__all__') {
                        final emails = widget.contacts
                            .where(_available)
                            .map((c) => c.email.trim().toLowerCase()).toSet();
                        for (final address in emails) { _select(address, destination); }
                      } else {
                        _select(email, destination);
                      }
                    }),
          ])),
      const SizedBox(height: 12),
    ],
  ]);

  @override
  void dispose() {
    for (final controller in _controllers.values) { controller.dispose(); }
    super.dispose();
  }
}
