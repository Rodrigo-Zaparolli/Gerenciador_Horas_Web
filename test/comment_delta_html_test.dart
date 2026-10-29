import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:gerenciador_horas/features/edesk/comment_delta_html.dart';

void main() {
  test(
      'default size matches native editor instead of silently shrinking to 11px',
      () {
    final result = commentHtmlFromDelta([
      {'insert': 'Agenda 09/11/2026:\nSanar duvidas e verificar testes\n'}
    ]);
    expect(result, startsWith('[[EDESK_HTML]]'));
    expect(result, contains('font-size:16.0px'));
    expect(result, isNot(contains('font-size:11')));
    expect(html.parseFragment(result.substring(14)).querySelectorAll('p'),
        hasLength(2));
  });
  test(
      'same snapshot preserves Times New Roman, sizes, mixed emphasis and safe colors',
      () {
    final result = commentHtmlFromDelta([
      {
        'insert': 'Agenda ',
        'attributes': {
          'font': 'Times New Roman',
          'size': '18',
          'bold': true,
          'italic': true
        }
      },
      {
        'insert': 'cliente',
        'attributes': {
          'size': '11',
          'underline': true,
          'strike': true,
          'color': '#f8fafc',
          'background': '#00aa55'
        }
      },
      {'insert': '\n'},
    ]);
    expect(result, contains('Times New Roman'));
    expect(result, contains('font-size:18.0px'));
    expect(result, contains('font-size:11.0px'));
    expect(result, contains('font-weight:bold'));
    expect(result, contains('font-style:italic'));
    expect(result, contains('underline line-through'));
    expect(result, contains('color:#111827'));
    expect(result, contains('background-color:#00aa55'));
  });
  test(
      'newline attributes preserve alignment, indentation, lists and blank lines',
      () {
    final result = commentHtmlFromDelta([
      {'insert': 'Dados do projeto'},
      {
        'insert': '\n',
        'attributes': {'align': 'center', 'indent': 1}
      },
      {'insert': 'Primeiro'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'}
      },
      {'insert': 'Filho'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet', 'indent': 1}
      },
      {'insert': 'Segundo'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'}
      },
      {'insert': 'Numerado'},
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'}
      },
      {'insert': '\nFim\n'},
    ]);
    final document =
        html.parseFragment(result.substring('[[EDESK_HTML]]'.length));
    expect(document.querySelector('p')!.attributes['style'],
        contains('text-align:center'));
    expect(document.querySelector('p')!.attributes['style'],
        contains('padding-left:3em'));
    expect(document.querySelectorAll('ul'), hasLength(2));
    expect(document.querySelectorAll('ol'), hasLength(1));
    expect(document.querySelectorAll('li').map((e) => e.text),
        containsAll(['PrimeiroFilho', 'Filho', 'Segundo', 'Numerado']));
    expect(document.querySelectorAll('p').where((e) => e.innerHtml == '<br>'),
        hasLength(1));
  });
  test(
      'text image text order, tabs and image dimensions survive without unsafe CSS',
      () {
    final result = commentHtmlFromDelta([
      {'insert': 'Situacao: '},
      {
        'insert': {'image': 'data:image/png;base64,YQ=='},
        'attributes': {
          'style': 'width:80px;height:14px;background:url(untrusted);'
        }
      },
      {'insert': '\n\tProximo passo\n'},
    ]);
    expect(result, contains('width:80px;height:14px'));
    expect(result, isNot(contains('untrusted')));
    expect(result, contains('&nbsp;&nbsp;&nbsp;&nbsp;Proximo'));
    expect(result.indexOf('Situacao'), lessThan(result.indexOf('<img')));
    expect(result.indexOf('<img'), lessThan(result.indexOf('Proximo')));
  });
  test('plain text is escaped and unsafe links or images never execute', () {
    final result = commentHtmlFromDelta([
      {
        'insert': '<script>bad</script>',
        'attributes': {
          'link': 'javascript:alert(1)',
          'font': 'bad;position:fixed'
        }
      },
      {'insert': '\n'}
    ]);
    expect(result, contains('&lt;script&gt;'));
    expect(result, isNot(contains('javascript:')));
    expect(result, isNot(contains('position:fixed')));
    expect(
        () => commentHtmlFromDelta([
              {
                'insert': {'image': 'javascript:bad'}
              }
            ]),
        throwsFormatException);
  });
}
