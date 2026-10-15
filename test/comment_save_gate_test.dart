import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_save_gate.dart';

void main() {
  test('manual save before sending stores a draft without claiming publication',
      () async {
    final gate = CommentSaveGate();
    var drafts = 0, publications = 0;
    await gate.saveManually(
        content: 'text and image',
        saveDraft: () async {
          drafts++;
        },
        savePublication: () async {
          publications++;
        });
    expect(drafts, 1);
    expect(publications, 0);
    expect(gate.alreadySent('text and image'), false);
    expect(gate.hasPendingSave, false);
  });
  test('manual save retries a pending publication instead of making a draft',
      () async {
    final gate = CommentSaveGate();
    gate.receiveResult(content: 'published', sending: true, confirmed: true);
    var drafts = 0, publications = 0;
    await gate.saveManually(
        content: 'edited afterwards',
        saveDraft: () async {
          drafts++;
        },
        savePublication: () async {
          publications++;
          await gate.persistPending(() async {});
        });
    expect(drafts, 0);
    expect(publications, 1);
    expect(gate.hasPendingSave, false);
  });
  test(
      'manual save keeps a published document and drafts only subsequent edits',
      () async {
    final gate = CommentSaveGate();
    gate.receiveResult(content: 'published', sending: true, confirmed: true);
    await gate.persistPending(() async {});
    var drafts = 0;
    Future<void> save(String content) => gate.saveManually(
        content: content,
        saveDraft: () async {
          drafts++;
        },
        savePublication: () async {
          fail('Already persisted');
        });
    await save('published');
    expect(drafts, 0);
    await save('new edit');
    expect(drafts, 1);
    expect(gate.alreadySent('published'), true);
    expect(gate.alreadySent('new edit'), false);
  });
  test('testing, cancellation and failure never enable project saving', () {
    final gate = CommentSaveGate();
    expect(gate.canSave('text'), false);
    gate.receiveResult(content: 'text', sending: false, confirmed: true);
    expect(gate.canSave('text'), false);
    gate.receiveResult(content: 'text', sending: true, confirmed: false);
    expect(gate.canSave('text'), false);
  });
  test(
      'confirmed content remains available for explicit save without resending',
      () {
    final gate = CommentSaveGate();
    gate.receiveResult(
        content: 'text and image', sending: true, confirmed: true);
    expect(gate.canSave('text and image'), true);
    expect(gate.alreadySent('text and image'), true);
    expect(gate.canSave('changed text'), false);
    gate.markSaved();
    expect(gate.canSave('text and image'), false);
    expect(gate.alreadySent('text and image'), true);
  });
  test('a new confirmed document can be saved after the previous one', () {
    final gate = CommentSaveGate();
    gate.receiveResult(content: 'first', sending: true, confirmed: true);
    gate.markSaved();
    gate.receiveResult(content: 'second', sending: true, confirmed: true);
    expect(gate.canSave('second'), true);
    expect(gate.canSave('first'), false);
  });
  test('only a confirmed publication triggers project persistence', () async {
    final gate = CommentSaveGate();
    var writes = 0;
    Future<void> persist() async {
      writes++;
    }

    expect(await gate.persistPending(persist), false);
    gate.receiveResult(content: 'text', sending: false, confirmed: true);
    expect(await gate.persistPending(persist), false);
    gate.receiveResult(content: 'text', sending: true, confirmed: false);
    expect(await gate.persistPending(persist), false);
    expect(writes, 0);
    gate.receiveResult(content: 'text', sending: true, confirmed: true);
    expect(await gate.persistPending(persist), true);
    expect(writes, 1);
    expect(gate.hasPendingSave, false);
    expect(gate.alreadySent('text'), true);
    expect(await gate.persistPending(persist), false);
    expect(writes, 1);
  });
  test(
      'failed project persistence retries without losing publication confirmation',
      () async {
    final gate = CommentSaveGate();
    gate.receiveResult(
        content: 'published snapshot', sending: true, confirmed: true);
    await expectLater(gate.persistPending(() async {
      throw StateError('offline');
    }), throwsStateError);
    expect(gate.hasPendingSave, true);
    expect(gate.alreadySent('published snapshot'), true);
    expect(await gate.persistPending(() async {}), true);
    expect(gate.hasPendingSave, false);
  });
  test('concurrent project save requests wait for the same acknowledgement',
      () async {
    final gate = CommentSaveGate();
    gate.receiveResult(content: 'published', sending: true, confirmed: true);
    final acknowledgement = Completer<void>();
    var writes = 0;
    Future<void> persist() {
      writes++;
      return acknowledgement.future;
    }

    final first = gate.persistPending(persist);
    final second = gate.persistPending(persist);
    expect(identical(first, second), true);
    expect(gate.hasPendingSave, true);
    expect(writes, 1);
    acknowledgement.complete();
    expect(await first, true);
    expect(await second, true);
    expect(gate.hasPendingSave, false);
  });
}
