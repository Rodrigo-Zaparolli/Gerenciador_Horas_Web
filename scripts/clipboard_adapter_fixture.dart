import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../lib/core/platform/comment_paste.dart';
import '../lib/core/platform/image_paste.dart';

void main() {
  final events = <Map<String, Object>>[];
  final body = web.document.body!;
  void record(Map<String, Object> event) {
    events.add(event);
    body.dataset['events'] = jsonEncode(events);
  }

  final stopComment = listenForCommentPaste(
    accepts: () => body.dataset['active'] == 'comment',
    onText: (text) => record({'kind': 'text', 'text': text}),
    onImage: (bytes) => record({'kind': 'comment-image', 'bytes': bytes.length}),
  );
  final stopImage = listenForImagePaste(
    accepts: () => body.dataset['active'] == 'image',
    onImage: (bytes) => record({'kind': 'image', 'bytes': bytes.length}),
    onError: () => record({'kind': 'error'}),
  );
  web.document.addEventListener('disposeClipboardFixture', ((web.Event _) {
    stopComment();
    stopImage();
  }).toJS);
  body.dataset['events'] = '[]';
  body.dataset['ready'] = 'true';
}
