import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Let the browser produce its trusted paste event rather than reading its API.
class BrowserCommentPasteAction extends Action<Intent> {
  @override
  bool consumesKey(Intent intent) => false;
  @override
  Object? invoke(Intent intent) => null;
}

/// Apply inside Quill's own shortcut/action layer so its paste action cannot
/// consume the key or attempt a permission-dependent clipboard read.
const browserCommentPasteShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.keyV, control: true):
      PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyV, meta: true):
      PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.insert, shift: true):
      PasteTextIntent(SelectionChangedCause.keyboard),
};
Map<Type, Action<Intent>> browserCommentPasteActions() => {
      PasteTextIntent: BrowserCommentPasteAction(),
    };
