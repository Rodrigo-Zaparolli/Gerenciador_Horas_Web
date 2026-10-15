/// Tracks confirmed publications independently from explicitly saved drafts.
class CommentSaveGate {
  String? _confirmedContent;
  bool _saved = false;
  Future<bool>? _persistence;
  bool get hasPendingSave => _confirmedContent != null && !_saved;
  bool alreadySent(String content) => _confirmedContent == content;
  bool canSave(String content) => alreadySent(content) && !_saved;
  void receiveResult(
      {required String content,
      required bool sending,
      required bool confirmed}) {
    if (!sending || !confirmed) return;
    _confirmedContent = content;
    _saved = false;
  }

  void markSaved() => _saved = true;

  Future<void> saveManually({
    required String content,
    required Future<void> Function() saveDraft,
    required Future<void> Function() savePublication,
  }) async {
    if (hasPendingSave) {
      await savePublication();
    } else if (!alreadySent(content)) {
      await saveDraft();
    }
  }

  /// Retrying a failed project save must never publish to E-Desk again.
  Future<bool> persistPending(Future<void> Function() persist) {
    if (_persistence != null) return _persistence!;
    if (!hasPendingSave) return Future.value(false);
    final content = _confirmedContent;
    final operation = Future<void>.sync(persist).then((_) {
      if (_confirmedContent == content) _saved = true;
      return true;
    });
    _persistence = operation.whenComplete(() => _persistence = null);
    return _persistence!;
  }
}
