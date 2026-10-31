import io
import os
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'edesk_bot'))
from operation_log import emit_log
from local_edesk.diagnostics import file_failure
from local_edesk.excel_editor import snapshot, SheetReadError


class OperationDiagnosticsTests(unittest.TestCase):
    def test_busy_permission_missing_and_unknown_have_distinct_codes(self):
        for error, code in [
            (ValueError('Aguarde a leitura ou grava\u00e7\u00e3o da planilha em andamento.'), 'excel_busy'),
            (PermissionError('Acesso negado'), 'file_permission'),
            (FileNotFoundError('private path'), 'file_missing'),
        ]:
            self.assertEqual(file_failure(error)[0]['errorCode'], code)
        with self.assertLogs('local_edesk.diagnostics') as records:
            payload, status = file_failure(RuntimeError('password=secret'), 'excel-editor-read')
        self.assertEqual(status, 500)
        self.assertEqual(payload['errorCode'], 'excel_operation_failed')
        self.assertIn(payload['diagnosticId'], records.output[0])
        self.assertNotIn('secret', str(payload) + str(records.output))

    def test_missing_sheet_and_failed_cell_read_are_not_conflated(self):
        book = SimpleNamespace(Worksheets=Mock(side_effect=RuntimeError('missing')))
        with self.assertRaises(SheetReadError) as raised:
            snapshot(book)
        self.assertEqual(raised.exception.code, 'excel_sheet_unavailable')
        book = SimpleNamespace(Worksheets=Mock(return_value=object()))
        with patch('local_edesk.excel_editor.SheetSnapshot', side_effect=RuntimeError('COM busy')):
            with self.assertRaises(SheetReadError) as raised:
                snapshot(book)
        self.assertEqual(raised.exception.code, 'excel_read_failed')
        self.assertNotIn('Configurar abas', str(raised.exception))

    def test_log_filter_preserves_repeated_receipts_and_debug(self):
        stream = io.StringIO()
        with patch.dict(os.environ, {'EDESK_LOG_LEVEL': 'INFO'}), redirect_stdout(stream):
            for text in ['', '=====', 'Hora confirmada', 'Hora confirmada']:
                emit_log(text, 'test')
        self.assertEqual(stream.getvalue().count('Hora confirmada'), 2)
        self.assertNotIn('=====', stream.getvalue())
        with patch.dict(os.environ, {'EDESK_LOG_LEVEL': 'DEBUG'}), redirect_stdout(stream):
            emit_log('=====', 'test')
        self.assertIn('=====', stream.getvalue())


if __name__ == '__main__':
    unittest.main()
