Map<String, dynamic> projectMovePatch(
    Map<String, dynamic> project, Map<String, dynamic> move) {
  if (move['moved'] != true) {
    throw StateError('A movimentação não foi confirmada.');
  }
  final oldFolder = move['oldFolderReference'],
      newFolder = move['folderReference'];
  final oldExcel = move['oldExcelReference'] ?? '',
      newExcel = move['excelReference'] ?? '';
  if (oldFolder is! String ||
      newFolder is! String ||
      oldFolder.isEmpty ||
      newFolder.isEmpty) {
    throw StateError('A movimentação retornou vínculos inválidos.');
  }
  if (project['folderPath'] != oldFolder &&
          project['folderPath'] != newFolder ||
      (project['excelLink'] ?? '') != oldExcel &&
          (project['excelLink'] ?? '') != newExcel) {
    throw StateError(
        'Os vínculos do projeto foram alterados em outra tela. A pasta já foi movida; confira os caminhos antes de continuar.');
  }
  return {'folderPath': newFolder, 'excelLink': newExcel};
}
