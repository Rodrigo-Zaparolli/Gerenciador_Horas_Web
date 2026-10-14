import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_draft_recovery.dart';

void main() {
  setUp(() => LocalUserState.memory = {});
  tearDown(() => LocalUserState.memory = null);
  test('comment recovery preserves formatting, percentage and saved comment ID', () {
    var metadata = <String, dynamic>{'type': 'Interno', 'commentId': 'saved-id'};
    var editor = quill.QuillController.basic();
    var percentage = TextEditingController();
    CommentDraftRecovery create() => CommentDraftRecovery(uid: 'owner', projectId: '123',
        editor: editor, percentage: percentage, isCurrentAccount: () => true,
        metadata: () => metadata, restoreMetadata: (data) => metadata = {'type': data['type'], 'commentId': data['commentId']});
    var recovery = create();
    editor.replaceText(0, 0, 'Texto original', const TextSelection.collapsed(offset: 14));
    editor.formatText(0, 5, quill.Attribute.bold);
    percentage.text = '25,5';
    recovery.dispose(); editor.dispose(); percentage.dispose();
    editor = quill.QuillController.basic(); percentage = TextEditingController(); metadata = {};
    recovery = create();
    expect(editor.document.toPlainText().trim(), 'Texto original');
    expect(editor.document.toDelta().toJson().first['attributes'], {'bold': true});
    expect(percentage.text, '25,5');
    expect(metadata['commentId'], 'saved-id');
    expect(recovery.status.value, contains('recuperado'));
    recovery.dispose(); editor.dispose(); percentage.dispose();
  });
  test('clearing removes recovery and typing identical text creates a fresh copy', () {
    final editor = quill.QuillController.basic(), percentage = TextEditingController();
    final recovery = CommentDraftRecovery(uid: 'owner', projectId: '123',
      editor: editor, percentage: percentage, isCurrentAccount: () => true,
      metadata: () => {}, restoreMetadata: (_) {});
    editor.replaceText(0, 0, 'Mesmo texto', const TextSelection.collapsed(offset: 11));
    editor.replaceText(0, 11, '', const TextSelection.collapsed(offset: 0));
    expect(recovery.status.value, isEmpty);
    editor.replaceText(0, 0, 'Mesmo texto', const TextSelection.collapsed(offset: 11));
    expect(recovery.status.value, contains('salvos'));
    recovery.dispose(); editor.dispose(); percentage.dispose();
    final restoredEditor = quill.QuillController.basic(), restoredPercent = TextEditingController();
    final restored = CommentDraftRecovery(uid: 'owner', projectId: '123',
      editor: restoredEditor, percentage: restoredPercent, isCurrentAccount: () => true,
      metadata: () => {}, restoreMetadata: (_) {});
    expect(restoredEditor.document.toPlainText().trim(), 'Mesmo texto');
    restored.dispose(); restoredEditor.dispose(); restoredPercent.dispose();
  });
  test('switching account stops updates to previous recovery', () {
    var current = true;
    final editor = quill.QuillController.basic(), percentage = TextEditingController();
    final recovery = CommentDraftRecovery(uid: 'owner', projectId: '123',
      editor: editor, percentage: percentage, isCurrentAccount: () => current,
      metadata: () => {}, restoreMetadata: (_) {});
    editor.replaceText(0, 0, 'Texto seguro', const TextSelection.collapsed(offset: 12)); current = false;
    percentage.text = '90';
    expect(LocalUserState.read('owner', 'draft.comment.123')!['percent'], '');
    recovery.dispose(); editor.dispose(); percentage.dispose();
  });
}
