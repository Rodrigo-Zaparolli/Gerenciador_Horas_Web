"""Use disposable workbook copies only; prove preview does not save pending edits."""
import sys
from pathlib import Path
import shutil
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from local_edesk.excel_editor import edit, revision

source = Path(sys.argv[1]).resolve()
kind = sys.argv[2]
original = revision(source)
with tempfile.TemporaryDirectory(prefix='status-preview-', dir=Path('build').resolve()) as directory:
    copy = Path(directory) / source.name
    shutil.copy2(source, copy)
    data = edit(copy, {'action': 'excel-editor-read', 'serviceType': kind})
    baseline = edit(copy, {'action': 'excel-editor-preview', 'serviceType': kind,
        'revision': data['revision'], 'changes': []})
    task = next(t for t in reversed(data['tasks']) if t['value'] != 1)
    change = {k: task[k] for k in ['sheet', 'cell']}
    change.update(before=task['value'], value=1.0)
    preview = edit(copy, {'action': 'excel-editor-preview', 'serviceType': kind,
        'revision': data['revision'], 'changes': [change]})
    assert preview['preview'] is True and preview['statusPreview']['rows']
    assert preview['statusPreview']['total'] != baseline['statusPreview']['total'], 'Pending task did not change the preview total'
    assert revision(copy) == original and revision(source) == original
    assert not (copy.parent / '.gerenciador-backups').exists()
    assert not list(copy.parent.glob('.gerenciador-*'))
    saved = edit(copy, {'action': 'excel-editor-write', 'serviceType': kind,
        'revision': data['revision'], 'changes': [change]})
    checked = edit(copy, {'action': 'excel-editor-preview', 'serviceType': kind,
        'revision': saved['revision'], 'changes': []})
    assert checked['statusPreview'] == preview['statusPreview']
    assert revision(source) == original
    try:
        edit(copy, {'action': 'excel-editor-preview', 'serviceType': kind,
            'revision': data['revision'], 'changes': []})
        raise AssertionError('Stale preview accepted')
    except ValueError as error:
        assert 'mudou' in str(error)
    print('CHECKLIST_PREVIEW_OK:', kind, 'preview matches saved Excel; source, copy and backups untouched by preview')
