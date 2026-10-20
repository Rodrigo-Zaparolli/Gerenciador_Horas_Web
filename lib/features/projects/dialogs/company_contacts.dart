import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/config/pilot_feature_access.dart';

class CompanyContact {
  final String id, name, email;
  const CompanyContact(this.id, this.name, this.email);
}

class CompanyContacts {
  static String owner() {
    final user = FirebaseAuth.instance.currentUser;
    if (!PilotFeatureAccess.allows(uid: user?.uid, email: user?.email)) {
      throw StateError('Cadastro disponível apenas para a conta autorizada.');
    }
    return user!.uid;
  }

  static Future<List<CompanyContact>> load() async {
    final uid = owner();
    final result = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('company_contacts')
        .orderBy('name')
        .get()
        .timeout(const Duration(seconds: 15));
    if (owner() != uid) throw StateError('A conta mudou.');
    return result.docs
        .map((d) => CompanyContact(
            d.id, d.data()['name'] as String, d.data()['email'] as String))
        .toList();
  }

  static Future<void> put(String name, String email, {String? id}) async {
    final uid = owner();
    final address = email.trim().toLowerCase();
    if (name.trim().isEmpty ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
      throw ArgumentError('Preencha o nome e um e-mail válido.');
    }
    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('company_contacts');
    final duplicates = await collection
        .where('email', isEqualTo: address)
        .get()
        .timeout(const Duration(seconds: 15));
    if (duplicates.docs
        .any((doc) => doc.id != (id ?? Uri.encodeComponent(address)))) {
      throw StateError(
          'Este e-mail já está cadastrado para outro colaborador.');
    }
    if (owner() != uid) throw StateError('A conta mudou.');
    // A stable e-mail key also prevents accidental duplicate registrations.
    await collection
        .doc(id ?? Uri.encodeComponent(address))
        .set({'name': name.trim(), 'email': address}).timeout(
            const Duration(seconds: 15));
    if (owner() != uid) throw StateError('A conta mudou.');
  }

  static Future<void> remove(String id) async {
    final uid = owner();
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('company_contacts')
        .doc(id)
        .delete()
        .timeout(const Duration(seconds: 15));
  }

  static Future<void> show(BuildContext context) => showDialog<void>(
      context: context, builder: (_) => const _ContactsDialog());

  static Future<CompanyContact?> pick(BuildContext context) async {
    final contacts = await load();
    if (!context.mounted) return null;
    var search = '';
    return showDialog<CompanyContact>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                    title: const Text('Selecionar colaborador'),
                    content: SizedBox(
                        width: 500,
                        height: 400,
                        child: Column(children: [
                          TextField(
                              autofocus: true,
                              decoration: const InputDecoration(
                                  labelText: 'Buscar nome ou e-mail'),
                              onChanged: (v) =>
                                  setState(() => search = v.toLowerCase())),
                          Expanded(
                              child: ListView(children: [
                            for (final c in contacts.where((c) =>
                                '${c.name} ${c.email}'
                                    .toLowerCase()
                                    .contains(search)))
                              ListTile(
                                  title: Text(c.name),
                                  subtitle: Text(c.email),
                                  onTap: () => Navigator.pop(context, c)),
                            if (contacts.isEmpty)
                              const ListTile(
                                  title: Text(
                                      'Cadastre os colaboradores primeiro.'))
                          ]))
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'))
                    ])));
  }
}

class _ContactsDialog extends StatefulWidget {
  const _ContactsDialog();
  @override
  State<_ContactsDialog> createState() => _ContactsDialogState();
}

class _ContactsDialogState extends State<_ContactsDialog> {
  StreamSubscription<User?>? subscription;
  String? uid;
  final name = TextEditingController(), email = TextEditingController();
  List<CompanyContact> contacts = [];
  String? editing, error;
  String search = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser?.uid;
    subscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted &&
          (user?.uid != uid ||
              !PilotFeatureAccess.allows(uid: user?.uid, email: user?.email))) {
        setState(() {
          contacts = [];
          name.clear();
          email.clear();
        });
        Navigator.pop(context);
      }
    });
    refresh();
  }

  Future<void> refresh() async {
    setState(() => busy = true);
    try {
      final result = await CompanyContacts.load();
      if (mounted) setState(() => contacts = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await CompanyContacts.put(name.text, email.text, id: editing);
      if (!mounted) return;
      name.clear();
      email.clear();
      editing = null;
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(CompanyContact c) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Excluir colaborador?'),
                content: Text(c.name),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Excluir'))
                ]));
    if (ok != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await CompanyContacts.remove(c.id);
      if (mounted) await refresh();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    name.dispose();
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Colaboradores da companhia'),
          content: SizedBox(
              width: 640,
              height: 480,
              child: Column(children: [
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                TextField(
                    controller: name,
                    enabled: !busy,
                    decoration: const InputDecoration(labelText: 'Nome')),
                TextField(
                    controller: email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail')),
                Wrap(spacing: 8, children: [
                  FilledButton.icon(
                      onPressed: busy ? null : save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                          editing == null ? 'Adicionar' : 'Salvar alterações')),
                  if (editing != null)
                    TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                  editing = null;
                                  name.clear();
                                  email.clear();
                                }),
                        child: const Text('Cancelar edição'))
                ]),
                TextField(
                    decoration: const InputDecoration(
                        labelText: 'Buscar colaborador',
                        prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() => search = v.toLowerCase())),
                Expanded(
                    child: ListView(children: [
                  for (final c in contacts.where((c) =>
                      '${c.name} ${c.email}'.toLowerCase().contains(search)))
                    ListTile(
                        title: Text(c.name),
                        subtitle: Text(c.email),
                        onTap: busy
                            ? null
                            : () => setState(() {
                                  editing = c.id;
                                  name.text = c.name;
                                  email.text = c.email;
                                }),
                        trailing: IconButton(
                            tooltip: 'Excluir colaborador',
                            onPressed: busy ? null : () => remove(c),
                            icon: const Icon(Icons.delete_outline))),
                  if (!busy && contacts.isEmpty)
                    const ListTile(
                        title: Text('Nenhum colaborador cadastrado.'))
                ]))
              ])),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Fechar'))
          ]);
}
