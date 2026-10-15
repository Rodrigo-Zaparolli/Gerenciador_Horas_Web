"""Offline browser regression: saved comment -> request -> Works -> percentage."""
import sys
from pathlib import Path
from urllib.parse import urlparse, parse_qs
sys.path.insert(0, str(Path(sys.argv[1]).resolve()))
from comment_percentage import update_percentage_after_comment
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, executable_path=p.chromium.executable_path)
    context = browser.new_context()
    saved = ['50,00']
    posts = []
    request_url = 'https://fixture.invalid/Solicitacao.aspx?solicitacao=2261144'
    work_url = 'https://fixture.invalid/Trabalho.aspx?solicitacao=2261144&id_trabalho=6'
    def respond(route):
        request = route.request
        path = urlparse(request.url).path
        if path == '/Solicitacao.aspx':
            html = ('<a role="tab" onclick="document.getElementById(&quot;cph1_rpvTrabalhos&quot;).style.display=&quot;block&quot;">Trabalhos (6)</a>'
                '<div id="cph1_rpvTrabalhos" style="display:none"><table id="cph1_gvwTra"><tr>'
                '<td onclick="btnSelTra()">6</td></tr></table></div>'
                '<script>function btnSelTra(){location.href="' + work_url + '"}</script>')
        elif path == '/Trabalho.aspx':
            if request.method == 'POST':
                data = parse_qs(request.post_data or '')
                saved[0] = data['percentage'][0]
                posts.append(data)
            html = ('<form method="post"><table><tr><td>%Realizado</td><td>'
                '<input name="percentage" value="' + saved[0] + '"></td></tr></table>'
                '<input type="submit" id="cph1_BtAtu" name="cph1$BtAtu" value="Salvar"></form>')
        else:
            raise AssertionError('Unexpected external request: ' + request.url)
        route.fulfill(status=200, content_type='text/html', body=html)
    context.route('**/*', respond)
    for closed in [False, True]:
        page = context.new_page()
        page.goto(request_url)
        if closed:
            page.close()
        before = len(posts)
        update_percentage_after_comment(page, context, request_url, '2261144', '6', '91.5')
        assert saved[0] == '91,50'
        assert len(posts) == before + 1, 'Percentage must be saved exactly once'
    browser.close()
print('COMMENT_PERCENTAGE_BROWSER_FLOW_OK: Works tab, exact work, one POST, reload verification, closed-page recovery')
