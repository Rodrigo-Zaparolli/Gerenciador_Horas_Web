"""Exercise the actual comment save followed by work percentage in a fixture."""
import os
import sys
import tempfile
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault('PLAYWRIGHT_BROWSERS_PATH', str(ROOT / 'python/ms-playwright'))
sys.path.insert(0, str(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'edesk_bot'))

with tempfile.TemporaryDirectory(prefix='comment-close-', dir=ROOT / 'build') as temporary:
    os.environ['EDESK_DATA_DIR'] = temporary
    from edesk_comentario import salvar_comentario
    from comment_percentage import save_comment_then_percentage, update_percentage_after_comment
    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context()
        state = {'comment_posts': 0, 'percentage_posts': 0, 'value': '0'}
        scenario = 'closed'
        request_url = 'https://fixture.invalid/Solicitacao.aspx?solicitacao=226144'
        work_url = 'https://fixture.invalid/Trabalho.aspx?solicitacao=226144&id_trabalho=3'

        def respond(route):
            request = route.request
            path = urlparse(request.url).path
            if path == '/Solicitacao.aspx':
                html = ('<button onclick="window.open(\'/Comentario.aspx\')">Comment</button>'
                    '<a role="tab" onclick="document.querySelector(\'#cph1_rpvTrabalhos\').style.display=\'block\'">Trabalhos (2)</a>'
                    '<div id="cph1_rpvTrabalhos" style="display:none"><table id="cph1_gvwTra">'
                    '<tr><td onclick="btnSelTra()">3</td></tr></table></div>'
                    '<script>function btnSelTra(){location.href="' + work_url + '"}</script>')
            elif path == '/Comentario.aspx':
                if request.method == 'POST':
                    state['comment_posts'] += 1
                    html = '<script>window.close()</script>' if scenario == 'closed' else '|error|fixture rejection'
                    if scenario == 'http_error':
                        return route.fulfill(status=500, body='fixture rejection')
                else:
                    html = '<form method="post"><button id="popC_BtAtu" name="popC$BtAtu" value="Salvar">Salvar</button></form>'
            elif path == '/Trabalho.aspx':
                if request.method == 'POST':
                    state['percentage_posts'] += 1
                    state['value'] = parse_qs(request.post_data)['percentage'][0]
                html = ('<form method="post"><label for="percentage">%Realizado</label>'
                    '<input id="percentage" name="percentage" value="' + state['value'] + '">'
                    '<button id="cph1_BtAtu" name="cph1$BtAtu" value="Salvar">Salvar</button></form>')
            else:
                raise AssertionError(path)
            route.fulfill(status=200, content_type='text/html', body=html)

        context.route('**/*', respond)
        page = context.new_page()
        page.goto(request_url)
        with page.expect_popup() as opened:
            page.get_by_text('Comment', exact=True).click()
        comment = opened.value
        comment.wait_for_load_state('domcontentloaded')
        save_comment_then_percentage(
            lambda: salvar_comentario(comment, comment),
            lambda: update_percentage_after_comment(page, context, request_url, '226144', '3', 91))
        assert state == {'comment_posts': 1, 'percentage_posts': 1, 'value': '91,00'}, state
        for scenario in ['http_error', 'asp_error']:
            page.goto(request_url)
            with page.expect_popup() as opened:
                page.get_by_text('Comment', exact=True).click()
            comment = opened.value
            comment.wait_for_load_state('domcontentloaded')
            before = state['percentage_posts']
            try:
                save_comment_then_percentage(
                    lambda: salvar_comentario(comment, comment),
                    lambda: update_percentage_after_comment(page, context, request_url, '226144', '3', 92))
                raise AssertionError('Rejected comment must not continue to percentage')
            except RuntimeError:
                pass
            assert state['percentage_posts'] == before
            comment.close()
        assert state['comment_posts'] == 3, 'Each manual test must click Save exactly once'
        browser.close()
print('COMMENT_CLOSE_FLOW_OK: closed popup -> work 3 -> percentage verified; one POST each; HTTP/ASP errors block percentage')
