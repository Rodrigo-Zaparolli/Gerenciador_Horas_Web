import 'dart:convert';
import 'dart:typed_data';

enum ProjectEmailKind {
  initial('Contato inicial'),
  finalization('Finalização ao cliente + ER'),
  internal('Encerramento interno');

  final String label;
  const ProjectEmailKind(this.label);
}

class EmailContact {
  String role, name, email, destination, group;
  EmailContact(
      {this.role = '',
      this.name = '',
      this.email = '',
      this.destination = 'Não incluir',
      this.group = 'Cyncly'});
  Map<String, dynamic> toJson() => {
        'role': role,
        'name': name,
        'email': email,
        'destination': destination,
        'group': group
      };
  factory EmailContact.fromJson(Map<String, dynamic> v) => EmailContact(
      role: v['role'] ?? '',
      name: v['name'] ?? '',
      email: v['email'] ?? '',
      destination: v['destination'] ?? 'Não incluir',
      group: v['group'] ?? 'Cyncly');
}

/// Share available addresses between models without sharing Para/Cc selections.
void mergeAvailableEmailContacts(List<EmailContact> target, Iterable<EmailContact> source) {
  final emails = target.map((c) => c.email.trim().toLowerCase()).toSet();
  for (final contact in source) {
    final email = contact.email.trim();
    if (!validEmail(email) || !emails.add(email.toLowerCase())) continue;
    target.add(EmailContact(role: contact.role, name: contact.name,
        email: email, group: contact.group));
  }
}

class EmailAttachment {
  final String name;
  final Uint8List bytes;
  EmailAttachment(this.name, this.bytes);
}

void selectModelRecipients(List<EmailContact> contacts, ProjectEmailKind kind) {
  for (final contact in contacts) {
    contact.destination = 'Não incluir';
    if (!validEmail(contact.email)) continue;
    if (kind == ProjectEmailKind.internal) {
      if (contact.group == 'Cyncly') contact.destination = 'Para';
    } else if (contact.group == 'Cliente') {
      contact.destination = 'Para';
    } else if (kind == ProjectEmailKind.finalization) {
      final role = contact.role.toLowerCase()
          .replaceAll('ç', 'c').replaceAll('ã', 'a')
          .replaceAll(RegExp(r'[^a-z]'), '');
      if (['execderelacionamento', 'executivoderelacionamento'].contains(role)) {
        contact.destination = 'Cc';
      }
    }
  }
}

const productsImageMarker = '[Print dos produtos adquiridos]';

String emailBodyWithSummary(String body, String summary,
    {String previousSummary = ''}) {
  final value = summary.trim();
  body = body.replaceAll('{resumo}', value);
  if (previousSummary.trim().isNotEmpty && previousSummary.trim() != value) {
    final heading = RegExp(
            r'(^|\n)(?:Resumo da implantação|Resumo de como foi o projeto):[ \t]*\r?\n',
            caseSensitive: false)
        .firstMatch(body);
    if (heading != null) {
      final remaining = body.substring(heading.end);
      if (remaining.startsWith(previousSummary.trim())) {
        body = body.replaceRange(
            heading.end, heading.end + previousSummary.trim().length, value);
      }
    }
  }
  if (value.isEmpty || body.contains(value)) return body;
  final section = 'Resumo da implantação:\n$value';
  final signature = RegExp(
          r'(^|\n)[ \t]*(?:Att[.,]?|Atenciosamente[,:]?)[ \t]*(?=\r?\n|$)',
          caseSensitive: false)
      .firstMatch(body);
  if (signature == null) return '$body\n\n$section';
  return '${body.substring(0, signature.start).trimRight()}\n\n$section\n\n${body.substring(signature.start).trimLeft()}';
}

String emailBodyWithProductsImage(String body) {
  if (body.contains(productsImageMarker)) return body;
  final heading =
      RegExp(r'Produtos adquiridos(?: pelo cliente)?\s*:', caseSensitive: false)
          .firstMatch(body);
  if (heading != null) {
    return body.replaceRange(
        heading.end, heading.end, '\n$productsImageMarker');
  }
  return '$body\n\nProdutos adquiridos pelo cliente:\n$productsImageMarker';
}

bool validEmail(String value) =>
    RegExp(r'^[^\s<>@,;]+@[^\s<>@,;]+\.[^\s<>@,;]+$').hasMatch(value.trim());
