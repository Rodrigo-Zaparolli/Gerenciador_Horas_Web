import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:gerenciador_horas/data/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_workbook.dart';

void main() {
  test(
      'full entry sheet fills all model data including system, client, prices and consultant phone',
      () {
    final parsed = parseEmailWorkbookRows([
      ['', 'Nome do sistema', 'Sistema Cliente'],
      ['', 'Nome resumido do sistema', 'Cliente'],
      ['', 'ID da Biblioteca', '4431'],
      ['', 'ID', '9456'],
      ['', 'NS para instalação', '80200790'],
      ['', 'Versão / Revisão', '2026.1'],
      ['', 'Assinatura da proposta', '02/07/2026'],
      ['', 'Senha do Configurador de Dimensões', 'config-teste'],
      ['', 'Senha dos Orçamentos', 'orc-teste'],
      ['', 'Senha das Margens', 'marg-teste'],
      ['', '', '', '', 'CLIENTE'],
      [
        '',
        '',
        '',
        '',
        'Proprietário',
        'Cliente',
        'cliente@example.com',
        '54 3333-3333',
        '111.222.333-44'
      ],
      [
        '',
        '',
        '',
        '',
        'Responsável técnico',
        'Técnico',
        'tecnico@example.com',
        '54 4444-4444',
        '222.333.444-55'
      ],
      ['', '', '', '', 'INFORMAÇÕES COMERCIAIS'],
      ['', '', '', '', 'Razão Social', 'Empresa Ltda', 'CEP', '99500-000'],
      ['', '', '', '', 'CNPJ', '11.222.333/0001-44', 'Estado', 'RS'],
      ['', '', '', '', 'IE', '12345', 'Cidade', 'Carazinho'],
      ['', '', '', '', 'Nome Fantasia', 'Empresa', 'Bairro', 'Centro'],
      ['', '', '', '', 'Telefone 01', '54 5555-5555', 'Rua', 'Rua Teste'],
      ['', '', '', '', 'Telefone 02', '54 6666-6666', 'Complemento', 'Sala 1'],
      [
        '',
        '',
        '',
        '',
        'E-mail de acesso ao portal',
        'portal@example.com',
        'Número',
        '10'
      ],
      ['', '', '', '', 'ACESSO AO PRICES'],
      [
        '',
        '',
        '',
        '',
        'Site de acesso:',
        'https://prices.example.com',
        'Prices',
        '123456'
      ],
      ['', '', '', '', 'Usuário Prices', 'Usuario', 'Senha', 'prices-teste'],
      ['', '', '', '', 'CYNCLY'],
      [
        '',
        '',
        '',
        '',
        'Consultor de Implantação',
        'Consultor',
        'consultor@example.com',
        '54 9999-9999'
      ],
      ['', '', '', '', 'Exec. de Relacionamento', 'ER', 'er@example.com'],
      ['', '', '', '', 'Gestor Regional', 'Gestor sem e-mail', ''],
    ]);
    expect(parsed.fields['telefone_consultor'], '54 9999-9999');
    expect(parsed.fields['telefone_tecnico'], '54 4444-4444');
    expect(parsed.fields['cpf_proprietario'], '111.222.333-44');
    expect(parsed.fields['ns'], '80200790');
    expect(parsed.fields['versao'], '2026.1');
    expect(parsed.fields['id_sistema'], '9456');
    expect(parsed.fields['email_portal'], 'portal@example.com');
    expect(parsed.fields['senha_prices'], 'prices-teste');
    expect(parsed.fields['cep'], '99500-000');
    expect(parsed.fields['rua'], 'Rua Teste');
    expect(parsed.fields['senha_dimensoes'], 'config-teste');
    expect(
        parsed.contacts.any((c) => c.email == 'portal@example.com'), isFalse);
    expect(
        parsed.contacts
            .singleWhere((c) => c.name == 'Gestor sem e-mail')
            .destination,
        'Não incluir');
    final template = renderEmailTemplate(
        '{sistema} {ns} {versao} {telefone_consultor}', parsed.fields);
    expect(template, 'Sistema Cliente 80200790 2026.1 54 9999-9999');
  });
  test(
      'merged label values are found without borrowing data from the opposite table',
      () {
    final parsed = parseEmailWorkbookRows([
      ['', 'Nome do sistema', '', 'Sistema Cliente'],
      ['', 'ID da Biblioteca', '', '', 'Razão Social', 'Empresa Ltda'],
      ['', '', '', '', 'CNPJ', '', 'CEP', '99500-000'],
    ]);
    expect(parsed.fields['sistema'], 'Sistema Cliente');
    expect(parsed.fields['razao_social'], 'Empresa Ltda');
    expect(parsed.fields.containsKey('biblioteca'), isFalse);
    expect(parsed.fields.containsKey('cnpj'), isFalse);
    expect(parsed.fields['cep'], '99500-000');
    expect(parsed.contacts, isEmpty);
  });
  test(
      'summary is included before the signature in a custom message without changing its text',
      () {
    const original = 'Mensagem personalizada.\n\nAtt,\nRodrigo';
    final result = emailBodyWithSummary(
        original, 'Treinamento concluído conforme a proposta.');
    expect(result,
        'Mensagem personalizada.\n\nResumo da implantação:\nTreinamento concluído conforme a proposta.\n\nAtt,\nRodrigo');
    expect(
        emailBodyWithSummary(
            result, 'Treinamento concluído conforme a proposta.'),
        result);
    expect(emailBodyWithSummary(original, ''), original);
  });
  test(
      'changing a summary updates its section while preserving the rest of the edited message',
      () {
    final original = emailBodyWithSummary(
        'Texto editado\n\nAtt,\nRodrigo', 'Primeiro resumo');
    final updated = emailBodyWithSummary(original, 'Resumo atualizado',
        previousSummary: 'Primeiro resumo');
    expect(updated, isNot(contains('Primeiro resumo')));
    expect(updated, contains('Resumo da implantação:\nResumo atualizado'));
    expect(updated, startsWith('Texto editado'));
    expect(updated, endsWith('Att,\nRodrigo'));
    expect(emailBodyWithSummary('Texto com {resumo}', 'Resumo'),
        'Texto com Resumo');
  });
  test(
      'image placement preserves manually edited messages and never duplicates a marker',
      () {
    const edited =
        'Texto ajustado manualmente\nProdutos adquiridos pelo cliente:\nObservação do cliente\nAssinatura';
    final result = emailBodyWithProductsImage(edited);
    expect(result,
        'Texto ajustado manualmente\nProdutos adquiridos pelo cliente:\n$productsImageMarker\nObservação do cliente\nAssinatura');
    expect(emailBodyWithProductsImage(result), result);
    expect(emailBodyWithProductsImage('Texto personalizado'),
        startsWith('Texto personalizado\n\nProdutos adquiridos'));
  });
  test(
      'proposal image is embedded by CID in the email body while PDF stays an attachment',
      () {
    final image = Uint8List.fromList([137, 80, 78, 71]);
    final message = utf8.decode(buildEmailDraft(
        subject: 'Encerramento',
        body:
            'Produtos adquiridos pelo cliente:\n$productsImageMarker\nDados gerais do sistema',
        contacts: [EmailContact(email: 'a@example.com', destination: 'Para')],
        productsImage: image,
        attachments: [
          EmailAttachment('Plano.pdf', Uint8List.fromList([1, 2]))
        ]));
    expect(message, contains('Content-Type: multipart/related;'));
    expect(message, contains('Content-Type: image/png'));
    expect(message, contains('Content-Disposition: inline;'));
    expect(
        message,
        contains(
            "Content-Disposition: attachment; filename*=UTF-8''Plano.pdf"));
    final htmlPart = RegExp(
            r'Content-Type: text/html;[^\r]+\r\nContent-Transfer-Encoding: base64\r\n\r\n([\s\S]*?)\r\n--')
        .firstMatch(message)!;
    final html = utf8
        .decode(base64Decode(htmlPart.group(1)!.replaceAll(RegExp(r'\s'), '')));
    expect(html, contains('<img src="cid:'));
    expect(html.indexOf('<img'),
        greaterThan(html.indexOf('Produtos adquiridos pelo cliente:')));
    expect(html.indexOf('<img'),
        lessThan(html.indexOf('Dados gerais do sistema')));
    expect(html, isNot(contains(productsImageMarker)));
  });
  test(
      'project dates and directories are imported without replacing the proposal print with a product list',
      () {
    final data = parseEmailWorkbookRows([
      ['', 'Sim', 'Enterprise'],
      ['', 'Sim', 'Implantação'],
      ['', 'Não', 'Catalog'],
      ['', 'Sim', '# Produto a preencher #'],
      ['', 'DATAS'],
      ['', 'Assinatura da proposta', '21/07/2026'],
      ['', 'Início do projeto pela Consultoria', '24/07/2026'],
      ['', 'Encerramento do projeto', '15/10/2026'],
      ['', 'DIRETÓRIOS'],
      [
        '',
        'Materiais da Implantação',
        'https://example.com/material?project=123#arquivos'
      ],
      [
        '',
        'Sistema do cliente',
        'Liberado no Portal para todos os NS em 24/07/2026'
      ],
      ['', 'Sim', 'Resposta fora dos produtos'],
      ['CYNCLY'],
      ['Consultor de Implantação', 'Rodrigo', 'rod@example.com'],
    ]);
    expect(data.fields['data_recebimento'], '24/07/2026');
    expect(data.fields['data_finalizacao'], '15/10/2026');
    expect(data.fields['materiais'],
        'https://example.com/material?project=123#arquivos');
    expect(data.fields['liberacao'],
        'Liberado no Portal para todos os NS em 24/07/2026');
    expect(data.fields.containsKey('produtos'), isFalse);
    expect(data.contacts.single.email, 'rod@example.com');
  });

  test('dates stored as Excel date cells become Brazilian dates without time',
      () {
    final book = Excel.createExcel();
    final sheet = book['Informações de entrada'];
    sheet.appendRow([
      TextCellValue('Início do projeto pela Consultoria'),
      DateCellValue(year: 2026, month: 7, day: 24)
    ]);
    sheet.appendRow([
      TextCellValue('Encerramento do projeto'),
      DateTimeCellValue(year: 2026, month: 10, day: 15, hour: 12, minute: 30)
    ]);
    sheet.appendRow([TextCellValue('CYNCLY')]);
    sheet.appendRow([
      TextCellValue('Consultor de Implantação'),
      TextCellValue('Rodrigo'),
      TextCellValue('rod@example.com')
    ]);
    final data = readEmailWorkbook(book.encode()!);
    expect(data.fields['data_recebimento'], '24/07/2026');
    expect(data.fields['data_finalizacao'], '15/10/2026');
  });

  test('blank or placeholder project details do not overwrite an email field',
      () {
    final data = parseEmailWorkbookRows([
      ['Início do projeto pela Consultoria', ''],
      ['Encerramento do projeto', '# Data encerramento #'],
      ['Materiais da Implantação', '# caminho material cliente #'],
      [
        'Sistema do cliente',
        '# Liberado no Portal para todos os NS em (xx/xx/xxxx) #'
      ],
      ['CYNCLY'],
      ['Consultor de Implantação', 'Rodrigo', 'rod@example.com'],
    ]);
    for (final field in [
      'data_recebimento',
      'data_finalizacao',
      'materiais',
      'liberacao',
      'produtos'
    ]) {
      expect(data.fields.containsKey(field), isFalse);
    }
  });
  test(
      'Client section imports real contacts and excludes placeholders and portal login',
      () {
    final data = parseEmailWorkbookRows([
      ['', '', 'CLIENTE'],
      [
        '',
        '',
        'Proprietário',
        'Roberto',
        'roberto@example.com',
        '(54) 3101-0288'
      ],
      ['', '', 'Responsável técnico', 'Ana', 'ana@example.com', ''],
      ['', '', 'Participante adicional 01', 'Carlos', 'carlos@example.com', ''],
      [
        '',
        '',
        'Participante adicional 02',
        '# participante adicional 2 #',
        '# email part adicional 2 #'
      ],
      ['', '', 'INFORMAÇÕES COMERCIAIS'],
      ['', '', 'Razão Social', 'Empresa de teste'],
      ['', '', 'CNPJ', '00.000.000/0001-00'],
      ['', '', 'E-mail de acesso ao portal', 'portal@example.com'],
      ['', '', 'CYNCLY'],
      ['', '', 'Consultor de Implantação', 'Rodrigo', 'rod@example.com'],
    ]);
    expect(data.contacts.where((c) => c.group == 'Cliente').length, 3);
    expect(data.contacts.where((c) => c.group == 'Cyncly').length, 1);
    expect(data.contacts.any((c) => c.email == 'portal@example.com'), isFalse);
    expect(data.fields['email_cliente'], 'roberto@example.com');
    expect(data.fields['email_tecnico'], 'ana@example.com');
    expect(data.fields['razao_social'], 'Empresa de teste');
    expect(data.contacts.every((c) => c.destination == 'Não incluir'), isTrue);
  });
  test('Backup supports email drafts and preserves existing secret filtering',
      () {
    final data = encodeBackupValue({
      'fields': {'cliente': 'Cliente', 'senha_dimensoes': 'private'}
    });
    final plan = validateBackup(
        jsonEncode({
          'format': 'gerenciador_horas_backup',
          'version': 1,
          'uid': 'owner',
          'documents': [
            {'path': 'projects/123/email_drafts/internal', 'data': data}
          ]
        }),
        'owner');
    expect(plan.documents.single.data['fields']['cliente'], 'Cliente');
    expect(plan.documents.single.data['fields'].containsKey('senha_dimensoes'),
        isFalse);
  });
  test('Enterprise models substitute project data without mixing audiences',
      () {
    final values = {
      'cliente': 'CLIENTE A',
      'solicitacao': '123',
      'consultor': 'Rodrigo',
      'equipe': 'Equipe interna'
    };
    expect(
        renderEmailTemplate(
            defaultEmailSubject(ProjectEmailKind.initial), values),
        contains('123'));
    expect(
        defaultEmailBody(ProjectEmailKind.initial), isNot(contains('{hora_reuniao}')));
    expect(defaultEmailBody(ProjectEmailKind.internal),
        contains('{senha_dimensoes}'));
    expect(defaultEmailBody(ProjectEmailKind.finalization),
        isNot(contains('{senha_dimensoes}')));
  });
  test('Workbook contacts are limited to Cyncly and retain distinct roles', () {
    final parsed = parseEmailWorkbookRows([
      ['Nome do sistema', 'Promob Teste'],
      ['Proprietário', 'Cliente', 'cliente@example.com'],
      ['', '', 'CYNCLY'],
      ['', '', 'Consultor de Implantação', 'Rodrigo', 'rod@example.com'],
      ['', '', 'Exec. de Relacionamento', 'Maria', 'maria@example.com'],
      ['', '', 'Participante adicional', '# participante #', '# email #'],
      ['', '', 'INFORMAÇÕES COMERCIAIS'],
      ['', '', 'Vendas', 'Outro', 'outro@example.com'],
    ]);
    expect(parsed.contacts.length, 2);
    expect(parsed.fields['sistema'], 'Promob Teste');
    expect(parsed.fields['er'], 'Maria');
    expect(
        parsed.contacts.every((c) => c.destination == 'Não incluir'), isTrue);
  });
  test('Reads actual xlsx sheet with accent in its name', () {
    final book = Excel.createExcel();
    final sheet = book['Informações de entrada'];
    sheet.appendRow([TextCellValue('CYNCLY')]);
    sheet.appendRow([
      TextCellValue('Consultor de Implantação'),
      TextCellValue('Rodrigo'),
      TextCellValue('rod@example.com')
    ]);
    expect(readEmailWorkbook(book.encode()!).contacts.single.name, 'Rodrigo');
  });
  test('Draft deduplicates addresses and contains unicode body and attachments',
      () {
    final bytes = buildEmailDraft(
        subject: 'Finalização',
        body: 'Olá, implantação concluída.',
        contacts: [
          EmailContact(email: 'cliente@example.com', destination: 'Para'),
          EmailContact(email: 'CLIENTE@example.com', destination: 'Cc'),
          EmailContact(email: 'er@example.com', destination: 'Cc'),
        ],
        attachments: [
          EmailAttachment('Plano assinado.pdf', Uint8List.fromList([1, 2, 3]))
        ]);
    final text = utf8.decode(bytes);
    expect(text, contains('X-Unsent: 1\r\n'));
    expect(text, contains('To: cliente@example.com\r\nCc: er@example.com'));
    expect(text,
        contains(base64Encode(utf8.encode('Olá, implantação concluída.'))));
    expect(text, contains('filename*=UTF-8\'\'Plano%20assinado.pdf'));
    expect(text, contains('AQID'));
  });
  test('Draft refuses missing recipients and header injection', () {
    expect(() => buildEmailDraft(subject: 'x', body: 'y', contacts: []),
        throwsFormatException);
    expect(
        () => buildEmailDraft(subject: 'x', body: 'y', contacts: [
              EmailContact(
                  email: 'a@example.com\r\nBcc: other@example.com',
                  destination: 'Para')
            ]),
        throwsFormatException);
  });
}
