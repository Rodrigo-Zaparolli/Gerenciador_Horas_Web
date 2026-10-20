import os
os.environ['EDESK_LOCAL_MODE'] = 'true'
import tempfile
import unittest
import uuid
from pathlib import Path
from urllib.parse import quote
from unittest.mock import patch
from local_edesk import local_files, project_archive


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=Path('build').resolve())
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / '226144 - Projeto'
        self.source.mkdir()
        (self.source / 'Documentos').mkdir()
        self.excel = self.source / 'Documentos' / 'Projeto.xlsm'
        self.excel.write_bytes(b'workbook-and-macros')
        self.destination = self.root / 'Finalizados'
        self.destination.mkdir()
        self.db = patch.object(local_files, 'DB_PATH', self.root / 'files.sqlite3')
        self.db.start()
        self.addCleanup(self.db.stop)
        self.user = {'sub': 'owner', 'email': 'rodrigozaparolli79@gmail.com'}
        self.folder_ref = self.authorize(self.source, 'folder')
        self.destination_ref = self.authorize(self.destination, 'folder')
        self.excel_ref = self.authorize(self.excel, 'file')

    def authorize(self, path, kind, uid='owner'):
        ref = f'desktop-{kind}://local/{uid}/{uuid.uuid4()}/{quote(str(path), safe="")}'
        local_files._save(uid, ref, path, kind)
        return ref

    def request(self, action, **extra):
        return local_files.execute('owner', {'action': action, **extra}, verified_user=self.user)

    def prepare(self):
        return self.request('project-move-prepare', reference=self.folder_ref,
                            destination=self.destination_ref, excelReference=self.excel_ref)

    def test_move_updates_folder_and_nested_excel_and_retry_does_not_move_again(self):
        plan = self.prepare()
        self.assertTrue(self.source.is_dir())
        self.assertTrue(plan['excelInside'])
        result = self.request('project-move-commit', operation=plan['operation'])
        target = Path(result['target'])
        self.assertFalse(self.source.exists())
        self.assertEqual((target / 'Documentos' / 'Projeto.xlsm').read_bytes(), b'workbook-and-macros')
        for reference, kind, expected in [(result['folderReference'], 'folder', target),
            (result['excelReference'], 'file', target / 'Documentos' / 'Projeto.xlsm')]:
            with local_files._connection() as con:
                row = con.execute('SELECT path FROM files WHERE uid=? AND reference=?', ('owner', reference)).fetchone()
                self.assertEqual(Path(row[0]), expected)
                local_files._check_expected_path(reference, expected)
        self.assertEqual(self.request('project-move-commit', operation=plan['operation']), result)
        self.assertTrue(self.prepare()['alreadyMoved'])
        self.destination_ref = self.authorize(self.destination, 'folder')
        self.assertTrue(self.prepare()['alreadyMoved'])

    def test_destination_collision_and_descendant_do_not_change_source(self):
        (self.destination / self.source.name).mkdir()
        with self.assertRaises(ValueError): self.prepare()
        self.destination_ref = self.authorize(self.source / 'Documentos', 'folder')
        with self.assertRaises(ValueError): self.prepare()
        self.assertTrue(self.excel.exists())

    def test_changed_files_after_confirmation_are_rejected(self):
        plan = self.prepare()
        self.excel.write_bytes(b'changed')
        with self.assertRaises(ValueError): self.request('project-move-commit', operation=plan['operation'])
        self.assertTrue(self.excel.exists())

    def test_failed_rename_can_retry_without_any_deletion(self):
        plan = self.prepare()
        with patch.object(project_archive.os, 'rename', side_effect=PermissionError('open workbook')):
            with self.assertRaises(ValueError): self.request('project-move-commit', operation=plan['operation'])
        self.assertTrue(self.excel.exists())
        result = self.request('project-move-commit', operation=plan['operation'])
        self.assertTrue(result['moved'])

    def test_recovery_after_rename_before_sqlite_commit(self):
        plan = self.prepare()
        rename = os.rename
        def interrupted(source, target):
            rename(source, target)
            raise OSError('simulated interrupted reply')
        with patch.object(project_archive.os, 'rename', side_effect=interrupted):
            with self.assertRaises(ValueError): self.request('project-move-commit', operation=plan['operation'])
        result = self.request('project-move-commit', operation=plan['operation'])
        self.assertTrue(result['moved'])
        self.assertTrue(Path(result['target']).is_dir())

    def test_outside_excel_keeps_its_reference(self):
        external = self.root / 'External.xlsm'
        external.write_bytes(b'external')
        self.excel_ref = self.authorize(external, 'file')
        plan = self.prepare()
        self.assertFalse(plan['excelInside'])
        result = self.request('project-move-commit', operation=plan['operation'])
        self.assertEqual(result['excelReference'], self.excel_ref)
        self.assertEqual(external.read_bytes(), b'external')

    def test_unauthorized_account_and_forged_operation_are_rejected(self):
        plan = self.prepare()
        with self.assertRaises(PermissionError):
            local_files.execute('other', {'action': 'project-move-commit', 'operation': plan['operation']},
                verified_user={'sub': 'other', 'email': 'other@example.com'})
        with self.assertRaises(ValueError): self.request('project-move-commit', operation=str(uuid.uuid4()))
        self.destination_ref = self.authorize(self.destination, 'folder', uid='other')
        with self.assertRaises(ValueError): self.prepare()
        self.assertTrue(self.source.exists())

    def test_different_volume_is_rejected_without_copying(self):
        original = Path.stat
        def different(path, *args, **kwargs):
            info = original(path, *args, **kwargs)
            if path == self.destination:
                from types import SimpleNamespace
                return SimpleNamespace(st_mode=info.st_mode, st_dev=info.st_dev + 1)
            return info
        with patch.object(Path, 'stat', different):
            with self.assertRaisesRegex(ValueError, 'mesma unidade'): self.prepare()
        self.assertTrue(self.excel.exists())

    def test_parallel_excel_operation_blocks_move_without_changing_files(self):
        from local_edesk.excel_editor import lock
        lock.acquire()
        try:
            with self.assertRaisesRegex(ValueError, 'Aguarde'):
                self.prepare()
        finally:
            lock.release()
        self.assertTrue(self.excel.exists())

if __name__ == '__main__': unittest.main()