String renderEmailTemplate(String source, Map<String, String> fields) => source
    .replaceAllMapped(RegExp(r'\{([a-z_]+)\}'), (m) => fields[m[1]] ?? m[0]!);

const emailFieldLabels = <String, String>{
  'cliente': 'Cliente',
  'solicitacao': 'Solicitação',
  'servico': 'Serviço',
  'sistema': 'Nome do sistema',
  'consultor': 'Consultor',
  'email_consultor': 'E-mail do consultor',
  'telefone_consultor': 'Telefone do consultor',
  'data_recebimento': 'Data de recebimento',
  'data_finalizacao': 'Data de finalização',
  'data_reuniao': 'Data da primeira reunião',
  'hora_reuniao': 'Horário da reunião',
  'er': 'Executivo de Relacionamento',
  'email_er': 'E-mail do ER',
  'materiais': 'Link / caminho dos materiais',
  'liberacao': 'Liberação do sistema no Portal',
  'produtos': 'Produtos adquiridos',
  'biblioteca': 'ID da biblioteca',
  'cnpj': 'CNPJ',
  'senha_dimensoes': 'Senha do configurador de dimensões',
  'senha_orcamentos': 'Senha dos orçamentos',
  'senha_margens': 'Senha das margens',
  'razao_social': 'Razão social',
  'nome_fantasia': 'Nome fantasia',
  'proprietario': 'Proprietário',
  'email_cliente': 'E-mail do cliente',
  'telefone_cliente': 'Telefone do cliente',
  'responsavel_tecnico': 'Responsável técnico',
  'email_tecnico': 'E-mail do responsável técnico',
  'resumo': 'Resumo da implantação',
  'nome_resumido_sistema': 'Nome resumido do sistema',
  'id_sistema': 'ID do sistema',
  'ns': 'NS para instalação',
  'versao': 'Versão / Revisão',
  'assinatura_proposta': 'Assinatura da proposta',
  'telefone_cliente_secundario': 'Telefone 02 do cliente',
  'telefone_tecnico': 'Telefone do responsável técnico',
  'cpf_proprietario': 'CPF do proprietário',
  'cpf_tecnico': 'CPF do responsável técnico',
  'email_portal': 'E-mail de acesso ao portal',
  'ie': 'Inscrição estadual',
  'cep': 'CEP',
  'estado': 'Estado',
  'cidade': 'Cidade',
  'bairro': 'Bairro',
  'rua': 'Rua / Endereço',
  'complemento': 'Complemento',
  'numero': 'Número',
  'site_prices': 'Site de acesso ao Prices',
  'id_prices': 'Prices',
  'usuario_prices': 'Usuário Prices',
  'senha_prices': 'Senha Prices',
};

String defaultEmailSubject(ProjectEmailKind kind) => '${switch (kind) {
      ProjectEmailKind.initial => 'Contato Inicial',
      ProjectEmailKind.finalization => 'Finalização',
      ProjectEmailKind.internal => 'ENCERRAMENTO'
    }} - {solicitacao} - {servico} - {cliente}';

