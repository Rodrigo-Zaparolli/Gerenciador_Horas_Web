import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ['EDESK_LOCAL_MODE'] = 'true'
from local_edesk import local_files
from cloud_run.main import app


class LocalFilesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.db = patch.object(local_files, 'DB_PATH', self.root / 'files.db')
        self.db.start()
        self.client = app.test_client()
        self.headers = {'Origin': 'https://gerenciador-horas.web.app', 'Authorization': 'Bearer fake-test-token'}

    def tearDown(self):
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
            local_files.execute('owner', {'action':'open', 'reference':r'C:\antiga\Projeto.xlsx'})
            opener.assert_called_once_with(str(original.resolve()))

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
            self.assertEqual(result.json, {'renderer': 'excel', 'imagemBase64': 'test-image'})
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
            execute.assert_called_once_with('owner', {'action':'open','reference':'test'})


if __name__ == '__main__':
    unittest.main()
