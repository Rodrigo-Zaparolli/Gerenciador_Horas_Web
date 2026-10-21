import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "edesk_bot"))
from edesk_horas import acrescentar_trabalho_realizado


class TrabalhoRealizadoTest(unittest.TestCase):
    def test_retry_preserves_history_when_later_hours_already_appended(self):
        history = '21/10/2026: - First\n21/10/2026: - Second'
        self.assertEqual(
            acrescentar_trabalho_realizado(history, history, '21/10/2026', 'First', retry=True),
            history,
        )

    def test_preserva_historico_exatamente_e_acrescenta_abaixo(self):
        anterior = "07/10/2026: - Dúvidas configurador + ajustes construtor\n08/10/2026: - Planilha acabamentos  "
        resultado = acrescentar_trabalho_realizado(
            anterior, anterior, "09/10/2026", "Revisão\nComplemento"
        )
        self.assertEqual(resultado, anterior + "\n09/10/2026: - Revisão\nComplemento")

    def test_postback_vazio_preserva_snapshot(self):
        self.assertEqual(
            acrescentar_trabalho_realizado("Histórico\n", "", "08/10/2026", "Novo"),
            "Histórico\n08/10/2026: - Novo",
        )

    def test_campo_vazio_e_envios_sequenciais(self):
        primeiro = acrescentar_trabalho_realizado("", "", "08/10/2026", "Primeiro")
        segundo = acrescentar_trabalho_realizado(primeiro, primeiro, "08/10/2026", "Segundo")
        self.assertEqual(segundo, "08/10/2026: - Primeiro\n08/10/2026: - Segundo")

    def test_preserva_acrescimo_do_postback(self):
        self.assertEqual(
            acrescentar_trabalho_realizado("Histórico", "Histórico\nOutro", "08/10/2026", "Novo"),
            "Histórico\nOutro\n08/10/2026: - Novo",
        )

    def test_interrompe_se_historico_foi_substituido(self):
        with self.assertRaisesRegex(RuntimeError, "preservar"):
            acrescentar_trabalho_realizado("Histórico", "Texto diferente", "08/10/2026", "Novo")


if __name__ == "__main__":
    unittest.main()