String defaultEmailBody(ProjectEmailKind kind) {
  const signature =
      '\n\nAtt,\n{consultor}\nConsultor de Implantação\n{email_consultor}\npromob.com | foccoerp.com.br';
  return switch (kind) {
    ProjectEmailKind.initial => '''Bom dia a todos!

Primeiramente, gostaria de me apresentar... me chamo {consultor} e serei o Consultor responsável pela Implantação do {sistema}.

Para darmos início à Implantação, segue em anexo uma breve apresentação inicial, onde estão informações como:
• Processo de desenvolvimento e entrega do produto;
• Usuário para acesso ao Portal Promob;
• Passo a passo para auxílio do download, instalação e ativação do seu Promob;
• Requisitos para Implantação;
• Cronograma da Implantação (as datas podem sofrer alterações).

A reunião será remota, e utilizamos o programa TeamViewer para realizar o acesso remoto.
Aguardo confirmação de agenda.

Pedimos que, se houver dúvidas quanto à apresentação em anexo, nos contate para que possamos lhe auxiliar da melhor maneira.$signature''',
    ProjectEmailKind.finalization => '''Bom dia a todos!

Desde já agradeço por todo o empenho e comprometimento nesse processo de Implantação e Pós-Implantação.

Conforme nossa reunião realizada no dia {data_finalizacao}, concluímos o processo de Implantação, juntamente com os ajustes solicitados no período de Pós-Implantação.

Vocês têm um Executivo de Relacionamento e o seu nome é {er}, ele nos lê em cópia através do e-mail {email_er}, e está à sua disposição para quaisquer dúvidas relacionadas aos seus produtos.

Com a conclusão dessa etapa de Implantação, vocês devem iniciar os próximos atendimentos pela equipe do suporte, que acontecerão através da abertura de solicitações, via Portal.
Para que isso ocorra da maneira correta, seguem abaixo algumas informações importantes:
• Ao abrir solicitação no Portal, é importante sempre descrever o máximo possível referente ao motivo da abertura da solicitação.
• Sempre que possível, anexar imagens para mostrar a situação, isso agiliza muito o atendimento e o entendimento da necessidade.
• As solicitações podem ser abertas referente a qualquer necessidade, tanto para customizações, quanto para dúvidas referentes a engenharia de produtos.

Dúvidas em relação à abertura de solicitações podem ser consultadas na página do suporte:
https://suporte.promob.com/hc/pt-br/articles/360043401013-Portal-Como-cadastrar-responder-e-gerenciar-solicita%C3%A7%C3%B5es$signature''',
    ProjectEmailKind.internal => '''Bom dia a todos!

Venho informar aos setores interessados que a Implantação do {sistema} foi concluída.
Projeto recebido pela Consultoria no dia {data_recebimento}
Projeto finalizado pela Consultoria no dia {data_finalizacao}

Segue em anexo o Plano de Projeto e Engenharia do Produto assinados pelo cliente e abaixo a solicitação do projeto:
{solicitacao} - {servico} - {cliente}

Caminho dos Materiais da Implantação → {materiais}
Caminho do Sistema do cliente → {liberacao}

Produtos adquiridos pelo cliente:
{produtos}

Dados gerais do sistema
Nome do sistema: {sistema}
ID da Biblioteca: {biblioteca}
CNPJ: {cnpj}

Senhas:
Senha do Configurador de Dimensões: {senha_dimensoes}
Senha dos Orçamentos: {senha_orcamentos}
Senha das Margens: {senha_margens}

Dados do cliente
Razão Social: {razao_social}
Nome Fantasia: {nome_fantasia}
Proprietário: {proprietario}
E-mail: {email_cliente}
Telefone: {telefone_cliente}
Responsável Técnico: {responsavel_tecnico}
Responsável Técnico E-mail: {email_tecnico}

Equipe Cyncly
{equipe}

Resumo da implantação:
{resumo}$signature''',
  };
}

/// Updates older saved templates and signatures to the current email fields.
String cleanRemovedEmailFields(String body, ProjectEmailKind kind,
    {String consultantPhone = ''}) {
  var inSignature = false;
  return body.split('\n').where((line) {
    final text = line.trim();
    if (RegExp(r'^(Att,|Atenciosamente)', caseSensitive: false)
        .hasMatch(text)) {
      inSignature = true;
    }
    if (line.contains('{telefone_consultor}')) return false;
    if (inSignature && consultantPhone.trim().isNotEmpty &&
        text == consultantPhone.trim()) {
      return false;
    }
    if (kind == ProjectEmailKind.initial &&
        (line.contains('{data_reuniao}') || line.contains('{hora_reuniao}') ||
            text.startsWith('Nossa primeira reunião está agendada para o dia '))) {
      return false;
    }
    return true;
  }).join('\n');
}

