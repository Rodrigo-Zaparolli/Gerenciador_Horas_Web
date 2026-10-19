import sys
import unittest
from pathlib import Path
from decimal import Decimal
from urllib.parse import parse_qs
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'edesk_bot'))
from comment_percentage import (parse_percentage, percentage_field,
                                save_work_percentage, save_comment_then_percentage)
from playwright.sync_api import sync_playwright


class PercentageTests(unittest.TestCase):
    def test_values(self):
        self.assertIsNone(parse_percentage(''))
        self.assertIsNone(parse_percentage(None))
        for value in [0, 100, '25,50', 0.25]:
            self.assertEqual(parse_percentage(value), Decimal(str(value).replace(',', '.')))
        for value in [True, -1, 101, 'NaN', 'Infinity', 'bad', '0.001']:
            with self.assertRaises(ValueError):
                parse_percentage(value)

    def test_order_and_no_percentage_after_comment_failure(self):
        events = []
        save_comment_then_percentage(lambda: events.append('comment'), lambda: events.append('percent'))
        self.assertEqual(events, ['comment', 'percent'])
        percent = Mock()
        with self.assertRaises(RuntimeError):
            save_comment_then_percentage(Mock(side_effect=RuntimeError('comment failed')), percent)
        percent.assert_not_called()

    def test_partial_failure_never_repeats_comment(self):
        comment, percent = Mock(), Mock(side_effect=RuntimeError('not saved'))
        with self.assertRaisesRegex(RuntimeError, 'EDESK_PERCENTAGE_PENDING'):
            save_comment_then_percentage(comment, percent)
        comment.assert_called_once()
        percent.assert_called_once()

    def test_work_form_saved_and_confirmed_on_reload(self):
        with sync_playwright() as p:
            browser = p.chromium.launch(channel='chrome', headless=True)
            page = browser.new_page()
            state = {'percent': '25,00', 'posts': 0, 'persist': True}
            url = 'https://promob.e-desk.com.br/Portal/Trabalho.aspx?solicitacao=2265173&id_trabalho=4'

            def route_work(route):
                if route.request.method == 'POST':
                    state['posts'] += 1
                    form = parse_qs(route.request.post_data)
                    self.assertEqual(form['estimated'], ['80,00'])
                    if state['persist']:
                        state['percent'] = form['realized'][0]
                route.fulfill(status=200, content_type='text/html', body=f'''
                  <p>Solicitação/Trabalho 2265173/4</p>
                  <form method="post"><table>
                  <tr><td>%Estimado</td><td><input name="estimated" value="80,00"></td></tr>
                  <tr><td>%Realizado</td><td><input name="realized" value="{state['percent']}"></td></tr>
                  </table><button id="cph1_BtAtu" name="cph1$BtAtu" value="Salvar">Salvar</button></form>''')

            page.route('**/Portal/Trabalho.aspx?*', route_work)
            page.goto(url)
            save_work_percentage(page, '2265173', '4', '45,50')
            self.assertEqual(state['posts'], 1)
            self.assertEqual(percentage_field(page).input_value(), '45,50')
            with self.assertRaisesRegex(RuntimeError, 'corresponde'):
                save_work_percentage(page, '9999999', '4', 60)
            self.assertEqual(state['posts'], 1)
            state['persist'] = False
            with self.assertRaisesRegex(RuntimeError, 'confirmado'):
                save_work_percentage(page, '2265173', '4', 60)
            self.assertEqual(state['posts'], 2)
            page.set_content('<label for="a">%Realizado</label><input id="a" readonly value="25">')
            with self.assertRaises(Exception):
                percentage_field(page)
            page.set_content('<label for="a">%Realizado</label><input id="a"><label for="b">%Realizado</label><input id="b">')
            with self.assertRaises(Exception):
                percentage_field(page)
            browser.close()

    def test_alternative_save_controls_and_numeric_input(self):
        with sync_playwright() as p:
            browser = p.chromium.launch(channel='chrome', headless=True)
            for button, field_type, expected in [
                ('<button name="cph1$SalvarTrabalho" value="Salvar">Salvar</button>', 'text', '37,50'),
                ('<button id="salvar" type="submit">Salvar</button>', 'text', '37,50'),
                ('<button name="cph1$SalvarTrabalho" value="Salvar">Salvar</button>', 'number', '37.50'),
            ]:
                page = browser.new_page()
                state = {'value': '0', 'posts': 0}
                url = 'https://fixture.invalid/Trabalho.aspx?solicitacao=2265173&id_trabalho=4'
                def respond(route):
                    if route.request.method == 'POST':
                        state['posts'] += 1
                        data = parse_qs(route.request.post_data or '')
                        state['value'] = data['realized'][0]
                    route.fulfill(status=200, content_type='text/html', body=f'''
                        <form method="post"><label for="realized">% Realizado</label>
                        <input id="realized" name="realized" type="{field_type}" step="0.01" value="{state['value']}">
                        {button}</form>''')
                page.route('**/*', respond)
                page.goto(url)
                save_work_percentage(page, '2265173', '4', '37.50')
                self.assertEqual(state['posts'], 1)
                self.assertEqual(state['value'], expected)
                page.close()
            browser.close()


if __name__ == '__main__':
    unittest.main()
