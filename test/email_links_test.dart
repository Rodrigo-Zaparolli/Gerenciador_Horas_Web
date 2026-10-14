import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';

void main() {
  test('signature domains open HTTPS sites without double-linking or changing emails', () {
    final html = emailBodyHtml('promob.com | foccoerp.com.br\nhttps://promob.com\npessoa@promob.com');
    expect(html, contains('<a href="https://promob.com">promob.com</a>'));
    expect(html, contains('<a href="https://foccoerp.com.br">foccoerp.com.br</a>'));
    expect(html, contains('<a href="https://promob.com">https://promob.com</a>'));
    expect(html, contains('pessoa@promob.com'));
    expect(RegExp('<a href=').allMatches(html).length, 3);
  });
  test('SharePoint folder label is decoded while original destination is preserved', () {
    const url = 'https://cyncly.sharepoint.com/:f:/r/sites/Client/Professional%20Produ%C3%A7%C3%A3o%20Completa%20-%20Promob%20Marcenaria%20Fernandes?d=abc&csf=1&web=1';
    final html = emailBodyHtml('Caminho do Sistema do cliente → $url');
    expect(html, contains('📁 Professional Produção Completa - Promob Marcenaria Fernandes</a>'));
    expect(html, contains('href="${url.replaceAll('&', '&amp;')}"'));
    expect(html, isNot(contains('&amp;amp;')));
  });
  test('HTML remains escaped and other links retain their display URL', () {
    final html = emailBodyHtml('<script>\nhttps://example.com/?a=1&b=2');
    expect(html, contains('&lt;script&gt;<br>'));
    expect(html, contains('<a href="https://example.com/?a=1&amp;b=2">'));
    expect(html, contains('https://example.com/?a=1&amp;b=2</a>'));
  });
}