/// A draft only: no SMTP/API sending. All header values are encoded or validated.
Uint8List buildEmailDraft(
    {required String subject,
    required String body,
    required List<EmailContact> contacts,
    List<EmailAttachment> attachments = const [],
    Uint8List? productsImage,
    Uint8List? signatureImage,
    String? signatureName,
    String signatureEmail = '',
    String signaturePhone = '',
    Map<String, Uint8List> signatureIcons = const {}}) {
  if (productsImage != null) body = emailBodyWithProductsImage(body);
  final included = contacts
      .where((c) => c.destination == 'Para' || c.destination == 'Cc')
      .toList();
  if (included.isEmpty || !included.any((c) => c.destination == 'Para')) {
    throw const FormatException('Selecione ao menos um destinatário em Para.');
  }
  if (included.any((c) => !validEmail(c.email))) {
    throw const FormatException(
        'Revise os e-mails dos destinatários selecionados.');
  }
  final seen = <String>{};
  List<String> recipients(String destination) => included
      .where((c) => c.destination == destination)
      .map((c) => c.email.trim())
      .where((e) => seen.add(e.toLowerCase()))
      .toList();
  final to = recipients('Para'), cc = recipients('Cc');
  String encoded(String v) {
    final words = <String>[];
    var chunk = '';
    for (final rune in v.replaceAll(RegExp(r'[\r\n]'), ' ').runes) {
      final character = String.fromCharCode(rune);
      if (utf8.encode(chunk + character).length > 42) {
        words.add('=?UTF-8?B?${base64Encode(utf8.encode(chunk))}?=');
        chunk = '';
      }
      chunk += character;
    }
    if (chunk.isNotEmpty) {
      words.add('=?UTF-8?B?${base64Encode(utf8.encode(chunk))}?=');
    }
    return words.join('\r\n ');
  }

  String base64Lines(List<int> bytes) {
    final s = base64Encode(bytes);
    return [
      for (var i = 0; i < s.length; i += 76)
        s.substring(i, (i + 76).clamp(0, s.length))
    ].join('\r\n');
  }

  final boundary = 'gh_${DateTime.now().microsecondsSinceEpoch}';
  final alternative = '${boundary}_alt';
  final related = '${boundary}_related';
  final imageId = '${boundary}_products@gerenciador-horas';
  final signatureId = '${boundary}_signature@gerenciador-horas';
  final hasInlineImages = productsImage != null || signatureImage != null || signatureIcons.isNotEmpty;
  final out = StringBuffer(
      'X-Unsent: 1\r\nMIME-Version: 1.0\r\nTo: ${to.join(', ')}\r\n');
  if (cc.isNotEmpty) out.write('Cc: ${cc.join(', ')}\r\n');
  out.write(
      'Subject: ${encoded(subject)}\r\nContent-Type: multipart/mixed; boundary="$boundary"\r\n\r\n');
  if (hasInlineImages) {
    out.write(
        '--$boundary\r\nContent-Type: multipart/related; boundary="$related"\r\n\r\n');
  }
  final container = hasInlineImages ? related : boundary;
  out.write(
      '--$container\r\nContent-Type: multipart/alternative; boundary="$alternative"\r\n\r\n');
  out.write(
      '--$alternative\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n${base64Lines(utf8.encode(body.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')))}\r\n');
  var content = emailBodyHtml(signatureName == null ? body : emailBodyBeforeSignature(body));
  if (productsImage != null) {
    content = content.replaceAll(productsImageMarker,
        '<img src="cid:$imageId" alt="Produtos adquiridos — proposta do cliente" style="max-width:100%;height:auto;display:block">');
  }
  if (signatureName != null) {
    content += formattedEmailSignature(name: signatureName,
        email: signatureEmail, phone: signaturePhone,
        iconId: (key) => signatureIcons.containsKey(key)
            ? '${boundary}_$key@gerenciador-horas' : null);
  }
  if (signatureImage != null) {
    content += '<br><br><img src="cid:$signatureId" alt="Cyncly | Promob | Focco" width="630" style="width:630px;max-width:100%;height:auto;display:block">';
  }
  final html =
      '<!doctype html><html><head><meta charset="utf-8"></head><body style="font-family:Calibri,Arial,sans-serif;font-size:11pt;color:#172b43">$content</body></html>';
  out.write(
      '--$alternative\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n${base64Lines(utf8.encode(html))}\r\n--$alternative--\r\n');
  if (productsImage != null) {
    out.write(
        '--$related\r\nContent-Type: image/png\r\nContent-ID: <$imageId>\r\n'
        'Content-Disposition: inline; filename="produtos-adquiridos.png"\r\n'
        'Content-Transfer-Encoding: base64\r\n\r\n${base64Lines(productsImage)}\r\n');
  }
  if (signatureImage != null) {
    out.write('--$related\r\nContent-Type: image/jpeg\r\nContent-ID: <$signatureId>\r\n'
        'Content-Disposition: inline; filename="assinatura-cyncly.jpg"\r\n'
        'Content-Transfer-Encoding: base64\r\n\r\n${base64Lines(signatureImage)}\r\n');
  }
  for (final entry in signatureIcons.entries) {
    if (!['mail', 'phone', 'web'].contains(entry.key)) continue;
    out.write('--$related\r\nContent-Type: image/png\r\nContent-ID: <${boundary}_${entry.key}@gerenciador-horas>\r\n'
        'Content-Disposition: inline; filename="assinatura-${entry.key}.png"\r\n'
        'Content-Transfer-Encoding: base64\r\n\r\n${base64Lines(entry.value)}\r\n');
  }
  if (hasInlineImages) out.write('--$related--\r\n');
  for (final a in attachments) {
    final name = Uri.encodeComponent(a.name.replaceAll(RegExp(r'[\r\n]'), ''));
    out.write(
        '--$boundary\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename*=UTF-8\'\'$name\r\nContent-Transfer-Encoding: base64\r\n\r\n${base64Lines(a.bytes)}\r\n');
  }
  out.write('--$boundary--\r\n');
  return Uint8List.fromList(utf8.encode(out.toString()));
}

