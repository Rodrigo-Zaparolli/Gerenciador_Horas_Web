import asyncio
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'edesk_bot'))
from phase_confirmation import mismatched_phases, close_new_duplicate_requests
import send_progress

class PhaseConfirmationTest(unittest.TestCase):
    def test_only_reloaded_matching_dates_are_confirmed(self):
        expected = [{'nome': 'Implantação', 'dataInicial': '01/10/2026', 'dataFinal': '14/10/2026'}]
        self.assertEqual(mismatched_phases(expected, expected), [])
        self.assertTrue(mismatched_phases(expected, [{**expected[0], 'dataFinal': '10/10/2026'}]))
        self.assertTrue(mismatched_phases(expected, []))
        self.assertTrue(mismatched_phases(expected, expected + expected))

    def test_only_new_duplicate_tabs_are_closed(self):
        class Page:
            url = 'https://promob.e-desk.com.br/Portal/Solicitacao.aspx?id=abc'
            closed = False
            def is_closed(self): return self.closed
            async def close(self): self.closed = True
        selected, duplicate, original = Page(), Page(), Page()
        class Context: pages = [selected, duplicate, original]
        asyncio.run(close_new_duplicate_requests(Context(), selected, [original]))
        self.assertTrue(duplicate.closed)
        self.assertFalse(selected.closed)
        self.assertFalse(original.closed)

    def test_confirmed_progress_survives_stage_changes_and_deduplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'progress.json'
            with patch.dict(os.environ, EDESK_PROGRESS_FILE=str(target), EDESK_PROGRESS_TOTAL='3'):
                send_progress._completed.clear()
                send_progress.completed('first')
                send_progress.completed('first')
                send_progress.stage('preparing')
                data = json.loads(target.read_text())
                self.assertEqual(data['completed'], 1)
                self.assertEqual(data['total'], 3)
                self.assertEqual(data['stage'], 'preparing')
                send_progress._completed.clear()

if __name__ == '__main__': unittest.main()
