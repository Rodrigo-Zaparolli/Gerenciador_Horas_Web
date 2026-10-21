"""Exercise renamed tabs on a disposable real workbook; never save the source."""
from pathlib import Path
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from local_edesk.excel_editor import edit, revision, workbook, vba

source = Path(sys.argv[1]).resolve(strict=True)
original = revision(source)
names = {'entry': 'Entrada do cliente', 'checklist': 'Professional - Ajustado'}
with tempfile.TemporaryDirectory(prefix='sheet-names-', dir=ROOT / 'build') as temporary:
    path = Path(temporary) / source.name
    shutil.copy2(source, path)
    with workbook(path, writable=True) as (_, book):
        book.Worksheets('Informações de entrada').Name = names['entry']
        book.Worksheets('Checklist-Processo').Name = names['checklist']
        book.Save()
    renamed_hash, macros = revision(path), vba(path)
    listed = edit(path, {'action': 'excel-editor-sheets'})
    assert all(name in listed['sheetNames'] for name in names.values())
    try:
        edit(path, {'action': 'excel-editor-read'})
        raise AssertionError('Missing defaults should require sheet configuration')
    except ValueError:
        pass
    data = edit(path, {'action': 'excel-editor-read', 'sheetNames': names})
    assert data['entrySheet'] == names['entry']
    assert data['checklistSheet'] == names['checklist']
    assert all(task['sheet'] == names['checklist'] for task in data['tasks'])
    preview = edit(path, {'action': 'excel-editor-preview', 'sheetNames': names,
                         'revision': data['revision'], 'changes': []})
    assert preview['preview'] and preview['checklistSheet'] == names['checklist']
    assert revision(path) == renamed_hash
    field = next(f for f in data['fields'] if f['label'] == 'Nome do sistema')
    saved = edit(path, {'action': 'excel-editor-write', 'sheetNames': names,
                       'revision': data['revision'], 'changes': [{
                           'sheet': field['sheet'], 'cell': field['cell'],
                           'before': field['value'], 'value': field['value'] + ' TESTE'}]})
    assert saved['saved'] and saved['checklistSheet'] == names['checklist']
    assert vba(path) == macros
    assert revision(source) == original
    print('RENAMED_SHEETS_OK: list, custom read/preview/write, validated cells and VBA preserved; source unchanged')
