import 'package:web/web.dart' as web;
bool pasteCommentText(String text) {
  final transfer = web.DataTransfer()..setData('text/plain', text);
  final event = web.ClipboardEvent('paste', web.ClipboardEventInit(
    clipboardData: transfer, bubbles: true, cancelable: true));
  return !web.document.dispatchEvent(event);
}
