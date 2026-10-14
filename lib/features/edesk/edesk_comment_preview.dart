import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

class EdeskCommentPreview extends StatelessWidget {
  final String text;
  final String? legacyImage;
  const EdeskCommentPreview({super.key, required this.text, this.legacyImage});

  Widget _image(String value) {
    try {
      final encoded = value.contains(',') ? value.substring(value.indexOf(',') + 1) : value;
      if (encoded.length > 14 * 1024 * 1024) throw const FormatException();
      final bytes = base64Decode(encoded);
      return Image.memory(bytes, fit: BoxFit.contain,
          errorBuilder: (_, error, stack) => const Text('Não foi possível mostrar esta imagem na prévia.'));
    } catch (_) {
      return const Text('Não foi possível mostrar esta imagem na prévia.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var spans = <InlineSpan>[];
    var inlineImages = 0;
    var alignment = TextAlign.left;
    void flush() {
      if (spans.isEmpty) return;
      children.add(SizedBox(width: double.infinity,
          child: SelectableText.rich(TextSpan(children: spans), textAlign: alignment)));
      spans = [];
    }
    void visit(dom.Node node, TextStyle style) {
      if (node is dom.Text) {
        spans.add(TextSpan(text: node.data, style: style));
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName;
      if (['script', 'style', 'iframe', 'object'].contains(tag)) return;
      if (tag == 'img') {
        flush();
        final src = node.attributes['src'] ?? '';
        if (RegExp(r'^data:image/(png|jpeg|jpg|gif|webp);base64,', caseSensitive: false).hasMatch(src)) {
          children.add(_image(src));
          inlineImages++;
        } else {
          children.add(const Text('Imagem externa não carregada na prévia.'));
        }
        return;
      }
      if (tag == 'br') {
        spans.add(const TextSpan(text: '\n'));
        return;
      }
      final css = node.attributes['style'] ?? '';
      final declarations = <String, String>{};
      for (final declaration in css.split(';')) {
        final colon = declaration.indexOf(':');
        if (colon > 0) declarations[declaration.substring(0, colon).trim().toLowerCase()] = declaration.substring(colon + 1).trim();
      }
      final requestedAlignment = switch (declarations['text-align']) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        'justify' => TextAlign.justify,
        'left' => TextAlign.left,
        _ => alignment,
      };
      if (requestedAlignment != alignment) { flush(); alignment = requestedAlignment; }
      final decoration = declarations['text-decoration'] ?? '';
      final color = declarations['color'];
      final rgb = color != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)
          ? Color(0xFF000000 | int.parse(color.substring(1), radix: 16)) : style.color;
      var next = style.copyWith(
          color: rgb,
          fontFamily: declarations['font-family']?.replaceAll(RegExp('["\x27]'), ''),
          fontWeight: ['b', 'strong'].contains(tag) || declarations['font-weight'] == 'bold'
              ? FontWeight.bold : declarations['font-weight'] == 'normal' ? FontWeight.normal : style.fontWeight,
          fontStyle: ['i', 'em'].contains(tag) || declarations['font-style'] == 'italic' ? FontStyle.italic : declarations['font-style'] == 'normal' ? FontStyle.normal : style.fontStyle,
          decoration: decoration == 'none' ? TextDecoration.none : TextDecoration.combine([
            if (tag == 'u' || tag == 'a' || decoration.contains('underline')) TextDecoration.underline,
            if (['s', 'del'].contains(tag) || decoration.contains('line-through')) TextDecoration.lineThrough,
            if (decoration.isEmpty && style.decoration != null) style.decoration!,
          ]));
      final size = RegExp(r'font-size:\s*(\d+(?:\.\d+)?)(px|pt)').firstMatch(css);
      if (size != null) {
        final value = double.parse(size.group(1)!) * (size.group(2) == 'pt' ? 4 / 3 : 1);
        next = next.copyWith(fontSize: value.clamp(8, 36).toDouble());
      }
      for (final child in node.nodes) { visit(child, next); }
      if (['p', 'div', 'tr', 'li'].contains(tag)) spans.add(const TextSpan(text: '\n'));
      if (tag == 'td') spans.add(const TextSpan(text: '\t'));
    }
    if (text.startsWith('[[EDESK_HTML]]')) {
      final document = html.parseFragment(text.substring('[[EDESK_HTML]]'.length));
      for (final node in document.nodes) { visit(node, const TextStyle(color: Color(0xFF111827))); }
      flush();
    } else {
      children.add(SelectableText(text));
    }
    if (inlineImages == 0 && legacyImage?.isNotEmpty == true) children.add(_image(legacyImage!));
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
    if (!text.startsWith('[[EDESK_HTML]]')) return content;
    // Document colors are independent of the application's dark/light theme.
    return ColoredBox(color: Colors.white, child: Padding(
      padding: const EdgeInsets.all(12), child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFF111827), fontSize: 14), child: content)));
  }
}
