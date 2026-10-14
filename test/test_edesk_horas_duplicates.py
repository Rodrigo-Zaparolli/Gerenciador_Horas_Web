import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'edesk_bot'))
from edesk_horas import fechar_solicitacoes_duplicadas


class Page:
    def __init__(self, url):
        self.url = url
        self.closed = False

    def is_closed(self):
        return self.closed

    def close(self):
        self.closed = True


class DuplicateRequestsTest(unittest.TestCase):
    def test_only_new_identical_request_is_closed(self):
        url = 'https://promob.e-desk.com.br/Portal/Solicitacao.aspx?solicitacao=encoded'
        grid = Page('https://promob.e-desk.com.br/Portal/ListaSolicitacao.aspx')
        old = Page(url)
        selected, duplicate = Page(url), Page(url)
        other = Page(url + '-other')
        work = Page('https://promob.e-desk.com.br/Portal/Trabalho.aspx')
        pages = [grid, old, selected, duplicate, other, work]
        fechar_solicitacoes_duplicadas(
            SimpleNamespace(pages=pages), selected, grid,
            {id(grid): grid.url, id(old): old.url},
        )
        self.assertTrue(duplicate.closed)
        for page in [grid, old, selected, other, work]:
            self.assertFalse(page.closed)


if __name__ == '__main__':
    unittest.main()
