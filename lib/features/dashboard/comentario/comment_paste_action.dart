import 'package:flutter/material.dart';
/// Let the browser produce its trusted paste event rather than reading its API.
class BrowserCommentPasteAction extends Action<Intent> {
  @override
  bool consumesKey(Intent intent) => false;
  @override
  Object? invoke(Intent intent) => null;
}
