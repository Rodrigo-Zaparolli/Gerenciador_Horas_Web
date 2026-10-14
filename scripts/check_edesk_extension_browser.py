"""Real MV3 extension, mocked E-Desk/app pages; NEVER connects to live E-Desk."""
from pathlib import Path
import json
import tempfile
import time
import ssl
import threading
import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from types import SimpleNamespace
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from urllib.parse import urlparse, parse_qs
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
APP = 'https://gerenciador-horas.web.app'
EDESK = 'https://promob.e-desk.com.br'


def run():
    state = {'hours': [], 'comment': '07/10/2026: - Histórico existente',
             'phases': [['01/10/2026', '02/10/2026'], ['03/10/2026', '04/10/2026']],
             'comments': [], 'saves': 0}

    def html(body, script=''):
        return '<!doctype html><meta charset="utf-8"><body>' + body + '<script>' + script + '</script></body>'

    def route_handler(route):
        url = urlparse(route.request.url)
        path = url.path
        if url.hostname == 'gerenciador-horas.web.app':
            if path == '/edesk_extension.js':
                return route.fulfill(content_type='application/javascript', body=(ROOT / 'web/edesk_extension.js').read_text(encoding='utf-8'))
            return route.fulfill(content_type='text/html', body=html('<h1>App simulado</h1>') + '<script src="/edesk_extension.js"></script>')
        if url.hostname != 'promob.e-desk.com.br':
            return route.abort()
        if path == '/save-hour':
            data = route.request.post_data_json
            # Deliberately return HTTP 200 without persisting one test interval.
            # The page optimistically adds a row; only reload reveals failure.
            if data['inicio'] != '10:00':
                state['hours'].append(data)
                state['comment'] = data['comment']
            state['saves'] += 1
            return route.fulfill(content_type='application/json', body=json.dumps(data))
        if path == '/save-phases':
            state['phases'] = route.request.post_data_json
            state['saves'] += 1
            return route.fulfill(body='ok')
        if path == '/save-comment':
            state['comments'].append(route.request.post_data_json['text'])
            state['saves'] += 1
            return route.fulfill(body='ok')
        if path.endswith('ListaSolicitacao.aspx') or path == '/':
            body = '<input id="cph1_txtSol"><button id="cph1_btnLocSol">Pesquisar</button>'
            script = "document.querySelector('button').onclick=()=>window.open('/Portal/Solicitacao.aspx?GUID=test&solicitacao=60201207102108503109404110051066011072021')"
        elif path.endswith('Solicitacao.aspx'):
            body = '<h1>Solicitação 2265173</h1><div id="cph1_rpvTrabalhos"><table id="cph1_gvwTra"><tr><td onclick="window.open(\'/Portal/Trabalho.aspx?GUID=test&id_trabalho=2&solicitacao=2265173\'); /* btnSelTra */">2</td></tr></table></div>'
            body = body.replace('<div id="cph1_rpvTrabalhos">', '<div id="cph1_rpvTrabalhos" style="display:none">')
            body += '<ul><li class="rtsLI"><span class="rtsTxt">Trabalhos (7)</span></li></ul>'
            body += '<div id="cph1_rpvFasePro">'
            for i, name in enumerate(['Promob - Contato Inicial', 'Promob - Consultoria']):
                body += f'<span id="lblGFasNome{i}">{name}</span><input id="txtGFasDtIniAj{i}" value="{state["phases"][i][0]}"><input id="txtGFasDtTerAju{i}" value="{state["phases"][i][1]}">'
            body += '<button id="save">Salvar</button></div>'
            script = "document.querySelector('.rtsLI').onclick=()=>document.querySelector('#cph1_rpvTrabalhos').style.display='block';document.querySelector('#save').onclick=async()=>{await fetch('/save-phases',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify([0,1].map(i=>[document.querySelector('#txtGFasDtIniAj'+i).value,document.querySelector('#txtGFasDtTerAju'+i).value]))});}"
        elif path.endswith('TrabalhoRetroativo.aspx'):
            body = '<input id="cph1_txtDatTem"><input id="cph1_txtHorIni"><input id="cph1_txtHorFin"><select id="cph1_ddlTipReg"><option value="0">Interno</option><option value="1">Externo</option></select>'
            body += '<textarea id="cph1_txtRea">' + state['comment'] + '</textarea><table id="cph1_gvwTempos">'
            for hour in state['hours']:
                body += '<tr>' + ''.join('<td>' + hour[key] + '</td>' for key in ['data','inicio','fim']) + '</tr>'
            body += '</table><button id="cph1_BtAtu">Salvar</button>'
            script = "document.querySelector('button').onclick=async()=>{let data={data:document.querySelector('#cph1_txtDatTem').value,inicio:document.querySelector('#cph1_txtHorIni').value,fim:document.querySelector('#cph1_txtHorFin').value,comment:document.querySelector('#cph1_txtRea').value}; await fetch('/save-hour',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});let row=document.querySelector('table').insertRow();for(let key of ['data','inicio','fim'])row.insertCell().textContent=data[key];}"
        elif path.endswith('Trabalho.aspx'):
            body = '<h1>Solicitação 2265173 Trabalho 2</h1><button id="cph1_BtCom">Comentários</button>' + ''.join('<p>' + item + '</p>' for item in state['comments'])
            script = "document.querySelector('button').onclick=()=>window.open('/Portal/Comentario.aspx?GUID=test')"
        elif path.endswith('Comentario.aspx'):
            body = '<select id="popC_ddlTipCom"><option value="0">Comentário</option></select><div id="ctl00_popC_rdeCom"></div><button id="popC_BtAtu">Salvar</button>'
            script = "let content='';window.$find=()=>({set_html:html=>{content=html;document.querySelector('#ctl00_popC_rdeCom').innerHTML=html},get_html:()=>content});document.querySelector('button').onclick=async()=>{await fetch('/save-comment',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text:document.querySelector('#ctl00_popC_rdeCom').textContent})});}"
        else:
            return route.fulfill(status=404, body='Unknown mocked route')
        route.fulfill(content_type='text/html', body=html(body, script))

    with tempfile.TemporaryDirectory(prefix='edesk-extension-test-') as profile, sync_playwright() as p:
        # tabs.create can navigate before Playwright attaches a page route.
        # Map both real hostnames to a local TLS fixture at the network layer.
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Edesk local test')])
        now = datetime.datetime.now(datetime.timezone.utc)
        cert = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
                .public_key(key.public_key()).serial_number(x509.random_serial_number())
                .not_valid_before(now - datetime.timedelta(days=1)).not_valid_after(now + datetime.timedelta(days=1))
                .add_extension(x509.SubjectAlternativeName([x509.DNSName('promob.e-desk.com.br'), x509.DNSName('gerenciador-horas.web.app')]), critical=False)
                .sign(key, hashes.SHA256()))
        certfile, keyfile = Path(profile)/'cert.pem', Path(profile)/'key.pem'
        certfile.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
        keyfile.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                self.handle_fixture()

            def do_POST(self):
                self.handle_fixture()

            def handle_fixture(self):
                payload = self.rfile.read(int(self.headers.get('Content-Length', '0')))
                request = SimpleNamespace(url='https://' + self.headers['Host'] + self.path,
                                          post_data_json=json.loads(payload) if payload else None)
                handler = self

                class LocalRoute:
                    def __init__(self):
                        self.request = request

                    def fulfill(self, content_type='text/plain', body='', status=200):
                        raw = body.encode('utf-8')
                        handler.send_response(status)
                        handler.send_header('Content-Type', content_type + '; charset=utf-8')
                        handler.send_header('Content-Length', str(len(raw)))
                        handler.end_headers()
                        handler.wfile.write(raw)

                    def abort(self):
                        self.fulfill(status=403, body='Blocked by local fixture')

                route_handler(LocalRoute())

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(certfile, keyfile)
        server.socket = tls.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        port = server.server_address[1]
        context = p.chromium.launch_persistent_context(
            profile, headless=False,
            executable_path=str(ROOT / 'python/ms-playwright/chromium-1187/chrome-win/chrome.exe'),
            args=['--headless=new', f'--disable-extensions-except={ROOT / "browser_extension"}', f'--load-extension={ROOT / "browser_extension"}', '--no-first-run',
                  '--ignore-certificate-errors', '--no-proxy-server',
                  f'--host-resolver-rules=MAP promob.e-desk.com.br 127.0.0.1:{port}, MAP gerenciador-horas.web.app 127.0.0.1:{port}'],
            ignore_default_args=['--disable-extensions'])
        context.route('https://**/*', route_handler)
        workers = context.service_workers
        worker = workers[0] if workers else context.wait_for_event('serviceworker')
        app = context.new_page()
        app.goto(APP)
        edesk = context.new_page()
        edesk.goto(EDESK + '/Portal/ListaSolicitacao.aspx?GUID=test')

        def call(path, body=None, uid='test-user'):
            return app.evaluate('async data=>JSON.parse(await window.edeskExtensionCall(JSON.stringify(data)))', {'path':path,'body':body,'uid':uid})

        assert call('/healthz')['mode'] == 'extension'
        work = {'solicitacao':'2265173','idTrabalho':'2','horas':[{'data':'09/10/2026','inicio':'08:00','fim':'09:00','tipo':'0','descricao':'Consultoria nova'}]}

        def operation(action, request, enviar=True, uid='test-user'):
            with context.expect_page() as created:
                result = call('/api/edesk/' + action, {'request':request,'enviar':enviar,'operationId':action + str(state['saves'])}, uid)
            assert result.get('accepted'), result
            runner = created.value
            runner.wait_for_url('**/runner.html')
            if action != 'horas':
                runner.locator('#start').wait_for(state='visible')
                runner.wait_for_function('!document.querySelector("#start").disabled')
            stored = worker.evaluate('async()=> (await chrome.storage.session.get("job")).job.request')
            assert 'edeskCredenciais' not in stored and 'url' not in stored
            if action != 'horas':
                runner.locator('#start').click()
            else:
                runner.locator('#start').wait_for(state='hidden')
            deadline = time.monotonic() + 90
            response = {}
            while time.monotonic() < deadline:
                response = call('/api/edesk/status', uid=uid)
                if 'result' in response:
                    break
                app.wait_for_timeout(300)
            assert 'result' in response, (response, runner.locator('#status').inner_text())
            return response['result']

        result = operation('horas', {'trabalhos':[work], 'edeskCredenciais':{'senha':'must-not-be-stored'}})
        assert result['confirmed'], result
        assert state['comment'] == '07/10/2026: - Histórico existente\n09/10/2026: - Consultoria nova'
        assert len(state['hours']) == 1
        assert call('/api/edesk/review', {'request':{'trabalhos':[work]}})['items'][0]['state'] == 'confirmed'
        result = operation('horas', {'trabalhos':[work]})
        assert result['confirmed'] and len(state['hours']) == 1
        assert call('/api/edesk/history', uid='another-user')['items'] == {}
        # Another browser-account namespace also checks server table, preventing a resend.
        result = operation('horas', {'trabalhos':[work]}, uid='another-user')
        assert result['confirmed'] and len(state['hours']) == 1
        result = operation('fases', {'id':'2265173','fases':[{'nome':'Contato Inicial','dataInicial':'10/10/2026','dataFinal':'12/10/2026'}]})
        assert result['confirmed'], result
        assert state['phases'] == [['10/10/2026','12/10/2026'], ['03/10/2026','04/10/2026']]
        result = operation('comentarios', {'solicitacao':'2265173','idTrabalho':'2','tipo':'0','texto':'Comentário confirmado da extensão'})
        assert result['confirmed'], result
        assert state['comments'] == ['Comentário confirmado da extensão']
        before = state['saves']
        result = operation('comentarios', {'solicitacao':'2265173','idTrabalho':'2','tipo':'0','texto':'[[EDESK_HTML]]<p>Texto inseguro</p><script>window.evil=true</script>'})
        assert not result['confirmed'] and state['saves'] == before
        result = operation('comentarios', {'solicitacao':'2265173','idTrabalho':'2','tipo':'0','texto':'[[EDESK_HTML]]<p>Texto com imagem</p><img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jIp0AAAAASUVORK5CYII=">'})
        assert not result['confirmed'] and 'imagens' in result['message']
        assert state['comments'][-1] == 'Texto com imagem'
        before = state['saves']
        result = operation('fases', {'id':'2265173','fases':[{'nome':'Consultoria','dataInicial':'15/10/2026','dataFinal':'16/10/2026'}]}, enviar=False)
        assert not result['confirmed'] and state['saves'] == before
        failed = {**work, 'horas': [{**work['horas'][0], 'inicio':'10:00', 'fim':'11:00'}]}
        result = operation('horas', {'trabalhos':[failed]})
        assert not result['confirmed']
        assert call('/api/edesk/review', {'request':{'trabalhos':[failed]}})['items'][0]['state'] == 'uncertain'
        blocked = call('/api/edesk/horas', {'request':{'trabalhos':[failed]}, 'enviar':True})
        assert 'error' in blocked and len(state['hours']) == 1
        # Closing a prepared runner releases the busy lock without saving.
        with context.expect_page() as created:
            accepted = call('/api/edesk/fases', {'request':{'id':'2265173','fases':[{'nome':'Consultoria','dataInicial':'15/10/2026','dataFinal':'16/10/2026'}]},'enviar':True})
        assert accepted['accepted']
        abandoned = created.value
        abandoned.wait_for_url('**/runner.html')
        abandoned.close()
        assert not call('/healthz')['busy']
        assert not call('/api/edesk/status')['result']['confirmed']
        # A request from an unlisted origin receives no content bridge.
        forbidden = context.new_page()
        context.route('https://untrusted.test/**', lambda route: route.fulfill(content_type='text/html', body=html('<p>Untrusted</p>')))
        forbidden.goto('https://untrusted.test/')
        assert forbidden.evaluate('typeof window.edeskExtensionCall') == 'undefined'
        context.close()
        server.shutdown()
        server.server_close()
        print('EXTENSION_BROWSER_OK: hours, preservation, deduplication, isolation, selected phases, comments, dry run, failed-save guard, interrupted runner, origin restrictions')


if __name__ == '__main__':
    run()
