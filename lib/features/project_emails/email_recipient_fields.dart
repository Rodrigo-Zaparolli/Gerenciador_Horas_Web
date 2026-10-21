import 'package:flutter/material.dart';
import 'email_document.dart';

class EmailRecipientFields extends StatefulWidget {
  final List<EmailContact> contacts;
  final VoidCallback onChanged;
  final Future<EmailContact?> Function()? pickCompanyContact;
  final List<EmailContact> companyContacts;
  const EmailRecipientFields(
      {super.key,
      required this.contacts,
      required this.onChanged,
      this.companyContacts = const [],
      this.pickCompanyContact});
  @override
  State<EmailRecipientFields> createState() => EmailRecipientFieldsState();
}

class EmailRecipientFieldsState extends State<EmailRecipientFields> {
  final _controllers = {
    'Para': TextEditingController(),
    'Cc': TextEditingController()
  };
  final _errors = <String, String?>{};

  bool _available(EmailContact contact) =>
      validEmail(contact.email) &&
      !widget.contacts.any((c) =>
          ['Para', 'Cc'].contains(c.destination) &&
          c.email.trim().toLowerCase() == contact.email.trim().toLowerCase());

  bool commitPending() {
    final entries = <String, List<String>>{};
    for (final entry in _controllers.entries) {
      final emails = entry.value.text
          .split(RegExp(r'[;,\n]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (emails.any((e) => !validEmail(e))) {
        setState(() => _errors[entry.key] =
            'Informe e-mails válidos, separados por ponto e vírgula.');
        return false;
      }
      entries[entry.key] = emails;
    }
    for (final entry in entries.entries) {
      final opposite = entry.key == 'Para' ? 'Cc' : 'Para';
      if (entry.value.any((email) =>
          widget.contacts.any((c) =>
              c.destination == opposite &&
              c.email.trim().toLowerCase() == email.toLowerCase()) ||
          entries[opposite]!
              .any((other) => other.toLowerCase() == email.toLowerCase()))) {
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
    final matches = widget.contacts
        .where((c) => c.email.trim().toLowerCase() == email.toLowerCase());
    if (matches.isEmpty) {
      widget.contacts.add(EmailContact(
          email: email, destination: destination, group: 'Cliente'));
    } else {
      for (final c in matches) {
        c.destination = 'Não incluir';
      }
      matches.first.destination = destination;
    }
    widget.onChanged();
  }

  void _selectCompany(EmailContact contact, String destination) {
    final matches = widget.contacts
        .where((c) =>
            c.email.trim().toLowerCase() == contact.email.trim().toLowerCase())
        .toList();
    if (matches.isEmpty) {
      widget.contacts.add(EmailContact(
          name: contact.name,
          email: contact.email.trim(),
          group: contact.group));
    } else if (matches.first.name.trim().isEmpty) {
      matches.first.name = contact.name;
    }
    _select(contact.email.trim(), destination);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final destination in ['Para', 'Cc']) ...[
          InputDecorator(
              key: ValueKey('recipient-container-$destination'),
              decoration: InputDecoration(
                  labelText: destination,
                  errorText: _errors[destination],
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  for (final contact in widget.contacts.where(
                                      (c) => c.destination == destination))
                                    InputChip(
                                        label: Tooltip(
                                            message:
                                                '${contact.name} <${contact.email}>',
                                            child: ConstrainedBox(
                                                constraints: BoxConstraints(
                                                    maxWidth:
                                                        (constraints.maxWidth -
                                                                76)
                                                            .clamp(1, 320)
                                                            .toDouble()),
                                                child: Text(
                                                    contact.name.trim().isEmpty
                                                        ? contact.email
                                                        : '${contact.name}\n${contact.email}',
                                                    softWrap: true))),
                                        onDeleted: () {
                                          contact.destination =
                                              'N\u00e3o incluir';
                                          widget.onChanged();
                                        }),
                                  SizedBox(
                                      width: constraints.maxWidth
                                          .clamp(1, 220)
                                          .toDouble(),
                                      child: TextField(
                                          key: ValueKey(
                                              'recipient-input-$destination'),
                                          controller: _controllers[destination],
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          autocorrect: false,
                                          decoration: const InputDecoration(
                                              hintText:
                                                  'Digite um e-mail e pressione Enter',
                                              border: InputBorder.none,
                                              enabledBorder: InputBorder.none,
                                              focusedBorder: InputBorder.none,
                                              filled: false,
                                              isDense: true),
                                          onSubmitted: (_) => commitPending())),
                                ]))),
                if (widget.pickCompanyContact != null)
                  IconButton(
                      tooltip: 'Buscar colaborador para $destination',
                      icon: const Icon(Icons.person_search_outlined),
                      onPressed: () async {
                        try {
                          final contact = await widget.pickCompanyContact!();
                          if (!mounted || contact == null) return;
                          final opposite =
                              destination == 'Para' ? 'Cc' : 'Para';
                          if (widget.contacts.any((c) =>
                              c.destination == opposite &&
                              c.email.trim().toLowerCase() ==
                                  contact.email.trim().toLowerCase())) {
                            setState(() => _errors[destination] =
                                'Este contato já está em $opposite.');
                            return;
                          }
                          setState(() {
                            _errors.remove(destination);
                            _selectCompany(contact, destination);
                          });
                        } catch (e) {
                          if (mounted) {
                            setState(() => _errors[destination] = e.toString());
                          }
                        }
                      }),
                PopupMenuButton<String>(
                    tooltip: 'Adicionar em $destination',
                    icon: const Icon(Icons.add),
                    itemBuilder: (_) => [
                          if (widget.contacts.any(_available)) ...[
                            const PopupMenuItem(
                                value: '__all__',
                                child: Row(children: [
                                  Icon(Icons.group_add_outlined),
                                  SizedBox(width: 8),
                                  Text('Adicionar todos')
                                ])),
                            const PopupMenuDivider(),
                          ],
                          if (!widget.contacts.any(_available) &&
                              !widget.companyContacts.any(_available))
                            const PopupMenuItem(
                                enabled: false,
                                child: Text(
                                    'Nenhum contato disponível. Importe a planilha ou remova um destinatário para adicioná-lo novamente.')),
                          for (final c in widget.contacts.where(_available))
                            PopupMenuItem(
                                value: c.email.trim(),
                                child: Text(c.name.isEmpty
                                    ? c.email
                                    : '${c.name} — ${c.email}')),
                          if (widget.companyContacts.any(_available)) ...[
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                                enabled: false,
                                child: Text('Colaboradores cadastrados')),
                            for (final c
                                in widget.companyContacts.where(_available))
                              PopupMenuItem(
                                  value: 'company:${c.email.trim()}',
                                  child: Text('${c.name} — ${c.email}')),
                          ]
                        ],
                    onSelected: (email) {
                      if (email.startsWith('company:')) {
                        final address = email.substring('company:'.length);
                        final contact = widget.companyContacts
                            .where((c) => c.email.trim() == address);
                        if (contact.isNotEmpty && _available(contact.first)) {
                          _selectCompany(contact.first, destination);
                        }
                      } else if (email == '__all__') {
                        final emails = widget.contacts
                            .where(_available)
                            .map((c) => c.email.trim().toLowerCase())
                            .toSet();
                        for (final address in emails) {
                          _select(address, destination);
                        }
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
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
