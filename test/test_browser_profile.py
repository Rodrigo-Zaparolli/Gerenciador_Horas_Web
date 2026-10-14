import os
os.environ['EDESK_LOCAL_MODE'] = 'true'
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from cloud_run import main

class BrowserProfileTest(unittest.TestCase):
    def test_profiles_reuse_session_but_isolate_account_and_edesk_identity(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(main, 'APP_ROOT', Path(temporary)):
            first = main._local_browser_profile('account-a', {'edeskCredenciais': {'email': 'a@example.test'}})
            self.assertEqual(first, main._local_browser_profile('account-a', {'edeskCredenciais': {'email': ' A@EXAMPLE.TEST '}}))
            self.assertNotEqual(first, main._local_browser_profile('account-b', {'edeskCredenciais': {'email': 'a@example.test'}}))
            self.assertNotEqual(first, main._local_browser_profile('account-a', {'edeskCredenciais': {'email': 'b@example.test'}}))
            self.assertTrue(Path(first).is_dir())
            self.assertTrue(Path(first).resolve().is_relative_to(Path(temporary).resolve()))
            self.assertNotIn('example.test', first)

    def test_session_cookies_survive_browser_restart_without_exporting_credentials(self):
        import runpy
        from types import SimpleNamespace
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {'EDESK_PROFILE_DIR': temporary}):
            config = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'edesk_bot/config.py'))
            cookies = [{'name': 'session', 'value': 'test-fixture', 'domain': 'example.test', 'path': '/'}]
            config['save_session_cookies'](SimpleNamespace(cookies=lambda: cookies))
            restored = []
            config['restore_session_cookies'](SimpleNamespace(add_cookies=lambda value: restored.extend(value)))
            self.assertEqual(cookies, restored)
            config['save_session_cookies'](SimpleNamespace(cookies=lambda: []))
            restored.clear()
            config['restore_session_cookies'](SimpleNamespace(add_cookies=lambda value: restored.extend(value)))
            self.assertEqual(restored, [])