String emailBodyHtml(String body) {
  const escape = HtmlEscape();
  String escaped(String value) => escape.convert(value).replaceAll('&#47;', '/');
  final out = StringBuffer();
  var offset = 0;
  for (final match in RegExp(
          r'https?://[^\s<>]+|(?<![\w@./-])(?:promob\.com|foccoerp\.com\.br)(?![\w.-])',
          caseSensitive: false).allMatches(body)) {
    out.write(escaped(body.substring(offset, match.start)));
    final display = match.group(0)!;
    final url = display.toLowerCase().startsWith('http') ? display : 'https://$display';
    final uri = Uri.tryParse(url);
    var label = display;
    if (uri != null &&
        (uri.host.toLowerCase() == 'sharepoint.com' ||
            uri.host.toLowerCase().endsWith('.sharepoint.com'))) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final name = segments.isEmpty ? '' : segments.last;
      label = name.isEmpty || name.startsWith(':')
          ? '📁 Abrir no SharePoint' : '📁 $name';
    }
    out.write('<a href="${escaped(url)}">${escaped(label)}</a>');
    offset = match.end;
  }
  out.write(escaped(body.substring(offset)));
  return out.toString().replaceAll('\n', '<br>');
}

String emailBodyBeforeSignature(String body) {
  final matches = RegExp(r'(?:^|\n)(?:Att,|Atenciosamente[,.:]?)\s*\n',
      caseSensitive: false).allMatches(body).toList();
  return matches.isEmpty ? body : body.substring(0, matches.last.start).trimRight();
}

String formattedEmailSignature({required String name, required String email,
    required String phone, required String? Function(String) iconId}) {
  const escape = HtmlEscape();
  String row(String key, String value) {
    final id = iconId(key);
    final icon = id == null ? '' : '<img src="cid:${escape.convert(id)}" width="22" height="22" alt="${escape.convert(key)}" style="display:block;width:22px;height:22px">';
    return '<tr><td style="width:30px;padding:0 8px 10px 0;vertical-align:middle">$icon</td><td style="padding:0 0 10px 0;vertical-align:middle">$value</td></tr>';
  }
  final mail = validEmail(email)
      ? '<a href="mailto:${escape.convert(email)}" style="color:#7052a3;text-decoration:underline">${escape.convert(email)}</a>'
      : escape.convert(email);
  return '<div style="font-family:Verdana,Arial,sans-serif;font-size:9pt"><p style="margin:20px 0">Att,</p>'
      '<p style="margin:0 0 6px 0"><strong>${escape.convert(name)}</strong></p>'
      '<p style="margin:0 0 6px 0">Consultor de Implantação</p>'
      '<table role="presentation" cellpadding="0" cellspacing="0" style="font-family:Verdana,Arial,sans-serif;font-size:9pt;border-collapse:collapse">'
      '${email.isEmpty ? '' : row('mail', mail)}'
      '${phone.isEmpty ? '' : row('phone', escape.convert(phone))}'
      '${row('web', '<strong><a href="https://promob.com">promob.com</a> | <a href="https://foccoerp.com.br">foccoerp.com.br</a></strong>')}'
      '</table></div>';
}
