import 'dart:convert';

class CommentDocumentSnapshot {
  CommentDocumentSnapshot(List<dynamic> currentDelta)
      : delta = jsonDecode(jsonEncode(currentDelta)) as List<dynamic>;
  final List<dynamic> delta;
}

String commentHtmlFromBlocks(List<Map<String, String>> currentBlocks,
    String Function(Map<String, String>) renderText) {
  final buffer = StringBuffer('[[EDESK_HTML]]');
  for (final block in currentBlocks) {
    if (block['tipo'] == 'texto') {
      buffer.write(renderText(block));
    } else if (block['tipo'] == 'imagem') {
      final value = (block['valor'] ?? '').trim();
      if (value.isEmpty) continue;
      final src = value.startsWith('data:') ? value : 'data:image/png;base64,$value';
      final dimensions = RegExp(r'(?:^|;)\s*(width|height)\s*:\s*(\d+(?:\.\d+)?)(px|%)\s*(?=;|$)')
          .allMatches(block['estiloImagem'] ?? '').map((match) => '${match[1]}:${match[2]}${match[3]};').join();
      buffer.write('<img src="${const HtmlEscape(HtmlEscapeMode.attribute).convert(src)}" '
        'alt="" style="max-width:100%;height:auto;vertical-align:middle;$dimensions">');
    }
  }
  return buffer.toString();
}
