import unittest
from unittest.mock import patch
from local_edesk import beta_voice

class BetaVoiceTests(unittest.TestCase):
    def test_only_pilot_account(self):
        self.assertTrue(beta_voice.allowed({'sub':'owner','email':beta_voice.OWNER_EMAIL}))
        self.assertFalse(beta_voice.allowed({'sub':'other','email':'other@example.com'}))
        self.assertFalse(beta_voice.allowed({'email':beta_voice.OWNER_EMAIL}))
    def test_missing_runtime_is_reported_without_downloading(self):
        with patch.object(beta_voice,'ready',return_value=False):
            self.assertFalse(beta_voice.execute({'action':'status'})['ready'])
            with self.assertRaises(RuntimeError):beta_voice.execute({'action':'speech','text':'Olá'})
    def test_invalid_action(self):
        for body in [None,[],{'action':'send-hours'}]:
            with self.assertRaises(ValueError):beta_voice.execute(body)

if __name__=='__main__':unittest.main()
