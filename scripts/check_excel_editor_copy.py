"""Real Excel acceptance against a disposable copy; never saves the source."""
import hashlib
from pathlib import Path
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from local_edesk.excel_editor import edit, revision, vba

source = Path(sys.argv[1]).resolve(strict=True)
original_hash = revision(source)
with tempfile.TemporaryDirectory(prefix='excel-editor-', dir=ROOT / 'build') as temporary:
    path = Path(temporary) / source.name
    shutil.copy2(source, path)
    backups = path.parent / '.gerenciador-backups'
    backups.mkdir()
    for day in range(1, 8):
        shutil.copy2(path, backups / f'{path.stem}-202601{day:02d}-120000-abcdef12{path.suffix}')
    other_backup = backups / 'Outro-20260101-120000-abcdef12.xlsm'
    other_backup.write_bytes(b'other workbook')
    first = edit(path, {'action': 'excel-editor-read'})
    text = next(f for f in first['fields'] if f['label'] == 'Nome do sistema')
    date = next(f for f in first['fields'] if f['kind'] == 'date')
    yesno = next(f for f in first['fields'] if f['kind'] == 'yesno')
    task = first['tasks'][0]
    selected = [(text, text['value'] + ' TESTE'), (date, '2026-10-19'),
                (yesno, 'Não' if yesno['value'] == 'Sim' else 'Sim'),
                (task, .25 if task['value'] != .25 else .5)]
    changes = [{'sheet': f['sheet'], 'cell': f['cell'], 'before': f['value'], 'value': value} for f, value in selected]
    saved = edit(path, {'action': 'excel-editor-write', 'revision': first['revision'], 'changes': changes})
    assert saved['saved'] is True
    assert revision(Path(saved['backup'])) == original_hash
    assert saved['backupCleanupWarning'] is None
    remaining = [p for p in backups.iterdir() if p != other_backup]
    assert len(remaining) == 5, [p.name for p in remaining]
    assert Path(saved['backup']) in remaining
    assert other_backup.read_bytes() == b'other workbook'
    assert vba(source) == vba(path)
    after = edit(path, {'action': 'excel-editor-read'})
    values = {(f['sheet'], f['cell']): f['value'] for f in after['fields'] + after['tasks']}
    for field, value in selected:
        assert values[(field['sheet'], field['cell'])] == value
    before_rejected = revision(path)
    try:
        edit(path, {'action': 'excel-editor-write', 'revision': first['revision'], 'changes': changes})
        raise AssertionError('Stale revision was accepted')
    except ValueError:
        pass
    assert revision(path) == before_rejected
    assert revision(source) == original_hash
    print('EXCEL_EDITOR_COPY_OK: text/date/yesno/percentage persisted; five backups retained per workbook; VBA intact; stale save blocked; source unchanged')
    print('MAPPED_FIELDS', len(first['fields']), 'TASKS', len(first['tasks']))
