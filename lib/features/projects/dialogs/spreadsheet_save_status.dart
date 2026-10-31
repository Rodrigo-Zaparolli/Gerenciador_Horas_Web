/// A preview or a cloud snapshot never confirms a write to the original Excel.
enum SpreadsheetWriteState { unchanged, saving, saved, unconfirmed }

String spreadsheetSaveLabel(SpreadsheetWriteState state, int pending,
    {bool loading = false, String? pendingLabel}) {
  if (state == SpreadsheetWriteState.saving) return 'Gravando no Excel...';
  if (state == SpreadsheetWriteState.unconfirmed) {
    return 'Grava\u00e7\u00e3o n\u00e3o confirmada';
  }
  if (pending > 0) {
    return pendingLabel ??
        '$pending ${pending == 1 ? 'altera\u00e7\u00e3o pendente' : 'altera\u00e7\u00f5es pendentes'}';
  }
  if (loading) return 'Lendo a planilha...';
  return state == SpreadsheetWriteState.saved
      ? 'Salvo no Excel'
      : 'Sem altera\u00e7\u00f5es pendentes';
}
