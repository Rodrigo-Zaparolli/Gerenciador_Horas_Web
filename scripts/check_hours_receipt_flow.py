"""Real Save callbacks and paginated receipt reads on an isolated E-Desk fixture."""
import html
import json
import os
import sys
import tempfile
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
os.environ['PLAYWRIGHT_BROWSERS_PATH'] = str(ROOT / 'python/ms-playwright')
sys.path.insert(0, str(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'edesk_bot'))

with tempfile.TemporaryDirectory(prefix='hours-receipt-', dir=ROOT / 'build') as temporary:
    os.environ['EDESK_DATA_DIR'] = temporary
    os.environ['EDESK_EVENTS_FILE'] = str(Path(temporary) / 'events.jsonl')
    import edesk_horas as hours
    from hour_receipt import read_hours, deliver_hours
    from send_progress import hour_event

    url = 'https://fixture.invalid/Portal/TrabalhoRetroativo.aspx?GUID=test&solicitacao=226144&id_trabalho=3'
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        for scenario in ['persisted', 'dropped_once', 'closed', 'paginated', 'unreadable']:
            context = browser.new_context()
            state = {'rows': [], 'calls': {}, 'history': '', 'page': None}
            items = [{'data': '21/10/2026', 'inicio': f'{n:02}:00', 'fim': f'{n+1:02}:00',
                      'tipo': '0', 'descricao': f'Atividade {n}', '_sendKey': str(n) * 64}
                     for n in [8, 9, 10]]
            if scenario in {'persisted', 'paginated'}:
                state['rows'].append(dict(items[0]))

            def document(page_number=1):
                records = state['rows']
                paginated = scenario == 'paginated' and len(records) > 1
                shown = records[page_number-1:page_number] if paginated else records
                grid = '<table id="cph1_historicoTempo"><tr><th>Data</th><th>Hora Inicial</th><th>Hora Final</th><th>Tipo</th></tr>'
                for row in shown:
                    grid += f'<tr><td>{row["data"][:-4]+row["data"][-2:]}</td><td>{row["inicio"]}:00</td><td>{row["fim"]}:00</td><td>Interno</td></tr>'
                if not shown:
                    grid += '<tr><td colspan="4">Nenhum registro encontrado</td></tr>'
                if paginated:
                    grid += '<tr><td colspan="4">' + ''.join(
                        f'<span>{i}</span>' if i == page_number else
                        f'''<a href="javascript:__doPostBack('cph1$historicoTempo','Page${i}')">{i}</a>'''
                        for i in range(1, len(records)+1)) + '</td></tr>'
                grid += '</table>'
                if scenario == 'unreadable': grid = '<div>Listagem temporariamente indisponivel</div>'
                return '''<html><body><input id="cph1_txtDatTem"><input id="cph1_txtHorIni"><input id="cph1_txtHorFin">
                  <select id="cph1_ddlTipReg"><option value="0">Interno</option></select>
                  <textarea id="cph1_txtRea">''' + html.escape(state['history']) + '''</textarea>
                  <button id="cph1_BtAtu" onclick="saveHour()">Salvar</button>''' + grid + '''<script>
                  async function __doPostBack(target,arg) {
                    const r=await fetch(location.href,{method:'POST',body:new URLSearchParams({__EVENTTARGET:target,__EVENTARGUMENT:arg})});
                    document.body.innerHTML=await r.text();
                  }
                  async function saveHour() {
                    const data={__EVENTTARGET:'cph1$BtAtu'};
                    for(const name of ['txtDatTem','txtHorIni','txtHorFin','ddlTipReg','txtRea'])data[name]=document.getElementById('cph1_'+name).value;
                    const saved=await fetch(location.href,{method:'POST',body:new URLSearchParams(data)});
                    await saved.text();
                    ''' + ('window.close();' if scenario == 'closed' else 'location.reload();') + '''
                  }</script></body></html>'''

            def route(request_route):
                request = request_route.request
                assert urlparse(request.url).path == '/Portal/TrabalhoRetroativo.aspx'
                assert parse_qs(urlparse(request.url).query)['id_trabalho'] == ['3']
                if request.method == 'POST':
                    data = parse_qs(request.post_data or '', keep_blank_values=True)
                    if data.get('__EVENTARGUMENT', [''])[0].startswith('Page$'):
                        request_route.fulfill(content_type='text/html', body=document(int(data['__EVENTARGUMENT'][0].split('$')[1])))
                        return
                    start = data['txtHorIni'][0]
                    state['calls'][start] = state['calls'].get(start, 0) + 1
                    state['history'] = data['txtRea'][0]
                    if scenario != 'dropped_once' or state['calls'][start] > 1:
                        state['rows'].append({'data': data['txtDatTem'][0], 'inicio': start,
                            'fim': data['txtHorFin'][0], 'tipo': data['ddlTipReg'][0]})
                    request_route.fulfill(content_type='text/plain', body='OK')
                else:
                    request_route.fulfill(content_type='text/html', body=document())

            context.route('https://fixture.invalid/**', route)
            keeper = context.new_page()
            keeper.set_content('<p>Grid keeper</p>')

            def prepare():
                page = state['page']
                if page is None or page.is_closed():
                    with context.expect_page() as opened:
                        keeper.evaluate('(url)=>window.open(url)', url)
                    page = state['page'] = opened.value
                    page.wait_for_load_state('domcontentloaded')
                return page

            def read_fresh():
                page = prepare()
                page.goto(url, wait_until='domcontentloaded')
                return read_hours(page)

            def submit(item, index, retry):
                item['_receiptRetry'] = retry
                item['_saveOutcome'] = 'not_submitted'
                try:
                    page = prepare()
                    hours.salvar_hora(page, item, index, len(items))
                except Exception:
                    pass
                return item['_saveOutcome']

            result = deliver_hours(items, read_fresh, submit, hour_event)
            if scenario == 'unreadable':
                assert result['ok'] is False and not state['calls'], result
            else:
                assert result['ok'] is True, result
                assert len(state['rows']) == len(items), (scenario, state['rows'], state['calls'])
                for item in items:
                    count = state['calls'].get(item['inicio'], 0)
                    expected = 0 if scenario in {'persisted','paginated'} and item is items[0] else 2 if scenario == 'dropped_once' else 1
                    assert count == expected, (scenario, item, count, expected)
                    if count:
                        assert state['history'].count('21/10/2026: - ' + item['descricao']) == 1, state['history']
                if scenario == 'paginated':
                    assert len(read_hours(prepare())['rows']) == len(items)
            print('HOURS_RECEIPT_CASE_OK', scenario, json.dumps(result), flush=True)
            context.close()
        browser.close()
print('HOURS_RECEIPT_FLOW_OK: fresh persisted rows, skip existing, bounded missing-only retry, closed page, pagination and unreadable grid; no real E-Desk access')
