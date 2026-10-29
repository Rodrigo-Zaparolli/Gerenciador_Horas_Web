import 'dart:convert';
import 'dart:io';
import '../../lib/features/edesk/comment_delta_html.dart';

void main() {
  final fixtures = <String, List<dynamic>>{
    'default': [
      {
        'insert':
            'Qual o progresso deste projeto?\nEtapa atual do projeto: Implantacao\nAgenda 09/11/2026:\nSanar duvidas e verificar testes\n'
      }
    ],
    'times': [
      {
        'insert': 'Agenda 09/11/2026:',
        'attributes': {'font': 'Times New Roman', 'size': '18', 'bold': true}
      },
      {'insert': '\n'},
      {
        'insert': 'Sanar duvidas e verificar testes',
        'attributes': {'font': 'Times New Roman', 'size': '16', 'italic': true}
      },
      {'insert': '\n'}
    ],
    'structure': [
      {
        'insert': 'Centralizado',
        'attributes': {'font': 'Arial'}
      },
      {
        'insert': '\n',
        'attributes': {'align': 'center'}
      },
      {
        'insert': 'Recuado',
        'attributes': {'font': 'Arial'}
      },
      {
        'insert': '\n',
        'attributes': {'indent': 1}
      },
      {
        'insert': 'Primeiro',
        'attributes': {'font': 'Arial'}
      },
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'}
      },
      {
        'insert': 'Filho',
        'attributes': {'font': 'Arial'}
      },
      {
        'insert': '\n',
        'attributes': {'list': 'bullet', 'indent': 1}
      },
      {
        'insert': 'Segundo',
        'attributes': {'font': 'Arial'}
      },
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'}
      }
    ],
  };
  File('build/comment-render-fixtures.json').writeAsStringSync(jsonEncode({
    for (final entry in fixtures.entries)
      entry.key: {
        'delta': entry.value,
        'html':
            commentHtmlFromDelta(entry.value).substring('[[EDESK_HTML]]'.length)
      }
  }));
}
