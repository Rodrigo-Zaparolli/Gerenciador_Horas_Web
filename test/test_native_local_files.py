import os
import json
import subprocess
import sys
import sqlite3
import tempfile
import unittest
from contextlib import closing
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import unquote, urlsplit, quote
from pathlib import Path
from unittest.mock import patch

os.environ['EDESK_LOCAL_MODE'] = 'true'
from local_edesk import local_files
from cloud_run.main import app


class LocalFilesTests(unittest.TestCase):
    def test_changed_reference_reuses_exact_authorized_path_without_picker(self):
        for kind, name in [('folder', 'Documentos'), ('file', 'Projeto.xlsx')]:
            path = self.root / name
            path.mkdir() if kind == 'folder' else path.write_bytes(b'workbook')
            old = f'desktop-{kind}://local/owner/12345678-1234-1234-1234-123456789012/' + quote(str(path), safe='')
            fresh = old.replace('123456789012', '123456789013')
            local_files._save('owner', old, path, kind)
            with patch.object(local_files, 'choose') as picker, patch.object(local_files.os, 'startfile') as opener:
                for _ in range(3):
                    result = local_files.execute('owner', {'action': 'open', 'reference': fresh})
                    self.assertEqual(result['reference'], fresh)
                    opener.assert_called_with(str(path.resolve()))
                picker.assert_not_called()

    def test_old_name_only_link_returns_a_durable_full_path(self):
        folder = self.root / 'Orquinare' / 'Documentos'
        folder.mkdir(parents=True)
        old = 'browser-folder://local/owner/12345678-1234-1234-1234-123456789012/Documentos'
        local_files._save('owner', old, folder, 'folder')
        with patch.object(local_files, 'choose') as picker, patch.object(local_files.os, 'startfile'):
            result = local_files.execute('owner', {'action': 'open', 'reference': old})
            self.assertTrue(result['reference'].startswith('desktop-folder://local/owner/'))
            self.assertEqual(unquote(urlsplit(result['reference']).path.split('/')[-1]), str(folder.resolve()))
            local_files.execute('owner', {'action': 'open', 'reference': result['reference']})
            picker.assert_not_called()

    def test_authorization_for_another_account_does_not_recover_a_path(self):
        folder = self.root / 'Documentos'
        folder.mkdir()
        ref = 'desktop-folder://local/owner/12345678-1234-1234-1234-123456789012/' + quote(str(folder), safe='')
        local_files._save('owner', ref, folder, 'folder')
        with patch.object(local_files, 'choose', return_value='') as picker, patch.object(local_files.os, 'startfile') as opener:
            self.assertEqual(local_files.execute('other', {'action': 'open', 'reference': ref.replace('/owner/', '/other/')}), {'cancelled': True})
            picker.assert_called_once()
            opener.assert_not_called()

    def test_full_paths_survive_a_new_python_process_without_reselection(self):
        folder = self.root / 'Documentos'
        folder.mkdir()
        workbook = folder / 'Projeto.xlsx'
        workbook.write_bytes(b'workbook')
        refs = []
        for kind, path in [('folder', folder), ('file', workbook)]:
            with patch.object(local_files, 'choose', return_value=str(path)):
                refs.append(local_files.execute('owner', {'action': 'pick-' + kind})['reference'])
        program = '''
import json, sys
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, sys.argv[1])
from local_edesk import local_files
local_files.LEGACY_DB_PATH = Path(sys.argv[3])
with patch.object(local_files, 'choose', side_effect=AssertionError('Unexpected picker')), patch.object(local_files.os, 'startfile') as opener:
    for reference in json.loads(sys.argv[2]):
        assert local_files.execute('owner', {'action':'open','reference':reference})['opened']
    assert opener.call_count == 2
print('RESTARTED_PATHS_OK')
'''
        env = {**os.environ, 'EDESK_LOCAL_FILES_DB_PATH': str(local_files.DB_PATH)}
        result = subprocess.run([sys.executable, '-I', '-c', program, str(Path(__file__).resolve().parents[1]), json.dumps(refs), str(self.root / 'no-legacy-data.sqlite3')],
            env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('RESTARTED_PATHS_OK', result.stdout)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.db = patch.object(local_files, 'DB_PATH', self.root / 'files.db')
        self.db.start()
        self.legacy = patch.object(local_files, 'LEGACY_DB_PATH', self.root / 'legacy' / 'local-files.sqlite3')
        self.legacy.start()
        self.client = app.test_client()
        self.headers = {'Origin': 'https://gerenciador-horas.web.app', 'Authorization': 'Bearer fake-test-token'}

    def tearDown(self):
        self.legacy.stop()
        self.db.stop()
        self.temp.cleanup()

    def test_original_file_opens_without_copy_and_is_account_scoped(self):
        original = self.root / 'original.xlsx'
        original.write_bytes(b'original unchanged')
        with patch.object(local_files, 'choose', return_value=str(original)), patch.object(local_files.os, 'startfile') as open_file:
            ref = local_files.execute('owner', {'action': 'pick-file'})['reference']
            local_files.execute('owner', {'action': 'open', 'reference': ref})
            open_file.assert_called_once_with(str(original.resolve()))
            self.assertEqual(original.read_bytes(), b'original unchanged')
            with self.assertRaises(ValueError):
                local_files.execute('other', {'action': 'open', 'reference': ref})
            self.assertEqual(local_files.execute('owner', {'action': 'read', 'reference': ref})['base64'], 'b3JpZ2luYWwgdW5jaGFuZ2Vk')

    def test_database_location_is_independent_of_package_extraction(self):
        with patch.dict(os.environ, {'LOCALAPPDATA': str(self.root)}, clear=True):
            self.assertEqual(local_files.database_path(), self.root / 'GerenciadorHoras' / 'integracao' / 'local-files.sqlite3')

    def test_old_links_migrate_and_survive_another_extraction_and_restart(self):
        folder = self.root / 'Orquinare' / 'Documentos'
        folder.mkdir(parents=True)
        workbook = folder / 'Projeto.xlsx'
        workbook.write_bytes(b'original workbook')
        references = [
            'desktop-folder://local/owner/12345678-1234-1234-1234-123456789012/Documentos',
            'desktop-file://local/owner/12345678-1234-1234-1234-123456789013/Projeto.xlsx',
        ]
        legacy = local_files.LEGACY_DB_PATH
        legacy.parent.mkdir()
        with closing(sqlite3.connect(legacy)) as old, old:
            old.execute('CREATE TABLE files(uid TEXT, reference TEXT, path TEXT, kind TEXT, PRIMARY KEY(uid,reference))')
            old.executemany('INSERT INTO files VALUES(?,?,?,?)', [
                ('owner', references[0], str(folder), 'folder'),
                ('owner', references[1], str(workbook), 'file'),
            ])
        with local_files._connection() as con:
            self.assertEqual(con.execute('SELECT COUNT(*) FROM files').fetchone()[0], 2)
        # A new extraction has no private database, but uses the same durable map.
        with patch.object(local_files, 'LEGACY_DB_PATH', self.root / 'new-package' / '.edesk-local' / 'local-files.sqlite3'), \
             patch.object(local_files, 'choose') as picker, patch.object(local_files.os, 'startfile') as opener:
            for ref, path in zip(references, [folder, workbook]):
                local_files.execute('owner', {'action': 'open', 'reference': ref})
                self.assertEqual(opener.call_args.args, (str(path.resolve()),))
            picker.assert_not_called()
        with closing(sqlite3.connect(legacy)) as old, old:
            self.assertEqual(old.execute('SELECT COUNT(*) FROM files').fetchone()[0], 2)

    def test_import_merges_accounts_and_keeps_existing_reference_destinations(self):
        first = self.root / 'first'
        second = self.root / 'second'
        first.mkdir()
        second.mkdir()
        ref = 'desktop-folder://local/owner/12345678-1234-1234-1234-123456789012/Documentos'
        local_files._save('owner', ref, first, 'folder')
        source = self.root / 'other-extraction.sqlite3'
        with closing(sqlite3.connect(source)) as old, old:
            old.execute('CREATE TABLE files(uid TEXT, reference TEXT, path TEXT, kind TEXT, PRIMARY KEY(uid,reference))')
            old.executemany('INSERT INTO files VALUES(?,?,?,?)', [
                ('owner', ref, str(second), 'folder'),
                ('other', ref.replace('/owner/', '/other/'), str(second), 'folder'),
            ])
        local_files.import_authorizations(source)
        local_files.import_authorizations(source)
        with local_files._connection() as con:
            self.assertEqual(con.execute('SELECT COUNT(*) FROM files').fetchone()[0], 2)
            self.assertEqual(con.execute('SELECT path FROM files WHERE uid=?', ('owner',)).fetchone()[0], str(first))
            self.assertEqual(con.execute('SELECT path FROM files WHERE uid=?', ('other',)).fetchone()[0], str(second))

    def test_simultaneous_first_opens_import_legacy_only_once(self):
        legacy = local_files.LEGACY_DB_PATH
        legacy.parent.mkdir()
        with closing(sqlite3.connect(legacy)) as old, old:
            old.execute('CREATE TABLE files(uid TEXT,reference TEXT,path TEXT,kind TEXT,PRIMARY KEY(uid,reference))')
            old.execute('INSERT INTO files VALUES(?,?,?,?)', ('owner', 'reference', str(self.root), 'folder'))
        def open_database(_):
            with local_files._connection() as con:
                return con.execute('SELECT COUNT(*) FROM files').fetchone()[0]
        with ThreadPoolExecutor(max_workers=6) as pool:
            self.assertEqual(list(pool.map(open_database, range(12))), [1] * 12)
        with local_files._connection() as con:
            self.assertEqual(con.execute('SELECT COUNT(*) FROM imported_file_databases').fetchone()[0], 1)

    def test_old_browser_reference_is_linked_once_and_opens_folder(self):
        folder = self.root / 'Projeto'
        folder.mkdir()
        ref = 'browser-folder://local/owner/12345678-1234-1234-1234-123456789012/Projeto'
        with patch.object(local_files, 'choose', return_value=str(folder)) as chooser, patch.object(local_files.os, 'startfile') as opener:
            local_files.execute('owner', {'action': 'open', 'reference': ref})
            local_files.execute('owner', {'action': 'open', 'reference': ref})
            self.assertEqual(chooser.call_count, 1)
            self.assertEqual(opener.call_count, 2)
            opener.assert_called_with(str(folder.resolve()))

    def test_unregistered_path_and_executable_are_rejected(self):
        executable = self.root / 'test.exe'
        executable.write_bytes(b'test')
        with patch.object(local_files, 'choose', return_value=str(executable)), patch.object(local_files.os, 'startfile') as opener:
            with self.assertRaises(ValueError):
                local_files.execute('owner', {'action': 'pick-file'})
            with self.assertRaises(ValueError):
                local_files.execute('owner', {'action': 'open', 'reference': str(executable)})
            opener.assert_not_called()

    def test_legacy_path_needs_native_selection_and_cancel_opens_nothing(self):
        original = self.root / 'Projeto.xlsx'
        original.write_bytes(b'test')
        with patch.object(local_files, 'choose', return_value=''), patch.object(local_files.os, 'startfile') as opener:
            self.assertEqual(local_files.execute('owner', {'action':'open', 'reference':r'C:\antiga\Projeto.xlsx'}), {'cancelled':True})
            opener.assert_not_called()
        with patch.object(local_files, 'choose', return_value=str(original)), patch.object(local_files.os, 'startfile') as opener:
            with self.assertRaises(ValueError):
                local_files.execute('owner', {'action':'open', 'reference':r'C:\antiga\Projeto.xlsx'})
            opener.assert_not_called()
            local_files.execute('owner', {'action':'open', 'reference':str(original.resolve())})
            opener.assert_called_once_with(str(original.resolve()))

    def test_same_named_project_folders_and_workbooks_stay_separate_after_reload(self):
        for kind, action, name in [('folder', 'pick-folder', 'Documentos'), ('file', 'pick-file', 'Projeto.xlsx')]:
            paths, refs = [], []
            for client in ['Orquinare', 'Sin Moveis']:
                parent = self.root / kind / client
                parent.mkdir(parents=True)
                path = parent / name
                if kind == 'folder':
                    path.mkdir()
                else:
                    path.write_bytes(client.encode())
                paths.append(path.resolve())
                with patch.object(local_files, 'choose', return_value=str(path)):
                    ref = local_files.execute('owner', {'action': action})['reference']
                self.assertEqual(unquote(urlsplit(ref).path.split('/')[-1]), str(path.resolve()))
                refs.append(ref)
            self.assertNotEqual(*refs)
            # Every execute reopens SQLite, as happens after a helper restart.
            with patch.object(local_files, 'choose') as chooser, patch.object(local_files.os, 'startfile') as opener:
                for index in [0, 1, 0, 1]:
                    local_files.execute('owner', {'action': 'open', 'reference': refs[index]})
                    self.assertEqual(opener.call_args.args, (str(paths[index]),))
                chooser.assert_not_called()

    def test_existing_reference_cannot_be_rebound_to_another_same_named_folder(self):
        first, second = self.root / 'Orquinare' / 'Documentos', self.root / 'Sin' / 'Documentos'
        first.mkdir(parents=True)
        second.mkdir(parents=True)
        ref = 'desktop-folder://local/owner/12345678-1234-1234-1234-123456789012/Documentos'
        local_files._save('owner', ref, first, 'folder')
        with self.assertRaises(ValueError):
            local_files._save('owner', ref, second, 'folder')
        with patch.object(local_files.os, 'startfile') as opener:
            local_files.execute('owner', {'action': 'open', 'reference': ref})
            opener.assert_called_once_with(str(first.resolve()))

    def test_full_path_recovery_rejects_another_same_named_folder(self):
        first, second = self.root / 'Orquinare' / 'Documentos', self.root / 'Sin' / 'Documentos'
        first.mkdir(parents=True)
        second.mkdir(parents=True)
        ref = 'desktop-folder://local/owner/12345678-1234-1234-1234-123456789012/' + quote(str(first.resolve()), safe='')
        with patch.object(local_files, 'choose', return_value=str(second)), patch.object(local_files.os, 'startfile') as opener:
            with self.assertRaises(ValueError):
                local_files.execute('owner', {'action': 'open', 'reference': ref})
            opener.assert_not_called()
        with patch.object(local_files, 'choose', return_value=str(first)), patch.object(local_files.os, 'startfile') as opener:
            local_files.execute('owner', {'action': 'open', 'reference': ref})
            opener.assert_called_once_with(str(first.resolve()))

    def test_preview_uses_only_the_account_approved_workbook(self):
        original = self.root / 'trabalho.xlsx'
        original.write_bytes(b'test')
        with patch.object(local_files, 'choose', return_value=str(original)):
            ref = local_files.execute('owner', {'action':'pick-file'})['reference']
        with patch('local_edesk.excel_mirror.render', return_value={'imagemBase64':'test','renderer':'excel'}) as render:
            result = local_files.execute('owner', {'action':'preview','reference':ref,'range':'Dados!A1:L8'})
            self.assertEqual(result['renderer'],'excel')
            render.assert_called_once_with(original.resolve(),'Dados!A1:L8')
            with self.assertRaises(ValueError):
                local_files.execute('other', {'action':'preview','reference':ref,'range':'Dados!A1:L8'})

    def test_health_reports_the_actions_used_by_the_loaded_module(self):
        result = self.client.get('/healthz')
        self.assertEqual(result.json['nativeFilesVersion'], local_files.PROTOCOL_VERSION)
        self.assertEqual(set(result.json['nativeActions']), local_files.SUPPORTED_ACTIONS)
        self.assertTrue(result.json['excelMirror'])
        with patch.object(local_files, 'SUPPORTED_ACTIONS', frozenset({'open'})):
            self.assertFalse(self.client.get('/healthz').json['excelMirror'])

    def test_preview_http_request_reaches_renderer_with_the_selected_range(self):
        original = self.root / 'trabalho.xlsx'
        original.write_bytes(b'test workbook unchanged')
        with patch.object(local_files, 'choose', return_value=str(original)):
            reference = local_files.execute('owner', {'action': 'pick-file'})['reference']
        with patch('local_edesk.authentication.verify_token', return_value={'sub': 'owner'}), \
             patch('local_edesk.excel_mirror.render', return_value={'renderer': 'excel', 'imagemBase64': 'test-image'}) as render:
            result = self.client.post('/api/local-files', headers=self.headers,
                json={'action': 'preview', 'reference': reference, 'range': 'Dados!A1:L8'})
            self.assertEqual(result.status_code, 200)
            self.assertEqual(result.json, {'renderer': 'excel', 'imagemBase64': 'test-image', 'reference': reference})
            render.assert_called_once_with(original.resolve(), 'Dados!A1:L8')
        self.assertEqual(original.read_bytes(), b'test workbook unchanged')

    def test_endpoint_requires_loopback_origin_and_authentication(self):
        for headers, address, host in [({}, '127.0.0.1', 'localhost'),
            ({'Origin':'https://gerenciador-horas.web.app'},'127.0.0.1','localhost'),
            (self.headers,'192.168.1.2','localhost'),
            (self.headers,'127.0.0.1','192.168.1.2'),
            ({**self.headers,'Origin':'https://evil.invalid'},'127.0.0.1','localhost')]:
            result = self.client.post('/api/local-files', json={'action':'open'}, headers=headers,
                environ_overrides={'REMOTE_ADDR':address}, base_url=f'http://{host}')
            self.assertIn(result.status_code, [401,403])
        with patch('local_edesk.authentication.verify_token', return_value={'sub':'owner'}), patch.object(local_files,'execute', return_value={'opened':True}) as execute:
            result = self.client.post('/api/local-files', json={'action':'open','reference':'test'}, headers=self.headers)
            self.assertEqual(result.status_code,200)
            execute.assert_called_once_with('owner', {'action':'open','reference':'test'}, verified_user={'sub': 'owner'})


if __name__ == '__main__':
    unittest.main()
