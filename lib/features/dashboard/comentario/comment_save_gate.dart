/// A project comment is persisted only by an explicit save after confirmation.
class CommentSaveGate {
  String? _confirmedContent;
  bool _saved = false;
  bool alreadySent(String content) => _confirmedContent == content;
  bool canSave(String content) => alreadySent(content) && !_saved;
  void receiveResult({required String content, required bool sending, required bool confirmed}) {
    if (!sending || !confirmed) return;
    _confirmedContent = content;
    _saved = false;
  }
  void markSaved() => _saved = true;
}
