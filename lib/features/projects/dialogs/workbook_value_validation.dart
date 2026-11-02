dynamic parseWorkbookInput(Map<String, dynamic> field, String text) {
  dynamic value;
  if (field['scheduleStatus'] == true &&
      const ['Programado', 'Cancelado', 'Reprogramado', ''].contains(text)) {
    value = text;
  } else if (const ['number', 'percent'].contains(field['kind']) ||
      field['percent'] == true) {
    value = double.tryParse(text.replaceAll(',', '.'));
  } else {
    value = field['value'] == '' && field['kind'] != 'time'
        ? double.tryParse(text.replaceAll(',', '.')) ?? text
        : text;
  }
  if ((field['percent'] == true || field['kind'] == 'percent') &&
      value is num) {
    value /= 100;
  }
  final error = value == null
      ? 'Informe um n\u00famero v\u00e1lido.'
      : validateWorkbookValue(field, value);
  if (error != null) throw FormatException(error);
  return value;
}

String? validateWorkbookValue(Map<String, dynamic> field, dynamic value) {
  if (field['consultoriaStatus'] == true) {
    return const ['Programado', 'Realizado', 'Cancelado'].contains(value)
        ? null
        : 'Selecione Programado, Realizado ou Cancelado.';
  }
  if (field['scheduleStatus'] == true) {
    if (const ['Programado', 'Cancelado', 'Reprogramado', ''].contains(value)) {
      return null;
    }
    return value is num && value.isFinite && value >= 0 && value <= 1
        ? null
        : 'Use percentual de 0 a 100 ou um status permitido.';
  }
  if (field['percent'] == true || field['kind'] == 'percent') {
    if (value is! num || !value.isFinite || value < 0 || value > 1) {
      return 'Informe um percentual entre 0 e 100.';
    }
  }
  if (field['kind'] == 'time' &&
      (value is! String ||
          value.isNotEmpty && !RegExp(r'^\d{1,4}:[0-5]\d$').hasMatch(value))) {
    return 'Informe o hor\u00e1rio no formato HH:mm.';
  }
  if (field['kind'] == 'number' && (value is! num || !value.isFinite)) {
    return 'Informe um n\u00famero v\u00e1lido.';
  }
  return null;
}
