import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/config/pilot_feature_access.dart';

class ClientContact {
  const ClientContact(
      {required this.id,
      required this.company,
      required this.name,
      this.phone = '',
      this.email = ''});
  final String id, company, name, phone, email;
  String get commentText =>
      'Contato: $name${phone.isEmpty ? '' : ' · $phone'}${email.isEmpty ? '' : ' · $email'}';
  Map<String, String> get fields => {
        'company': company.trim(),
        'name': name.trim(),
        'phone': phone.trim(),
        'email': email.trim()
      };
  String? validate() {
    if (company.trim().isEmpty || name.trim().isEmpty) {
      return 'Preencha o cliente e o nome do contato.';
    }
    if ([company, name, phone, email]
        .any((s) => s.length > 300 || RegExp(r'[\r\n]').hasMatch(s))) {
      return 'Use até 300 caracteres por campo, sem quebras de linha.';
    }
    if (phone.trim().isEmpty && email.trim().isEmpty) {
      return 'Informe um telefone ou e-mail.';
    }
    if (email.trim().isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())) {
      return 'Informe um e-mail válido.';
    }
    return null;
  }
}

abstract class ClientContactStore {
  bool get authorized;
  Future<List<ClientContact>> load();
  Future<void> save(ClientContact contact);
  Future<void> remove(String id);
}

class FirebaseClientContactStore implements ClientContactStore {
  FirebaseClientContactStore() : owner = FirebaseAuth.instance.currentUser?.uid;
  final String? owner;
  @override
  bool get authorized {
    final user = FirebaseAuth.instance.currentUser;
    return owner != null &&
        user?.uid == owner &&
        PilotFeatureAccess.allows(uid: user?.uid, email: user?.email);
  }

  void check() {
    if (!authorized) {
      throw StateError('A conta mudou ou não tem acesso a este cadastro.');
    }
  }

  CollectionReference<Map<String, dynamic>> get collection =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(owner)
          .collection('client_contacts');
  @override
  Future<List<ClientContact>> load() async {
    check();
    final result = await collection.get().timeout(const Duration(seconds: 15));
    check();
    return result.docs.map((d) {
      final v = d.data();
      return ClientContact(
          id: d.id,
          company: v['company']?.toString() ?? '',
          name: v['name']?.toString() ?? '',
          phone: v['phone']?.toString() ?? '',
          email: v['email']?.toString() ?? '');
    }).toList();
  }

  @override
  Future<void> save(ClientContact contact) async {
    check();
    final error = contact.validate();
    if (error != null) throw ArgumentError(error);
    await (contact.id.isEmpty ? collection.doc() : collection.doc(contact.id))
        .set(contact.fields)
        .timeout(const Duration(seconds: 15));
    check();
  }

  @override
  Future<void> remove(String id) async {
    check();
    await collection.doc(id).delete().timeout(const Duration(seconds: 15));
    check();
  }
}

class ClientContactsDialog extends StatefulWidget {
  const ClientContactsDialog(
      {super.key, required this.store, required this.company});
  final ClientContactStore store;
  final String company;
  static Future<ClientContact?> pick(BuildContext context, String company) =>
      showDialog<ClientContact>(
          context: context,
          builder: (_) => ClientContactsDialog(
              store: FirebaseClientContactStore(), company: company));
  @override
  State<ClientContactsDialog> createState() => _ClientContactsDialogState();
}

