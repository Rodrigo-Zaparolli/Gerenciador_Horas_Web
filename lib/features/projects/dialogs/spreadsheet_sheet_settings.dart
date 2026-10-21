import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/config/pilot_feature_access.dart';

abstract class SpreadsheetSheetSettingsStore {
  Future<Map<String, String>> load(
      String uid, String project, String reference);
  Future<void> save(
      String uid, String project, String reference, Map<String, String> names);
}

class FirebaseSpreadsheetSheetSettingsStore
    implements SpreadsheetSheetSettingsStore {
  void check(String uid) {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.uid != uid ||
        !PilotFeatureAccess.allows(uid: user?.uid, email: user?.email)) {
      throw StateError('A conta mudou.');
    }
  }

  DocumentReference<Map<String, dynamic>> document(
          String uid, String project) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('projects')
          .doc(project)
          .collection('spreadsheet')
          .doc('sheet-settings');
  @override
  Future<Map<String, String>> load(
      String uid, String project, String reference) async {
    check(uid);
    final data = (await document(uid, project)
            .get()
            .timeout(const Duration(seconds: 15)))
        .data();
    check(uid);
    if (data == null) return {};
    return {
      'entry': data['entry'] as String,
      'checklist': data['checklist'] as String
    };
  }

  @override
  Future<void> save(String uid, String project, String reference,
      Map<String, String> names) async {
    check(uid);
    await document(uid, project)
        .set({'reference': reference, ...names}).timeout(
            const Duration(seconds: 15));
    check(uid);
  }
}

Future<Map<String, String>?> selectSpreadsheetSheets(BuildContext context,
    List<String> available, Map<String, String> current) async {
  String? entry =
      available.contains(current['entry']) ? current['entry'] : null;
  String? checklist =
      available.contains(current['checklist']) ? current['checklist'] : null;
  return showDialog<Map<String, String>>(
    context: context,
    builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
              title: const Text('Configurar abas da planilha'),
              content: SizedBox(
                  width: 440,
                  child: SingleChildScrollView(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                          'Selecione os nomes existentes no Excel. A escolha fica salva neste projeto; o arquivo não será renomeado.'),
                      const SizedBox(height: 20),
                      for (final kind in ['entry', 'checklist']) ...[
                        DropdownButtonFormField<String>(
                          initialValue: kind == 'entry' ? entry : checklist,
                          isExpanded: true,
                          decoration: InputDecoration(
                              labelText: kind == 'entry'
                                  ? 'Aba de informações de entrada'
                                  : 'Aba de checklist'),
                          items: available
                              .map((name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (value) => update(() {
                            if (kind == 'entry') {
                              entry = value;
                            } else {
                              checklist = value;
                            }
                          }),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed:
                        entry == null || checklist == null || entry == checklist
                            ? null
                            : () => Navigator.pop(context,
                                {'entry': entry!, 'checklist': checklist!}),
                    child: const Text('Usar estas abas')),
              ],
            )),
  );
}
