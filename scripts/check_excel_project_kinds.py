"""Check both project layouts on a disposable workbook copy using real Excel."""
from pathlib import Path
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from local_edesk.excel_editor import edit, revision, vba

source = Path(sys.argv[1]).resolve(strict=True)
original = revision(source)
with tempfile.TemporaryDirectory(prefix='excel-project-kinds-', dir=ROOT / 'build') as temporary:
    copy = Path(temporary) / source.name
    shutil.copy2(source, copy)
    enterprise = edit(copy, {'action': 'excel-editor-read', 'serviceType': 'Enterprise'})
    professional = edit(copy, {'action': 'excel-editor-read', 'serviceType': 'Professional'})
    assert enterprise['checklistSheet'].lower() == 'checklist-processo'
    assert professional['checklistSheet'].lower() == 'maker checklist-processo'
    assert enterprise['tasks'] and professional['tasks']
    task = professional['tasks'][0]
    assert int(task['cell'][1:]) < 17, 'Early Maker rows must not be skipped'
    new = .25 if task['value'] != .25 else .5
    saved = edit(copy, {'action': 'excel-editor-write', 'serviceType': 'Professional',
        'revision': professional['revision'], 'changes': [
            {'sheet': task['sheet'], 'cell': task['cell'], 'before': task['value'], 'value': new}]})
    assert saved['saved'] is True
    after = edit(copy, {'action': 'excel-editor-read', 'serviceType': 'Professional'})
    assert next(t for t in after['tasks'] if t['cell'] == task['cell'])['value'] == new
    unchanged = edit(copy, {'action': 'excel-editor-read', 'serviceType': 'Enterprise'})
    assert {t['cell']: t['value'] for t in unchanged['tasks']} == {t['cell']: t['value'] for t in enterprise['tasks']}
    assert vba(copy) == vba(source)
    assert revision(Path(saved['backup'])) == original
    assert revision(source) == original
    print('EXCEL_PROJECT_KINDS_OK: Maker reads early rows, saves/reopens its task; Enterprise inputs, VBA and original untouched')
    print('TASK_COUNTS', len(enterprise['tasks']), len(professional['tasks']))
