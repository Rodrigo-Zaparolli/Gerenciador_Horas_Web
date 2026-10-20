"""Reproduce the text-date opening failure in a disposable workbook copy."""
from pathlib import Path
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from local_edesk.excel_editor import edit, revision, workbook

source = Path(sys.argv[1]).resolve(strict=True)
original = revision(source)
with tempfile.TemporaryDirectory(prefix='excel-text-dates-', dir=ROOT / 'build') as temporary:
    copy = Path(temporary) / source.name
    shutil.copy2(source, copy)
    print('TEXT_DATES_PREPARING_COPY', flush=True)
    with workbook(copy, writable=True) as (_, book):
        sheet = book.Worksheets('Informações de entrada')
        sheet.Range('C22').NumberFormat = '@'
        sheet.Range('C22').Value2 = '19/10/2026'
        sheet.Range('C23').NumberFormat = '@'
        sheet.Range('C23').Value2 = '# Preencher a data de início #'
        book.Save()
        del sheet
    print('TEXT_DATES_READING_COPY', flush=True)
    data = edit(copy, {'action': 'excel-editor-read'})
    fields = {field['cell']: field for field in data['fields'] if field['sheet'] == 'Informações de entrada'}
    assert fields['C22']['value'] == '2026-10-19'
    assert fields['C23']['value'] == '# Preencher a data de início #'
    assert len(data['tasks']) == 159
    print('TEXT_DATES_SAVING_COPY', flush=True)
    edit(copy, {'action': 'excel-editor-write', 'revision': data['revision'], 'changes': [
        {'sheet': fields['C22']['sheet'], 'cell': 'C22', 'before': fields['C22']['value'], 'value': '2026-10-20'}]})
    with workbook(copy) as (_, book):
        cell = book.Worksheets('Informações de entrada').Range('C22')
        assert cell.Value2 == '20/10/2026'
        assert cell.NumberFormat == '@'
        del cell
assert revision(source) == original
print('EXCEL_TEXT_DATES_OK: opens text dates/instructions; edited text date keeps display and storage; source unchanged')
