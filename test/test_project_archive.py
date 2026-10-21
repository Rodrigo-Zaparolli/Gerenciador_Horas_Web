import os
import json
os.environ['EDESK_LOCAL_MODE'] = 'true'
import tempfile
import unittest
import uuid
from pathlib import Path
from urllib.parse import quote
from unittest.mock import patch
from local_edesk import local_files, project_archive


class ArchiveTests(unittest.TestCase):
    def test_reopening_after_failed_rename_recovers_retry_instead_of_blocking(self):
        plan = self.prepare()
        with patch.object(project_archive.os, 'rename', side_effect=PermissionError('Excel open')):
            with self.assertRaises(ValueError):
                self.request('project-move-commit', operation=plan['operation'])
        recovered = self.prepare()
        self.assertFalse(recovered['alreadyMoved'])
        self.assertEqual(recovered['operation'], plan['operation'])
        self.assertTrue(self.request('project-move-commit', operation=recovered['operation'])['moved'])

    def test_changed_source_after_failed_rename_requires_a_new_confirmation(self):
        plan = self.prepare()
        with patch.object(project_archive.os, 'rename', side_effect=PermissionError('Excel open')):
            with self.assertRaises(ValueError):
                self.request('project-move-commit', operation=plan['operation'])
        (self.source / 'Novo.txt').write_text('new content')
        fresh = self.prepare()
        self.assertNotEqual(fresh['operation'], plan['operation'])
        with self.assertRaisesRegex(ValueError, 'substituído'):
            self.request('project-move-commit', operation=plan['operation'])
        result = self.request('project-move-commit', operation=fresh['operation'])
        self.assertTrue((Path(result['target']) / 'Novo.txt').exists())

    def test_conflicting_authorizations_can_be_repaired_then_move_the_correct_project(self):
        root_ref = self.folder_ref
        self.folder_ref = self.authorize(self.source / 'Documentos', 'folder')
        bindings = [
            (self.destination_ref, self.destination, 'folder', 'Pasta de destino'),
            (self.folder_ref, self.source / 'Documentos', 'folder', 'Pasta vinculada'),
            (root_ref, self.source, 'folder', 'Pasta inteira'),
            (self.excel_ref, self.excel, 'file', 'Planilha do projeto')]
        wrong_paths = []
        for index, (ref, expected, kind, label) in enumerate(bindings):
            with self.subTest(binding=label):
                wrong = self.root / f'Outro projeto {index}' / expected.name
                wrong.parent.mkdir()
                wrong.mkdir() if kind == 'folder' else wrong.write_bytes(b'other workbook')
                wrong_paths.append(wrong)
                other_ref = self.authorize(wrong, kind)
                with local_files._connection() as con:
                    con.execute('UPDATE files SET path=? WHERE uid=? AND reference=?', (str(wrong), 'owner', ref))
                    con.execute('INSERT INTO files VALUES(?,?,?,?)', ('other', ref, str(wrong), kind))
                with self.assertRaisesRegex(ValueError, label):
                    self.request('project-move-prepare', reference=self.folder_ref,
                        sourceReference=root_ref, destination=self.destination_ref, excelReference=self.excel_ref)
                with patch.object(local_files, 'choose', return_value=str(expected)) as picker, patch.object(local_files.os, 'startfile') as opener:
                    self.assertTrue(self.request('authorize', reference=ref)['authorized'])
                    picker.assert_called_once()
                    opener.assert_not_called()
                with local_files._connection() as con:
                    self.assertEqual(con.execute('SELECT path FROM files WHERE uid=? AND reference=?', ('owner', ref)).fetchone()[0], str(expected))
                    self.assertEqual(con.execute('SELECT path FROM files WHERE uid=? AND reference=?', ('other', ref)).fetchone()[0], str(wrong))
                    self.assertEqual(con.execute('SELECT path FROM files WHERE uid=? AND reference=?', ('owner', other_ref)).fetchone()[0], str(wrong))
        plan = self.request('project-move-prepare', reference=self.folder_ref,
            sourceReference=root_ref, destination=self.destination_ref, excelReference=self.excel_ref)
        result = self.request('project-move-commit', operation=plan['operation'])
        self.assertTrue(result['moved'])
        self.assertTrue((self.destination / self.source.name / 'Documentos' / self.excel.name).exists())
        self.assertTrue(all(path.exists() for path in wrong_paths))

    def test_conflicting_link_cancellation_or_wrong_choice_does_not_repair_or_move(self):
        wrong = self.root / 'Outro projeto'
        wrong.mkdir()
        with local_files._connection() as con:
            con.execute('UPDATE files SET path=? WHERE uid=? AND reference=?', (str(wrong), 'owner', self.folder_ref))
        with patch.object(local_files, 'choose', return_value=''):
            self.assertTrue(self.request('authorize', reference=self.folder_ref)['cancelled'])
        with patch.object(local_files, 'choose', return_value=str(wrong)):
            with self.assertRaisesRegex(ValueError, 'corresponde'):
                self.request('authorize', reference=self.folder_ref)
        with local_files._connection() as con:
            self.assertEqual(con.execute('SELECT path FROM files WHERE uid=? AND reference=?', ('owner', self.folder_ref)).fetchone()[0], str(wrong))
        with self.assertRaises(ValueError): self.prepare()
        self.assertTrue(self.source.exists())

    def test_conflicting_alias_can_reuse_an_exact_path_already_approved_by_same_user(self):
        wrong = self.root / 'Outro projeto'
        wrong.mkdir()
        self.authorize(self.source, 'folder')
        with local_files._connection() as con:
            con.execute('UPDATE files SET path=? WHERE uid=? AND reference=?', (str(wrong), 'owner', self.folder_ref))
        with patch.object(local_files, 'choose') as picker:
            self.assertEqual(Path(self.prepare()['source']), self.source)
            self.assertTrue(self.request('authorize', reference=self.folder_ref)['authorized'])
            picker.assert_not_called()

    def test_move_project_parent_preserves_documents_link_and_all_siblings(self):
        self.folder_ref = self.authorize(self.source / 'Documentos', 'folder')
        root_ref = self.authorize(self.source, 'folder')
        (self.source / 'Proposta.pdf').write_bytes(b'proposal')
        plan = self.request('project-move-prepare', reference=self.folder_ref,
            sourceReference=root_ref, destination=self.destination_ref, excelReference=self.excel_ref)
        self.assertEqual(Path(plan['source']), self.source)
        result = self.request('project-move-commit', operation=plan['operation'])
        target = self.destination / self.source.name
        self.assertEqual((target / 'Proposta.pdf').read_bytes(), b'proposal')
        with local_files._connection() as con:
            folder = project_archive._record(local_files, con, 'owner', result['folderReference'], 'folder')
            excel = project_archive._record(local_files, con, 'owner', result['excelReference'], 'file')
        self.assertEqual(folder, target / 'Documentos')
        self.assertEqual(excel, target / 'Documentos' / 'Projeto.xlsm')
        recovered = self.request('project-move-prepare', reference=self.folder_ref,
            sourceReference=root_ref, destination=self.destination_ref, excelReference=self.excel_ref)
        self.assertTrue(recovered['alreadyMoved'])
        self.assertEqual(self.request('project-move-commit', operation=recovered['operation']), result)

    def test_general_or_unrelated_root_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'imediatamente'):
            self.request('project-move-prepare', reference=self.folder_ref,
                sourceReference=self.authorize(self.root, 'folder'), destination=self.destination_ref)
        self.folder_ref = self.authorize(self.source / 'Documentos', 'folder')
        for path in [self.root, self.destination]:
            with self.assertRaisesRegex(ValueError, 'imediatamente'):
                self.request('project-move-prepare', reference=self.folder_ref,
                    sourceReference=self.authorize(path, 'folder'), destination=self.destination_ref)
        self.assertTrue(self.excel.exists())

    def test_missing_links_can_be_authorized_in_place_then_moved(self):
        with local_files._connection() as con:
            con.execute('DELETE FROM files WHERE uid=?', ('owner',))
        with self.assertRaisesRegex(ValueError, 'Selecione novamente'):
            self.prepare()
        with patch.object(local_files, 'choose', side_effect=[str(self.source), str(self.excel), str(self.destination)]) as picker, patch.object(local_files.os, 'startfile') as opener:
            for ref in [self.folder_ref, self.excel_ref, self.destination_ref]:
                self.assertTrue(self.request('authorize', reference=ref)['authorized'])
            self.assertEqual(picker.call_count, 3)
            opener.assert_not_called()
        with patch.object(local_files, 'choose') as picker:
            self.request('authorize', reference=self.folder_ref)
            picker.assert_not_called()
        plan = self.prepare()
        self.assertTrue(self.source.exists())
        self.assertTrue(self.request('project-move-commit', operation=plan['operation'])['moved'])

    def test_authorize_cancellation_and_wrong_project_never_move(self):
        with local_files._connection() as con:
            con.execute('DELETE FROM files WHERE uid=?', ('owner',))
        with patch.object(local_files, 'choose', return_value=''):
            self.assertTrue(self.request('authorize', reference=self.folder_ref)['cancelled'])
        wrong = self.root / 'Outro projeto' / self.source.name
        wrong.mkdir(parents=True)
        with patch.object(local_files, 'choose', return_value=str(wrong)):
            with self.assertRaisesRegex(ValueError, 'corresponde'):
                self.request('authorize', reference=self.folder_ref)
        with self.assertRaises(ValueError): self.prepare()
        self.assertTrue(self.excel.exists())

    def test_cloud_file_tags_are_not_confused_with_junctions_or_symlinks(self):
        from types import SimpleNamespace
        for variant in range(16):
            self.assertFalse(project_archive._unsafe_reparse(SimpleNamespace(
                st_file_attributes=0x400, st_reparse_tag=0x9000001A | variant << 12)))
        for tag in [0xA0000003, 0xA000000C, 0, 0x9000001C]:
            self.assertTrue(project_archive._unsafe_reparse(SimpleNamespace(
                st_file_attributes=0x400, st_reparse_tag=tag)))

    def test_cloud_metadata_keeps_the_same_tree_fingerprint(self):
        from types import SimpleNamespace
        original = Path.lstat
        before = project_archive._manifest(self.source)
        def cloud(path, *args, **kwargs):
            info = original(path, *args, **kwargs)
            return SimpleNamespace(st_mode=info.st_mode, st_size=info.st_size,
                st_mtime_ns=info.st_mtime_ns, st_file_attributes=0x400, st_reparse_tag=0x9000001A)
        with patch.object(Path, 'lstat', cloud):
            self.assertEqual(project_archive._manifest(self.source), before)

    def test_pending_v23_plan_can_still_be_recovered(self):
        plan = self.prepare()
        plan.pop('manifestVersion')
        plan['manifest'] = project_archive._manifest(self.source, 1)
        with local_files._connection() as con:
            con.execute('UPDATE project_moves SET plan=? WHERE uid=? AND operation=?',
                (json.dumps(plan), 'owner', plan['operation']))
        result = self.request('project-move-commit', operation=plan['operation'])
        self.assertTrue(result['moved'])

    def test_unreadable_subfolder_is_not_silently_ignored(self):
        def unreadable(folder, **kwargs):
            kwargs['onerror'](PermissionError('denied'))
        with patch.object(project_archive.os, 'walk', side_effect=unreadable):
            with self.assertRaisesRegex(ValueError, 'subpasta'):
                self.prepare()
        self.assertTrue(self.excel.exists())

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
