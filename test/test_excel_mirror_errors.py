import unittest
from pathlib import Path
from unittest.mock import patch
from local_edesk.excel_mirror import render


class MirrorErrorsTests(unittest.TestCase):
    def test_legacy_professional_name_resolves_maker_only_when_original_is_missing(self):
        from edesk_bot.excel_preview import resolver_nome_aba
        self.assertEqual(resolver_nome_aba('Professional Checklist-Processo', ['Dados','Maker CheckList-Processo']), 'Maker CheckList-Processo')
        self.assertEqual(resolver_nome_aba('Professional Checklist-Processo', ['Professional Checklist-Processo','Maker Checklist-Processo']), 'Professional Checklist-Processo')
        for requested, names in [('Checklist-Processo',['Maker Checklist-Processo']), ('Professional Checklist-Processo',['Checklist-Processo']), ('Outra',['Maker Checklist-Processo'])]:
            with self.subTest(requested=requested), self.assertRaises(ValueError):
                resolver_nome_aba(requested,names)

    def test_missing_sheet_message_keeps_actual_names(self):
        message = "Aba 'Professional' não encontrada. Abas disponíveis: Professional Checklist-Processo, Dados"
        with patch('local_edesk.excel_mirror.renderizar_intervalo_excel', side_effect=ValueError(message)):
            with self.assertRaisesRegex(ValueError, 'Abas disponíveis: Professional Checklist-Processo'):
                render(Path('fixture.xlsm'), 'Professional!A1:D3')

    def test_excel_startup_file_and_capture_messages_are_preserved(self):
        for message in ['Não foi possível iniciar o Microsoft Excel.', 'O Excel iniciou, mas não conseguiu abrir a planilha.', 'Falha ao capturar imagem do Clipboard.']:
            with self.subTest(message=message), patch('local_edesk.excel_mirror.renderizar_intervalo_excel', side_effect=RuntimeError(message)):
                with self.assertRaises(ValueError) as raised:
                    render(Path('fixture.xlsm'), 'Dados!A1:D3')
                self.assertEqual(str(raised.exception),message)

    def test_unexpected_error_does_not_claim_excel_is_missing_and_unlocks(self):
        with patch('local_edesk.excel_mirror.renderizar_intervalo_excel', side_effect=OSError('clipboard unavailable')), self.assertLogs('local_edesk.excel_mirror'):
            with self.assertRaises(ValueError) as raised:
                render(Path('fixture.xlsm'), 'Dados!A1:D3')
        self.assertNotIn('instalado',str(raised.exception))
        with patch('local_edesk.excel_mirror.renderizar_intervalo_excel', return_value=('image','Dados')):
            self.assertEqual(render(Path('fixture.xlsm'), 'Dados!A1:D3')['imagemBase64'],'image')

    def test_invalid_range_never_starts_excel(self):
        with patch('local_edesk.excel_mirror.renderizar_intervalo_excel') as renderer:
            with self.assertRaises(ValueError):
                render(Path('fixture.xlsm'), 'Dados!A0:D3')
            renderer.assert_not_called()


if __name__ == '__main__':
    unittest.main()
