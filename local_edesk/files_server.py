"""Portable opener only: loopback, app-origin allowlist and Firebase user auth."""
from flask import Flask, jsonify, request
from waitress import serve
from local_edesk.authentication import verify_token
from local_edesk.local_files import execute, SUPPORTED_ACTIONS, PROTOCOL_VERSION

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 32768
ORIGINS = {'https://gerenciador-horas.web.app', 'https://gerenciador-horas.firebaseapp.com'}


@app.before_request
def guard():
    if request.remote_addr not in {'127.0.0.1', '::1'} or request.host.split(':', 1)[0] not in {'127.0.0.1', 'localhost'}:
        return jsonify(message='Use a integração deste computador.'), 403
    origin = request.headers.get('Origin')
    if origin and origin not in ORIGINS or request.method == 'POST' and origin not in ORIGINS:
        return jsonify(message='Abra pelo aplicativo web.'), 403
    if request.method == 'OPTIONS':
        return '', 204


@app.after_request
def headers(response):
    origin = request.headers.get('Origin')
    response.headers['Cache-Control'] = 'no-store'
    if origin in ORIGINS:
        response.headers.update({'Access-Control-Allow-Origin': origin,
            'Access-Control-Allow-Headers':'Authorization, Content-Type',
            'Access-Control-Allow-Methods':'GET, POST, OPTIONS',
            'Access-Control-Allow-Private-Network':'true', 'Vary':'Origin'})
    return response


@app.get('/healthz')
def health():
    return jsonify(status='ok', service='gerenciador-horas-edesk', nativeFiles=True,
        mode='files-only', busy=False, excelMirror='preview' in SUPPORTED_ACTIONS,
        nativeActions=sorted(SUPPORTED_ACTIONS), nativeFilesVersion=PROTOCOL_VERSION)


@app.post('/api/local-files')
def open_files():
    scheme, _, token = request.headers.get('Authorization', '').partition(' ')
    if scheme.lower() != 'bearer' or not token:
        return jsonify(message='Entre novamente na sua conta.'), 401
    try:
        user = verify_token(token)
    except ValueError:
        return jsonify(message='Autenticação inválida. Entre novamente.'), 401
    except Exception:
        return jsonify(message='Não foi possível validar sua conta. Verifique a conexão com a internet.'), 503
    body = request.get_json(silent=True)
    if not isinstance(body, dict):
        return jsonify(message='Solicitação inválida.'), 400
    try:
        if body.get('action') in {'excel-editor-read', 'excel-editor-write'}:
            return jsonify(execute(user['sub'], body, verified_user=user))
        return jsonify(execute(user['sub'], body))
    except PermissionError as error:
        return jsonify(message=str(error)), 403
    except FileNotFoundError:
        return jsonify(message='Selecione novamente o original: a pasta ou arquivo mudou de lugar.'), 400
    except ValueError as error:
        return jsonify(message=str(error)), 400
    except Exception:
        return jsonify(message='Não foi possível abrir o original. Verifique as permissões e o programa padrão do Windows.'), 500


if __name__ == '__main__':
    serve(app, host='127.0.0.1', port=8765, threads=4, channel_timeout=960)
