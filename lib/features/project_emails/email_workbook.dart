import 'package:excel/excel.dart';
import 'email_document.dart';

String _key(String value) {
  var s = value.toLowerCase().trim();
  for (final pair in [
    ('áàãâ', 'a'),
    ('éê', 'e'),
    ('í', 'i'),
    ('óôõ', 'o'),
    ('ú', 'u'),
    ('ç', 'c')
  ]) {
    for (final c in pair.$1.split('')) {
      s = s.replaceAll(c, pair.$2);
    }
  }
  return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class EmailWorkbookData {
  final Map<String, String> fields;
  final List<EmailContact> contacts;
  EmailWorkbookData(this.fields, this.contacts);
}

String _dateText(int year, int month, int day) =>
    '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year';

bool _placeholder(String value) => RegExp(r'#[^#]+#').hasMatch(value);

String _cellText(CellValue? value) => switch (value) {
      DateCellValue(:final year, :final month, :final day) =>
        _dateText(year, month, day),
      DateTimeCellValue(:final year, :final month, :final day) =>
        _dateText(year, month, day),
      TimeCellValue(:final hour, :final minute) =>
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
      _ => value?.toString() ?? '',
    };

EmailWorkbookData readEmailWorkbook(List<int> bytes) {
  if (bytes.length > 30 * 1024 * 1024) {
    throw const FormatException('A planilha deve ter até 30 MB.');
  }
  final book = Excel.decodeBytes(bytes);
  final matches =
      book.tables.entries.where((e) => _key(e.key) == 'informacoesdeentrada');
  if (matches.isEmpty) {
    throw const FormatException(
        'Não foi encontrada a aba Informações de entrada.');
  }
  return parseEmailWorkbookRows(matches.first.value.rows
      .map((row) => row.map((cell) => _cellText(cell?.value)).toList())
      .toList());
}

bool _contactRole(String role) =>
    const {
      'proprietario',
      'responsaveltecnico',
      'consultordeimplantacao',
      'execderelacionamento',
      'executivoderelacionamento',
      'executivodevendas',
      'execdevendas',
      'gestorregional',
      'coordenadorregional',
      'gestordeimplantacao',
      'coordenadoraimplantacao',
      'coordenadordeimplantacao',
      'liderdeprojetos',
      'gestoraservicos',
      'gestordeservicos',
      'coordenadorsuporte',
      'liderdeprojetosservicos',
    }.contains(_key(role)) ||
    RegExp(r'^participanteadicional\d*$').hasMatch(_key(role));

EmailWorkbookData parseEmailWorkbookRows(List<List<String>> rows) {
  final fields = <String, String>{};
  final contacts = <EmailContact>[];
  const labels = {
    'nomedosistema': 'sistema',
    'nomeresumidodosistema': 'nome_resumido_sistema',
    'id': 'id_sistema',
    'nsparainstalacao': 'ns',
    'versaorevisao': 'versao',
    'assinaturadaproposta': 'assinatura_proposta',
    'iddabiblioteca': 'biblioteca',
    'cnpj': 'cnpj',
    'razaosocial': 'razao_social',
    'nomefantasia': 'nome_fantasia',
    'telefone01': 'telefone_cliente',
    'telefone02': 'telefone_cliente_secundario',
    'emaildeacessoaoportal': 'email_portal',
    'ie': 'ie',
    'cep': 'cep',
    'estado': 'estado',
    'cidade': 'cidade',
    'bairro': 'bairro',
    'rua': 'rua',
    'endereco': 'rua',
    'complemento': 'complemento',
    'numero': 'numero',
    'sitedeacesso': 'site_prices',
    'prices': 'id_prices',
    'usuarioprices': 'usuario_prices',
    'proprietario': 'proprietario',
    'responsaveltecnico': 'responsavel_tecnico',
    'emailresponsaveltecnico': 'email_tecnico',
    'consultordeimplantacao': 'consultor',
    'execderelacionamento': 'er',
    'executivoderelacionamento': 'er',
    'emaildoconsultor': 'email_consultor',
    'telefonedoconsultor': 'telefone_consultor',
    'materiaisdaimplantacao': 'materiais',
    'sistemadocliente': 'liberacao',
    'iniciodoprojetopelaconsultoria': 'data_recebimento',
    'encerramentodoprojeto': 'data_finalizacao',
    'dataderecebimento': 'data_recebimento',
    'datadefinalizacao': 'data_finalizacao',
    'datadaprimeirareuniao': 'data_reuniao',
    'horariodareuniao': 'hora_reuniao',
    'resumodaimplantacao': 'resumo',
    'senhadoconfiguradordedimensoes': 'senha_dimensoes',
    'senhadosorcamentos': 'senha_orcamentos',
    'senhadasmargens': 'senha_margens',
  };
  String? section;
  bool prices = false;
  String valueAfter(List<String> row, int index) {
    final end = index < 4 ? 4 : index + 4;
    for (var next = index + 1; next < row.length && next < end; next++) {
      final value = row[next].trim();
      if (value.isEmpty) continue;
      if (next > index + 1 &&
          (labels.containsKey(_key(value)) ||
              _contactRole(value) ||
              const {
                'cliente',
                'cyncly',
                'datas',
                'biblioteca',
                'senhas',
                'diretorios',
                'informacoescomerciais',
                'acessoaoprices'
              }.contains(_key(value)))) return '';
      return value;
    }
    return '';
  }

  for (final row in rows) {
    if (row.any((v) => _key(v) == 'acessoaoprices')) prices = true;
    if (row.any((v) =>
        ['cliente', 'cyncly', 'informacoescomerciais'].contains(_key(v))))
      prices = false;
    if (row.any((v) => _key(v) == 'cliente') && !row.any(validEmail))
      section = 'Cliente';
    if (row.any((v) => _key(v) == 'cyncly')) section = 'Cyncly';
    if (row.any(
        (v) => ['informacoescomerciais', 'acessoaoprices'].contains(_key(v))))
      section = null;
    if (section != null) {
      for (var i = 0; i + 1 < row.length; i++) {
        final role = row[i].trim(), name = row[i + 1].trim();
        if (!_contactRole(role) || name.isEmpty || _placeholder(name)) continue;
        final address = i + 2 < row.length ? row[i + 2].trim() : '';
        // Names without an email still belong to the team, but start excluded
        // from recipients. Selecting them requires a valid email before export.
        if (validEmail(address)) continue;
        if (!contacts.any(
            (c) => c.group == section && c.role == role && c.name == name)) {
          contacts.add(EmailContact(role: role, name: name, group: section));
        }
        if (_key(role) == 'consultordeimplantacao' && i + 3 < row.length) {
          final phone = row[i + 3].trim();
          if (phone.isNotEmpty && !_placeholder(phone))
            fields['telefone_consultor'] = phone;
        }
      }
    }
    for (var i = 0; i < row.length; i++) {
      final field = prices && _key(row[i]) == 'senha'
          ? 'senha_prices'
          : labels[_key(row[i])];
      if (field != null && i + 1 < row.length) {
        final value = valueAfter(row, i);
        if (value.isNotEmpty && !_placeholder(value)) fields[field] = value;
      }
      if (section != null && i >= 2 && validEmail(row[i])) {
        final role = row[i - 2].trim(),
            name = row[i - 1].trim(),
            email = row[i].trim();
        if (role.isEmpty ||
            name.isEmpty ||
            name.contains('#') ||
            role.contains('#')) continue;
        if (contacts.any((c) =>
            _key(c.role) == _key(role) &&
            c.group == section &&
            c.email.toLowerCase() == email.toLowerCase())) {
          continue;
        }
        contacts.add(
            EmailContact(role: role, name: name, email: email, group: section));
        if (section == 'Cliente' && _key(role) == 'proprietario') {
          fields['proprietario'] = name;
          fields['email_cliente'] = email;
          if (i + 1 < row.length &&
              row[i + 1].trim().isNotEmpty &&
              !row[i + 1].contains('#'))
            fields['telefone_cliente'] = row[i + 1].trim();
          if (i + 2 < row.length &&
              row[i + 2].trim().isNotEmpty &&
              !_placeholder(row[i + 2])) {
            fields['cpf_proprietario'] = row[i + 2].trim();
          }
        }
        if (section == 'Cliente' && _key(role) == 'responsaveltecnico') {
          fields['responsavel_tecnico'] = name;
          fields['email_tecnico'] = email;
          if (i + 1 < row.length &&
              row[i + 1].trim().isNotEmpty &&
              !_placeholder(row[i + 1])) {
            fields['telefone_tecnico'] = row[i + 1].trim();
          }
          if (i + 2 < row.length &&
              row[i + 2].trim().isNotEmpty &&
              !_placeholder(row[i + 2])) {
            fields['cpf_tecnico'] = row[i + 2].trim();
          }
        }
        if (section == 'Cyncly' && _key(role) == 'consultordeimplantacao') {
          fields['consultor'] = name;
          fields['email_consultor'] = email;
          if (i + 1 < row.length &&
              row[i + 1].trim().isNotEmpty &&
              !_placeholder(row[i + 1])) {
            fields['telefone_consultor'] = row[i + 1].trim();
          }
        }
        if (section == 'Cyncly' &&
            ['execderelacionamento', 'executivoderelacionamento']
                .contains(_key(role))) {
          fields['er'] = name;
          fields['email_er'] = email;
        }
      }
    }
  }
  if (contacts.isEmpty && fields.isEmpty) {
    throw const FormatException(
        'Não foram encontrados contatos válidos nas seções CLIENTE ou CYNCLY. Você pode cadastrá-los manualmente.');
  }
  return EmailWorkbookData(fields, contacts);
}
