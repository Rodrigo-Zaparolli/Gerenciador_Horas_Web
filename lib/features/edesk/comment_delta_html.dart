import 'dart:convert';

const commentDefaultFontSize = 16.0;
const _escape = HtmlEscape(HtmlEscapeMode.attribute);
String _html(String value) => _escape.convert(value);

String _font(dynamic value) {
  final name = (value?.toString() ?? 'Roboto')
      .replaceAll('"', '')
      .replaceAll("'", '')
      .trim();
  if (!RegExp(r'^[a-zA-Z0-9 _-]{1,80}$').hasMatch(name)) {
    return "'Roboto',Arial,sans-serif";
  }
  final fallback = switch (name) {
    'Times New Roman' => 'Times,serif',
    'Noto Serif' => 'Georgia,serif',
    'Roboto Mono' => "'Courier New',monospace",
    _ => 'Arial,sans-serif',
  };
  return "'$name',$fallback";
}

String _size(dynamic value) {
  final raw = value?.toString() ?? '';
  final parsed = double.tryParse(raw.replaceFirst(RegExp(r'px$'), ''));
  if (parsed != null && parsed.isFinite && parsed >= 1 && parsed <= 200) {
    return '${parsed}px';
  }
  return switch (raw) {
    'small' => '10px',
    'large' => '18px',
    'huge' => '24px',
    _ => '${commentDefaultFontSize}px'
  };
}

String? _color(dynamic value, {bool text = false}) {
  var raw = value?.toString().replaceFirst('#', '') ?? '';
  if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(raw)) raw = raw.substring(2);
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(raw)) return null;
  // The editor's default light ink must remain readable on the E-Desk white page.
  if (text && raw.toLowerCase() == 'f8fafc') return '#111827';
  return '#$raw';
}

String _inline(String text, Map<String, dynamic> attributes) {
  final decorations = [
    if (attributes['underline'] == true) 'underline',
    if (attributes['strike'] == true) 'line-through'
  ];
  final style =
      'font-family:${_font(attributes['font'])};font-size:${_size(attributes['size'])};'
      'font-weight:${attributes['bold'] == true ? 'bold' : 'normal'};'
      'font-style:${attributes['italic'] == true ? 'italic' : 'normal'};'
      'text-decoration:${decorations.isEmpty ? 'none' : decorations.join(' ')};'
      'color:${_color(attributes['color'], text: true) ?? '#111827'};'
      '${_color(attributes['background']) == null ? '' : 'background-color:${_color(attributes['background'])};'}';
  var content =
      '<span style="${_html(style)}">${_html(text).replaceAll('\t', '&nbsp;&nbsp;&nbsp;&nbsp;')}</span>';
  final link = Uri.tryParse(attributes['link']?.toString() ?? '');
  if (link != null && const {'https', 'http', 'mailto'}.contains(link.scheme)) {
    content = '<a href="${_html(link.toString())}">$content</a>';
  }
  return content;
}

String _image(Map insert, Map<String, dynamic> attributes) {
  final source = insert['image']?.toString() ?? '';
  if (!RegExp(r'^data:image/(png|jpe?g|gif|webp);base64,', caseSensitive: false)
          .hasMatch(source) &&
      Uri.tryParse(source)?.scheme != 'https') {
    throw const FormatException(
        'Imagem sem origem reconhecida. Reinsira a imagem antes de enviar.');
  }
  final dimensions =
      RegExp(r'(?:^|;)\s*(width|height)\s*:\s*(\d+(?:\.\d+)?)(px|%)\s*(?=;|$)')
          .allMatches(attributes['style']?.toString() ?? '')
          .map((m) => '${m[1]}:${m[2]}${m[3]};')
          .join();
  return '<img src="${_html(source)}" alt="" style="max-width:100%;height:auto;vertical-align:middle;$dimensions">';
}

/// Export the exact frozen Quill document, including attributes stored on newlines.
/// The result needs no Quill stylesheet in the destination editor.
String commentHtmlFromDelta(List<dynamic> delta) {
  final lines = <({String content, Map<String, dynamic> attributes})>[];
  var current = StringBuffer();
  for (final raw in delta) {
    final operation = Map<String, dynamic>.from(raw as Map);
    final attributes =
        Map<String, dynamic>.from(operation['attributes'] as Map? ?? {});
    final insert = operation['insert'];
    if (insert is String) {
      final parts = insert.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) current.write(_inline(parts[i], attributes));
        if (i < parts.length - 1) {
          lines.add((content: current.toString(), attributes: attributes));
          current = StringBuffer();
        }
      }
    } else if (insert is Map && insert.containsKey('image')) {
      current.write(_image(insert, attributes));
    } else if (insert != null) {
      throw const FormatException(
          'O comentario possui um elemento nao reconhecido. Confira antes de enviar.');
    }
  }
  if (current.isNotEmpty) {
    lines.add((content: current.toString(), attributes: {}));
  }
  final html = StringBuffer(
      '[[EDESK_HTML]]<div style="font-family:Roboto,Arial,sans-serif;font-size:16px;line-height:1.42;color:#111827;white-space:pre-wrap;overflow-wrap:break-word;">');
  final lists = <String>[];
  void closeLists() {
    while (lists.isNotEmpty) {
      html.write('</li></${lists.removeLast()}>');
    }
  }

  for (final line in lines) {
    final a = line.attributes;
    final list = a['list'];
    final indent = (int.tryParse('${a['indent'] ?? 0}') ?? 0).clamp(0, 8);
    final align =
        const {'left', 'center', 'right', 'justify'}.contains(a['align'])
            ? a['align']
            : 'left';
    final direction = a['direction'] == 'rtl' ? 'rtl' : 'ltr';
    final style =
        'margin:0;font-size:16px;font-family:Roboto,Arial,sans-serif;line-height:1.42;text-align:$align;direction:$direction;white-space:pre-wrap;';
    final content = line.content.isEmpty ? '<br>' : line.content;
    if (const {'bullet', 'ordered', 'checked', 'unchecked'}.contains(list)) {
      final tag = list == 'ordered' ? 'ol' : 'ul';
      final depth = indent + 1;
      while (lists.length > depth) {
        html.write('</li></${lists.removeLast()}>');
      }
      if (lists.length == depth && lists.last != tag) {
        html.write('</li></${lists.removeLast()}>');
      }
      if (lists.length == depth) html.write('</li>');
      while (lists.length < depth) {
        final type = list == 'ordered'
            ? (lists.length % 3 == 0
                ? 'decimal'
                : lists.length % 3 == 1
                    ? 'lower-alpha'
                    : 'lower-roman')
            : 'disc';
        html.write(
            '<$tag style="margin:0;padding-left:1.5em;list-style-type:$type;">');
        lists.add(tag);
        if (lists.length < depth) {
          html.write('<li style="list-style-type:none;">');
        }
      }
      html.write(
          '<li style="${_html('${style}padding-left:1.5em;')}">${list == 'checked' ? '&#9745; ' : list == 'unchecked' ? '&#9744; ' : ''}$content');
    } else {
      closeLists();
      final header = int.tryParse('${a['header']}');
      final tag = header != null && header >= 1 && header <= 6
          ? 'h$header'
          : a['blockquote'] == true
              ? 'blockquote'
              : 'p';
      html.write(
          '<$tag style="${_html('$style${indent > 0 ? 'padding-left:${indent * 3}em;' : ''}')}">$content</$tag>');
    }
  }
  closeLists();
  html.write('</div>');
  return html.toString();
}
