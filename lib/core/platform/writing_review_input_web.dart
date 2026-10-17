import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Widget writingReviewInput(
        {required String text,
        required ValueChanged<String> onChanged,
        required Color foreground,
        required Color background}) =>
    HtmlElementView.fromTagName(
      tagName: 'textarea',
      onElementCreated: (element) {
        final input = element as web.HTMLTextAreaElement;
        input.value = text;
        input.lang = 'pt-BR';
        input.spellcheck = true;
        input.setAttribute('autocorrect', 'on');
        input.setAttribute('autocapitalize', 'sentences');
        input.setAttribute('aria-label', 'Texto para revisar em português');
        input.style.cssText =
            'box-sizing:border-box;width:100%;height:100%;resize:none;'
            'padding:14px;border:1px solid #8193a5;border-radius:8px;'
            'font:16px/1.5 system-ui,sans-serif;'
            'color:#${foreground.toARGB32().toRadixString(16).substring(2)};'
            'background:#${background.toARGB32().toRadixString(16).substring(2)};';
        input.addEventListener(
            'input', ((web.Event _) => onChanged(input.value)).toJS);
      },
    );
