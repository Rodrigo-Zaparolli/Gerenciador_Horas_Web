import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../../../data/services/recoverable_draft.dart';

/// Recovery is independent of comment saving, sending and the deadline rules.
class CommentDraftRecovery {
  CommentDraftRecovery(
      {required this.uid,
      required this.projectId,
      required this.editor,
      required this.percentage,
      required this.isCurrentAccount,
      required this.metadata,
      required this.restoreMetadata}) {
    final saved = RecoverableDraft.read(uid, key);
    if (saved != null) {
      try {
        editor.document = quill.Document.fromJson(saved['delta'] as List);
        percentage.text = saved['percent'] as String? ?? '';
        restoreMetadata(saved);
        previous = jsonEncode(snapshot);
        status.value =
            'Rascunho recuperado. Revise o texto e reinsira as imagens antes de enviar.';
      } catch (_) {
        RecoverableDraft.clear(uid, key);
      }
    }
    editor.addListener(persist);
    percentage.addListener(persist);
  }
  final String? uid;
  final String projectId;
  final quill.QuillController editor;
  final TextEditingController percentage;
  final bool Function() isCurrentAccount;
  final Map<String, dynamic> Function() metadata;
  final void Function(Map<String, dynamic>) restoreMetadata;
  final status = ValueNotifier<String>('');
  String previous = '';
  String get key => 'comment.$projectId';
  Map<String, dynamic> get snapshot => {
        'delta': RecoverableDraft.textDelta(editor.document.toDelta().toJson()),
        'percent': percentage.text,
        ...metadata()
      };
  void persist() {
    if (!isCurrentAccount()) return;
    if (editor.document.toPlainText().replaceAll('\uFFFC', '').trim().isEmpty &&
        percentage.text.isEmpty) {
      RecoverableDraft.clear(uid, key);
      status.value = '';
      previous = '';
      return;
    }
    final data = snapshot;
    final encoded = jsonEncode(data);
    if (encoded == previous) return;
    if (RecoverableDraft.save(uid, key, data)) {
      previous = encoded;
      status.value =
          'Texto e percentual salvos para recuperação neste dispositivo. Imagens devem ser inseridas novamente.';
    } else {
      status.value = 'Não foi possível salvar a recuperação local. Use Salvar.';
    }
  }

  void dispose() {
    persist();
    editor.removeListener(persist);
    percentage.removeListener(persist);
    status.dispose();
  }
}