class _ClientContactsDialogState extends State<ClientContactsDialog> {
  List<ClientContact> contacts = [];
  String search = '', error = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final values = await widget.store.load();
      values.sort((a, b) {
        final sameA = a.company.trim().toLowerCase() ==
            widget.company.trim().toLowerCase();
        final sameB = b.company.trim().toLowerCase() ==
            widget.company.trim().toLowerCase();
        if (sameA != sameB) return sameA ? -1 : 1;
        return '${a.company} ${a.name}'
            .toLowerCase()
            .compareTo('${b.company} ${b.name}'.toLowerCase());
      });
      if (mounted && widget.store.authorized) setState(() => contacts = values);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([ClientContact? contact]) async {
    final value = await showDialog<ClientContact>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ContactForm(
            contact: contact,
            company: widget.company,
            saveContact: widget.store.save));
    if (value != null && mounted && widget.store.authorized) await refresh();
  }

  Future<void> remove(ClientContact contact) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Excluir contato?'),
                content: Text('${contact.company} · ${contact.name}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Excluir'))
                ]));
    if (confirmed != true || !mounted || !widget.store.authorized) return;
    setState(() => busy = true);
    try {
      await widget.store.remove(contact.id);
      if (mounted) await refresh();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = contacts
        .where((c) => '${c.company} ${c.name} ${c.phone} ${c.email}'
            .toLowerCase()
            .contains(search.toLowerCase()))
        .toList();
    return AlertDialog(
        title: const Text('Contatos dos clientes'),
        content: SizedBox(
            width: 650,
            height: MediaQuery.sizeOf(context).height * .6,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                      decoration: const InputDecoration(
                          labelText:
                              'Buscar cliente, contato, telefone ou e-mail',
                          prefixIcon: Icon(Icons.search)),
                      onChanged: (v) => setState(() => search = v)),
                  Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                          onPressed: busy || !widget.store.authorized
                              ? null
                              : () => edit(),
                          icon: const Icon(Icons.person_add_alt),
                          label: const Text('Cadastrar contato'))),
                  if (busy) const LinearProgressIndicator(),
                  if (error.isNotEmpty)
                    Text(error,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  Expanded(
                      child: !widget.store.authorized
                          ? const Center(
                              child: Text('A conta mudou. Feche esta janela.'))
                          : shown.isEmpty
                              ? const Center(
                                  child: Text('Nenhum contato encontrado.'))
                              : ListView(children: [
                                  for (final contact in shown)
                                    Card(
                                        child: ListTile(
                                      title: Text(contact.name),
                                      subtitle: Text('${contact.company}\n${[
                                        contact.phone,
                                        contact.email
                                      ].where((s) => s.isNotEmpty).join(' · ')}'),
                                      isThreeLine: true,
                                      onTap: busy
                                          ? null
                                          : () =>
                                              Navigator.pop(context, contact),
                                      trailing: PopupMenuButton<String>(
                                          enabled: !busy,
                                          onSelected: (value) {
                                            if (value == 'edit') {
                                              edit(contact);
                                            } else {
                                              remove(contact);
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                                PopupMenuItem(
                                                    value: 'edit',
                                                    child: Text('Editar')),
                                                PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text('Excluir'))
                                              ]),
                                    ))
                                ])),
                  const Text(
                      'Selecione um contato para inserir no comentário.'),
                ])),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Fechar'))
        ]);
  }
}

class _ContactForm extends StatefulWidget {
  const _ContactForm(
      {this.contact, required this.company, required this.saveContact});
  final Future<void> Function(ClientContact) saveContact;
  final ClientContact? contact;
  final String company;
  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  late final TextEditingController company, name, phone, email;
  String? error;
  late final String contactId;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    contactId = widget.contact?.id ??
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(0x7fffffff).toRadixString(36)}';
    company =
        TextEditingController(text: widget.contact?.company ?? widget.company);
    name = TextEditingController(text: widget.contact?.name);
    phone = TextEditingController(text: widget.contact?.phone);
    email = TextEditingController(text: widget.contact?.email);
  }

  @override
  void dispose() {
    company.dispose();
    name.dispose();
    phone.dispose();
    email.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    final value = ClientContact(
        id: contactId,
        company: company.text.trim(),
        name: name.text.trim(),
        phone: phone.text.trim(),
        email: email.text.trim());
    final message = value.validate();
    if (message != null) {
      setState(() => error = message);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.saveContact(value);
      if (mounted) Navigator.pop(context, value);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
          title: Text(
              widget.contact == null ? 'Cadastrar contato' : 'Editar contato'),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: company,
                    maxLength: 300,
                    decoration:
                        const InputDecoration(labelText: 'Cliente / empresa')),
                TextField(
                    controller: name,
                    maxLength: 300,
                    decoration:
                        const InputDecoration(labelText: 'Nome do contato')),
                TextField(
                    controller: phone,
                    maxLength: 300,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Telefone / WhatsApp')),
                TextField(
                    controller: email,
                    maxLength: 300,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail')),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: busy ? null : save,
                child: const Text('Salvar contato'))
          ]));
}
