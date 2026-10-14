import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'products_image_field_test.dart' show png;

void main() {
  test('original banner is included inline for every model, alongside proposal', () {
    final banner = File('assets/images/email_signature_cyncly.jpg').readAsBytesSync();
    expect(banner.take(2), [255, 216]);
    for (final kind in ProjectEmailKind.values) {
      final eml = utf8.decode(buildEmailDraft(subject: kind.label,
          body: defaultEmailBody(kind),
          contacts: [EmailContact(email: 'test@example.com', destination: 'Para')],
          signatureImage: banner,
          signatureName: 'Rodrigo Zaparolli',
          signatureEmail: 'rodrigo.zaparolli@cyncly.com',
          signaturePhone: '5430225800',
          signatureIcons: {
            for (final key in ['mail', 'phone', 'web'])
              key: File('assets/images/email_signature_$key.png').readAsBytesSync(),
          },
          productsImage: kind == ProjectEmailKind.internal ? png : null));
      expect(eml, contains('Content-Type: multipart/related'));
      expect(eml, contains('Content-Type: image/jpeg'));
      expect(eml, contains('Content-Disposition: inline; filename="assinatura-cyncly.jpg"'));
      expect(eml, contains(base64Encode(banner).substring(0, 76)));
      final htmlPart = RegExp(r'Content-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n([A-Za-z0-9+/=\r\n]+)').firstMatch(eml)!;
      final html = utf8.decode(base64Decode(htmlPart.group(1)!.replaceAll(RegExp(r'\s'), '')));
      expect(html, contains('_signature@gerenciador-horas'));
      expect(html, contains('<strong>Rodrigo Zaparolli</strong>'));
      expect(html, contains('mailto:rodrigo.zaparolli@cyncly.com'));
      expect(html, contains('5430225800'));
      for (final key in ['mail', 'phone', 'web']) {
        expect(html, contains('_$key@gerenciador-horas'));
      }
      expect(html.substring(html.lastIndexOf('Att,')), isNot(contains('{consultor}')));
      expect(html.indexOf('alt="Cyncly'), greaterThan(html.indexOf('promob.com')));
      if (kind == ProjectEmailKind.internal) {
        expect(eml, contains('Content-Type: image/png'));
        expect(html, contains('_products@gerenciador-horas'));
      }
    }
  });
}
