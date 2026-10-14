"""Chrome local-device permission regression checks; no user files are opened."""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

origin = 'https://gerenciador-horas.web.app'
script = (Path(__file__).resolve().parents[1] / 'web/native_local_files_v2.js').read_text(encoding='utf-8')
with sync_playwright() as p:
    browser = p.chromium.launch(channel='chrome', headless=True)
    context = browser.new_context()
    page = context.new_page()
    cdp = context.new_cdp_session(page)
    context_id = cdp.send('Target.getTargetInfo')['targetInfo']['browserContextId']
    def permission(state):
        for name in ['local-network-access', 'loopback-network']:
            try:
                cdp.send('Browser.setPermission', {'permission':{'name':name},
                    'setting':state, 'origin':origin, 'browserContextId':context_id})
            except Exception:
                if name == 'local-network-access':
                    raise
    page.goto(origin, wait_until='networkidle', timeout=60000)
    page.evaluate(script)
    def call(action, **args):
        return page.evaluate('async args => JSON.parse(await nativeLocalFilesRequest(JSON.stringify(args)))',
            {'action':action, **args})

    permission('denied')
    result = call('open', token='invalid-test-token', reference='invalid')
    assert result['error'] == 'permission', result
    assert 'navegador bloqueou' in result['message'], result

    permission('granted')
    result = call('health', interactive=True)
    assert result['status'] == 200 and result['data']['nativeFiles'] is True, result
    result = call('open', token='invalid-test-token', reference='invalid')
    assert result['status'] == 401, result  # No picker or startfile can run.

    # A passive probe must leave a pending permission alone and make no request.
    page.evaluate("""() => {
      window.originalQuery = navigator.permissions.query.bind(navigator.permissions);
      navigator.permissions.query = async () => ({state:'prompt'});
      window.originalFetch = window.fetch;
      window.fetchCount = 0;
      window.fetch = async (url, options) => {
        if (String(url).startsWith('http://127.0.0.1:8765/')) {window.fetchCount++; throw Error('unexpected');}
        return window.originalFetch(url, options);
      };
    }""")
    result = call('health', interactive=False)
    assert result['data']['status'] == 'permission-required', result
    assert page.evaluate('fetchCount') == 0

    # An interactive call survives a response slower than the old one-second probe.
    page.evaluate("""() => {
      window.fetch = async (url, options) => {
        if (!String(url).startsWith('http://127.0.0.1:8765/')) return window.originalFetch(url, options);
        if (url !== 'http://127.0.0.1:8765/api/local-files') throw Error('unsafe URL');
        if (JSON.parse(options.body).action !== 'open') throw Error('missing action');
        if (options.targetAddressSpace !== 'loopback') throw Error('missing address space');
        await new Promise(resolve => setTimeout(resolve, 1600));
        if (options.signal.aborted) throw Error('request interrupted');
        return {status:200, json:async()=>({opened:true})};
      };
    }""")
    result = call('open', token='invalid-test-token', reference='invalid')
    assert result == {'status':200,'data':{'opened':True}}, result
    page.evaluate("""() => {
      window.fetch = async (url, options) => {
        if (!String(url).startsWith('http://127.0.0.1:8765/')) return window.originalFetch(url, options);
        const body = JSON.parse(options.body);
        if (options.method !== 'POST' || body.action !== 'preview' ||
            body.reference !== 'test-workbook' || body.range !== 'Dados!A1:L8')
          throw Error('incorrect preview request');
        if (options.headers.Authorization !== 'Bearer invalid-test-token')
          throw Error('missing authentication');
        return {status:200, json:async()=>({renderer:'excel', imagemBase64:'test-image'})};
      };
    }""")
    result = call('preview', token='invalid-test-token', reference='test-workbook', range='Dados!A1:L8')
    assert result == {'status':200,'data':{'renderer':'excel','imagemBase64':'test-image'}}, result
    diagnostic = page.evaluate("localStorage.getItem('nativeExcelPreviewDiagnostic')")
    assert json.loads(diagnostic)['acaoEnviada'] == 'preview'
    assert all(value not in diagnostic for value in ['invalid-test-token', 'test-workbook', 'test-image', 'Dados!A1:L8'])
    page.evaluate('() => { navigator.permissions.query = window.originalQuery; window.fetch = window.originalFetch; }')
    page.route(origin + '/abrir-arquivos.html', lambda route: route.fulfill(content_type='text/html',
        body=(Path(__file__).resolve().parents[1] / 'web/abrir-arquivos.html').read_text(encoding='utf-8')))
    page.route(origin + '/native_local_files_v2.js*', lambda route: route.fulfill(content_type='application/javascript', body=script))
    page.goto(origin + '/abrir-arquivos.html', wait_until='networkidle')
    page.get_by_role('button', name='Permitir acesso e verificar conexão').click()
    page.wait_for_function("document.querySelector('#status').textContent.includes('incluindo o espelho do Excel')")
    permission('denied')
    page.get_by_role('button', name='Permitir acesso e verificar conexão').click()
    page.wait_for_function("document.querySelector('#status').textContent.includes('navegador bloqueou')")
    browser.close()
print(json.dumps({'denied_permission':'clear guidance', 'granted_permission':'connected',
    'unauthenticated_open':'blocked', 'passive_probe':'no permission prompt',
    'preview_request':'action, reference, range and auth preserved', 'delayed_response':'not interrupted'}))
