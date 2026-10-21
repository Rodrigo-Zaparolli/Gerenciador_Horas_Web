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
    def test_failed_move_with_empty_destination_can_be_prepared_and_confirmed_again(self):
        target = self.destination / self.source.name
        target.mkdir()
        plan = self.prepare()
        original = Path.rmdir
        def locked(path):
            if path == target:
                raise PermissionError('destination temporarily locked')
            return original(path)
        with patch.object(Path, 'rmdir', locked):
            with self.assertRaises(ValueError):
                self.request('project-move-commit', operation=plan['operation'])
        renewed = self.prepare()
        self.assertNotEqual(renewed['operation'], plan['operation'])
        self.assertTrue(self.excel.exists())
        self.assertTrue(target.is_dir())
        result = self.request('project-move-commit', operation=renewed['operation'])
        self.assertTrue(result['contentsVerified'])
        self.assertFalse(self.source.exists())
        self.assertEqual((target / 'Documentos' / self.excel.name).read_bytes(), b'workbook-and-macros')

    def test_retry_never_discards_nonempty_destination_after_failed_move(self):
        plan = self.prepare()
        with patch.object(project_archive.os, 'rename', side_effect=PermissionError('locked')):
            with self.assertRaises(ValueError):
                self.request('project-move-commit', operation=plan['operation'])
        target = self.destination / self.source.name
        target.mkdir()
        (target / 'preserve.txt').write_bytes(b'do not delete')
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertEqual((target / 'preserve.txt').read_bytes(), b'do not delete')
        self.assertTrue(self.excel.exists())

    def test_selecting_whole_project_replaces_failed_documents_only_plan(self):
        root_reference = self.folder_ref
        self.folder_ref = self.authorize(self.source / 'Documentos', 'folder')
        (self.source / 'Proposta.pdf').write_bytes(b'proposal')
        previous = self.prepare()
        with patch.object(project_archive.os, 'rename', side_effect=PermissionError('locked')):
            with self.assertRaises(ValueError):
                self.request('project-move-commit', operation=previous['operation'])
        plan = self.request('project-move-prepare', reference=self.folder_ref,
            sourceReference=root_reference, destination=self.destination_ref, excelReference=self.excel_ref)
        self.assertEqual(Path(plan['source']), self.source)
        self.assertNotEqual(plan['operation'], previous['operation'])
        with self.assertRaisesRegex(ValueError, 'substituído'):
            self.request('project-move-commit', operation=previous['operation'])
        result = self.request('project-move-commit', operation=plan['operation'])
        self.assertFalse(self.source.exists())
        self.assertEqual((Path(result['target']) / 'Proposta.pdf').read_bytes(), b'proposal')
        self.assertEqual((Path(result['target']) / 'Documentos' / self.excel.name).read_bytes(), b'workbook-and-macros')

    def test_recovery_finds_matching_destination_before_latest_other_destination(self):
        first = self.prepare()
        with patch.object(project_archive.os, 'rename', side_effect=PermissionError('locked')):
            with self.assertRaises(ValueError):
                self.request('project-move-commit', operation=first['operation'])
        original_destination = self.destination_ref
        other = self.root / 'Outro destino'
        other.mkdir()
        self.destination_ref = self.authorize(other, 'folder')
        second = self.prepare()
        with patch.object(project_archive.os, 'rename', side_effect=PermissionError('locked')):
            with self.assertRaises(ValueError):
                self.request('project-move-commit', operation=second['operation'])
        self.destination_ref = original_destination
        self.assertEqual(self.prepare()['operation'], first['operation'])

    def test_previous_completed_move_recovers_with_visible_file_count_without_moving_again(self):
        plan = self.prepare()
        result = self.request('project-move-commit', operation=plan['operation'])
        for key in ('fileCount', 'directoryCount', 'totalBytes', 'projectFileCount', 'sampleFiles', 'projectManifest', 'folderIdentity', 'emptyTargetIdentity'):
            plan.pop(key, None)
        result.pop('contentsVerified')
        result.pop('sourceRemoved')
        with local_files._connection() as con:
            con.execute('UPDATE project_moves SET plan=?,result=? WHERE operation=?',
                        (json.dumps(plan), json.dumps(result), plan['operation']))
        recovered = self.prepare()
        self.assertEqual(recovered['fileCount'], 1)
        self.assertTrue(recovered['alreadyMoved'])
        with patch.object(project_archive.os, 'rename', side_effect=AssertionError('must not move again')):
            confirmed = self.request('project-move-commit', operation=plan['operation'])
        self.assertTrue(confirmed['contentsVerified'])
        self.assertTrue(confirmed['sourceRemoved'])

    def test_confirmed_empty_destination_is_replaced_by_entire_original_folder(self):
        target = self.destination / self.source.name
        target.mkdir()
        (self.source / 'Proposta.pdf').write_bytes(b'proposal')
        plan = self.prepare()
        self.assertIsNotNone(plan['emptyTargetIdentity'])
        self.assertTrue(target.exists())
        self.assertTrue(self.excel.exists())
        result = self.request('project-move-commit', operation=plan['operation'])
        self.assertTrue(result['contentsVerified'])
        self.assertFalse(self.source.exists())
        self.assertEqual((target / 'Proposta.pdf').read_bytes(), b'proposal')
        self.assertEqual((target / 'Documentos' / self.excel.name).read_bytes(), b'workbook-and-macros')

    def test_empty_destination_that_gains_any_file_cannot_be_replaced(self):
        target = self.destination / self.source.name
        target.mkdir()
        plan = self.prepare()
        (target / '.oculto.txt').write_bytes(b'preserve')
        with self.assertRaises(ValueError):
            self.request('project-move-commit', operation=plan['operation'])
        self.assertEqual((target / '.oculto.txt').read_bytes(), b'preserve')
        self.assertTrue(self.excel.exists())

    def test_moves_entire_nonempty_tree_without_copying_and_reports_contents(self):
        import shutil
        nested = self.source / 'Outros' / 'Subpasta'
        nested.mkdir(parents=True)
        (self.source / '.oculto.txt').write_bytes(b'hidden')
        (nested / 'Proposta.pdf').write_bytes(b'proposal')
        (nested / 'Anotacao.txt').write_bytes(b'notes')
        expected = {p.relative_to(self.source): p.read_bytes() for p in self.source.rglob('*') if p.is_file()}
        identity = project_archive._folder_identity(self.source)
        plan = self.prepare()
        self.assertEqual(plan['fileCount'], len(expected))
        self.assertEqual(plan['directoryCount'], 3)
        self.assertEqual(plan['totalBytes'], sum(map(len, expected.values())))
        with patch.object(shutil, 'copytree', side_effect=AssertionError('must not copy')), patch.object(shutil, 'copy2', side_effect=AssertionError('must not copy')):
            result = self.request('project-move-commit', operation=plan['operation'])
        target = Path(result['target'])
        self.assertFalse(self.source.exists())
        self.assertEqual(project_archive._folder_identity(target), identity)
        self.assertEqual({p.relative_to(target): p.read_bytes() for p in target.rglob('*') if p.is_file()}, expected)
        self.assertTrue(result['contentsVerified'])
        self.assertTrue(result['sourceRemoved'])

    def test_empty_or_backup_only_source_is_not_confirmed(self):
        self.excel.unlink()
        self.excel_ref = ''
        with self.assertRaisesRegex(ValueError, 'não contém arquivos'):
            self.prepare()
        backup = self.source / '.gerenciador-backups'
        backup.mkdir()
        (backup / 'Cliente-20261020-120000-abcdef12.xlsm').write_bytes(b'backup')
        with self.assertRaisesRegex(ValueError, 'não contém arquivos'):
            self.prepare()
        self.assertTrue(self.source.exists())
        self.assertFalse((self.destination / self.source.name).exists())

    def test_empty_destination_never_updates_links_or_cleans_backups(self):
        plan = self.prepare()
        rename = os.rename
        def simulate_missing_contents(source, target):
            rename(source, target)
            (target / 'Documentos' / self.excel.name).unlink()
        with patch.object(project_archive.os, 'rename', side_effect=simulate_missing_contents), patch('local_edesk.backup_policy.remove_archived_backups') as cleanup:
            with self.assertRaisesRegex(ValueError, 'conferir o destino'):
                self.request('project-move-commit', operation=plan['operation'])
            cleanup.assert_not_called()
        with local_files._connection() as con:
            self.assertEqual(con.execute('SELECT state FROM project_moves WHERE operation=?', (plan['operation'],)).fetchone()[0], 'moving')

    def test_copy_left_at_source_is_not_reported_as_a_move(self):
        import shutil
        plan = self.prepare()
        with patch.object(project_archive.os, 'rename', side_effect=lambda source, target: shutil.copytree(source, target)), patch('local_edesk.backup_policy.remove_archived_backups') as cleanup:
            with self.assertRaisesRegex(ValueError, 'ainda existe na origem'):
                self.request('project-move-commit', operation=plan['operation'])
            cleanup.assert_not_called()
        self.assertTrue(self.excel.exists())

    def test_missing_file_after_move_cannot_recover_as_success(self):
        (self.source / 'Proposta.pdf').write_bytes(b'proposal')
        plan = self.prepare()
        result = self.request('project-move-commit', operation=plan['operation'])
        (Path(result['target']) / 'Proposta.pdf').unlink()
        with self.assertRaisesRegex(ValueError, 'conteúdo no destino mudou'):
            self.request('project-move-commit', operation=plan['operation'])

    def test_backups_removed_only_after_verified_move_and_recovery_is_idempotent(self):
        backup = self.excel.parent / '.gerenciador-backups'
        backup.mkdir()
        (backup / 'Cliente-20261020-120000-abcdef12.xlsm').write_bytes(b'backup')
        plan = self.prepare()
        self.assertTrue(backup.exists())
        with patch.object(project_archive.os, 'rename', side_effect=PermissionError('locked')):
            with self.assertRaises(ValueError):
                self.request('project-move-commit', operation=plan['operation'])
        self.assertTrue(backup.exists())
        result = self.request('project-move-commit', operation=plan['operation'])
        self.assertTrue(result['backupCleanup']['complete'])
        self.assertEqual(result['backupCleanup']['removed'], 1)
        self.assertFalse((Path(result['target']) / backup.relative_to(self.source)).exists())
        with patch.object(project_archive.os, 'rename', side_effect=AssertionError('must not move twice')):
            self.assertEqual(self.request('project-move-commit', operation=plan['operation']), result)

    def test_interrupted_cleanup_retries_without_moving_again(self):
        backup = self.excel.parent / '.gerenciador-backups'
        backup.mkdir()
        (backup / 'Cliente-20261020-120000-abcdef12.xlsm').write_bytes(b'backup')
        plan = self.prepare()
        with patch('local_edesk.backup_policy.remove_archived_backups', side_effect=OSError('interrupted')):
            result = self.request('project-move-commit', operation=plan['operation'])
        self.assertTrue(result['moved'])
        self.assertFalse(result['backupCleanup']['complete'])
        with patch.object(project_archive.os, 'rename', side_effect=AssertionError('must not move twice')):
            recovered = self.request('project-move-commit', operation=plan['operation'])
        self.assertTrue(recovered['backupCleanup']['complete'])

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
        collision = self.destination / self.source.name
        collision.mkdir()
        (collision / 'Nao substituir.txt').write_bytes(b'keep')
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
