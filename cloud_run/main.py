import hashlib
import json
import logging
import os
import signal
import subprocess
import sys
import tempfile
import threading
import uuid
from pathlib import Path
from urllib.parse import urlsplit

from flask import Flask, jsonify, request
from werkzeug.exceptions import BadRequest, RequestEntityTooLarge
from local_edesk import central


APP_ROOT = Path(__file__).resolve().parent.parent
EDESK_SCRIPTS_DIR = APP_ROOT / "edesk_bot"
MAX_REQUEST_BYTES = 15 * 1024 * 1024
SCRIPT_TIMEOUT_SECONDS = 840
EDESK_URL_HOSTS = {
    "promob.e-desk.com.br",
    "promobid.promob.com",
    "identity.promob.com",
}
SCRIPTS = {
    "fases": "edesk_fases.py",
    "horas": "edesk_horas.py",
    "comentarios": "edesk_comentario.py",
    "percentual": "edesk_percentual.py",
    "conferencia": "edesk_conferencia.py",
    "recebidos": "edesk_recebidos.py",
}
DEFAULT_ORIGINS = {
    "https://gerenciador-horas.web.app",
    "https://gerenciador-horas.firebaseapp.com",
}

LOCAL_MODE = os.environ.get("EDESK_LOCAL_MODE") == "true"
if not LOCAL_MODE:
    import firebase_admin
    from firebase_admin import auth

    firebase_admin.initialize_app()

automation_lock = threading.Lock()
operation_status = {}

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = MAX_REQUEST_BYTES
if LOCAL_MODE:
    app.logger.setLevel(logging.INFO)


def _local_browser_profile(uid, data):
    credentials = data.get('edeskCredenciais') or {}
    email = str(credentials.get('email') or '').strip().lower() if isinstance(credentials, dict) else ''
    identity = hashlib.sha256((uid + '\0' + email).encode('utf-8')).hexdigest()
    root = APP_ROOT / '.edesk-local' / 'browser-profiles'
    path = root / identity
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    return str(path)


def _allowed_origins() -> set[str]:
    configured = os.environ.get("EDESK_API_ORIGINS", "")
    if configured.strip():
        return {
            origin.strip().rstrip("/")
            for origin in configured.split(",")
            if origin.strip()
        }
    return DEFAULT_ORIGINS


def _origin_is_allowed(origin: str) -> bool:
    normalized_origin = origin.rstrip("/")
    if normalized_origin in _allowed_origins():
        return True

    parsed = urlsplit(normalized_origin)
    return (
        parsed.scheme == "http"
        and parsed.hostname in {"localhost", "127.0.0.1"}
    )


@app.before_request
def _handle_preflight():
    hosts = {"localhost", "127.0.0.1"}
    if LOCAL_MODE and central.enabled():
        hosts.add(central.address())
        if request.remote_addr not in {"127.0.0.1", "::1"} and not central.private_address(request.remote_addr or ''):
            return jsonify({"message": "A central está disponível somente na rede privada."}), 403
    if LOCAL_MODE and request.host.split(":", 1)[0] not in hosts:
        return jsonify({"message": "Endereço local inválido."}), 403
    origin = request.headers.get("Origin")
    if LOCAL_MODE and request.method == "POST" and not origin:
        return jsonify({"message": "Abra a integração pelo aplicativo web."}), 403
    if origin and not _origin_is_allowed(origin):
        return jsonify({"message": "Origem não autorizada."}), 403

    if request.method == "OPTIONS":
        return ("", 204)

    return None


@app.after_request
def _add_response_headers(response):
    if LOCAL_MODE and request.method == "POST" and request.view_args:
        action = request.view_args.get("action")
        if action in SCRIPTS:
            app.logger.info("E-Desk request finished: action=%s status=%s", action, response.status_code)
    response.headers["Cache-Control"] = "no-store"
    origin = request.headers.get("Origin")
    if origin and _origin_is_allowed(origin):
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Headers"] = (
            "Authorization, Content-Type"
        )
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        response.headers["Vary"] = "Origin"
        if LOCAL_MODE:
            response.headers["Access-Control-Allow-Private-Network"] = "true"
    return response


@app.errorhandler(RequestEntityTooLarge)
def _request_too_large(_error):
    return jsonify({"message": "A solicitação excede o limite permitido."}), 413


@app.get("/healthz")
def health_check():
    native = {}
    if LOCAL_MODE and os.name == 'nt':
        from local_edesk import local_files
        actions = sorted(getattr(local_files, 'SUPPORTED_ACTIONS', []))
        native = {'nativeActions': actions,
                  'durableLocalLinks': getattr(local_files, 'DURABLE_LINKS', False),
                  'nativeProjectLinkRecovery': getattr(local_files, 'PROJECT_LINK_RECOVERY', False),
                  'nativeSpreadsheetLayouts': list(getattr(local_files, 'SPREADSHEET_LAYOUTS', [])),
                  'nativeSpreadsheetSheetNames': getattr(local_files, 'SPREADSHEET_SHEET_NAMES', False),
                  'projectRootMove': getattr(local_files, 'PROJECT_ROOT_MOVE', False),
                  'verifiedProjectMove': getattr(local_files, 'VERIFIED_PROJECT_MOVE', False),
                  'nativeFilesVersion': getattr(local_files, 'PROTOCOL_VERSION', None)}
    return jsonify({"status": "ok", "service": "gerenciador-horas-edesk",
                    "commentPercentage": True,
                    "commentPercentageReceipt": True,
                    "hoursReconciliation": True,
                    "hoursTimesheet": True,
                    "workAudit": True,
                    "workEnumeration": True,
                    "workGridImport": True,
                    "requestTitleImport": True,
                    "workInbox": True,
                    "standalonePercentage": True,
                    "integrationPackageVersion": os.environ.get('EDESK_INTEGRATION_VERSION'),
                    "mode": "central" if LOCAL_MODE and central.enabled() else "local" if LOCAL_MODE else "cloud",
                    "browserVisible": LOCAL_MODE,
                    "busy": automation_lock.locked(), "nativeFiles": LOCAL_MODE and os.name == 'nt',
                    'excelMirror': 'preview' in native.get('nativeActions', []), **native})


def _authenticated_user(*, pairing=False):
    authorization = request.headers.get("Authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        return None, (jsonify({"message": "Autenticação necessária."}), 401)

    try:
        if LOCAL_MODE:
            from local_edesk.authentication import verify_token
            user = verify_token(token)
        else:
            user = auth.verify_id_token(token)
        if LOCAL_MODE and not pairing and not central.permitted(user["sub"]):
            return None, (jsonify({"message": "Esta conta não foi autorizada pelo responsável pelo computador central."}), 403)
    except ValueError:
        return None, (jsonify({"message": "Token Firebase inválido."}), 401)
    except Exception as error:
        if not LOCAL_MODE and isinstance(error, auth.InvalidIdTokenError):
            return None, (jsonify({"message": "Token Firebase inválido."}), 401)
        # Never log tokens, credentials or request bodies.
        app.logger.warning("Firebase token verification failed.")
        return None, (
            jsonify({"message": "Não foi possível validar a autenticação."}),
            503,
        )

    return user, None


@app.post('/api/local-files')
def local_files_action():
    if not LOCAL_MODE or request.remote_addr not in {'127.0.0.1', '::1'} or request.host.split(':', 1)[0] not in {'localhost', '127.0.0.1'}:
        return jsonify({'message': 'Abra os arquivos somente pela integração deste computador.'}), 403
    user, error = _authenticated_user(pairing=True)
    if error is not None:
        return error
    body = request.get_json(silent=True)
    if not isinstance(body, dict):
        return jsonify({'message': 'Solicitação local inválida.'}), 400
    try:
        from local_edesk.local_files import execute
        return jsonify(execute(user['sub'], body, verified_user=user))
    except PermissionError as error:
        return jsonify({'message': str(error)}), 403
    except (ValueError, FileNotFoundError) as error:
        message = 'O arquivo ou pasta mudou de lugar. Selecione novamente no editor.' if isinstance(error, FileNotFoundError) else str(error)
        return jsonify({'message': message}), 400
    except Exception:
        return jsonify({'message': 'Não foi possível abrir o arquivo original. Verifique as permissões e o programa padrão no Windows.'}), 500


@app.get('/api/edesk/session')
def edesk_session():
    user, error = _authenticated_user()
    if error is not None:
        return error
    return jsonify({'uid': user['sub'], 'authorized': True})


@app.post('/api/edesk/central/pair')
def pair_central():
    if not LOCAL_MODE or not central.enabled():
        return jsonify({'message': 'Execute Iniciar central E-Desk.cmd neste computador.'}), 409
    if request.remote_addr not in {'127.0.0.1', '::1'} or request.host.split(':', 1)[0] not in {'localhost', '127.0.0.1'}:
        return jsonify({'message': 'A primeira autorização deve ser feita no computador central.'}), 403
    user, error = _authenticated_user(pairing=True)
    if error is not None:
        return error
    try:
        central.pair(user['sub'])
    except PermissionError as error:
        return jsonify({'message': str(error)}), 403
    return jsonify({'url': f'http://{central.address()}:8765', 'authorized': True})


@app.route('/api/edesk/central/access', methods=['GET', 'POST'])
def central_access():
    if not LOCAL_MODE or not central.enabled():
        return jsonify({'message': 'O serviço não está no modo central.'}), 409
    user, error = _authenticated_user()
    if error is not None:
        return error
    try:
        body = request.get_json(silent=True) if request.method == 'POST' else None
        if request.method == 'POST' and (not isinstance(body, dict) or 'users' not in body):
            raise ValueError('Lista de contas inválida.')
        data = central.access(user['sub'], body['users'] if body else None)
        return jsonify({'users': data['users']})
    except PermissionError as error:
        return jsonify({'message': str(error)}), 403
    except ValueError as error:
        return jsonify({'message': str(error)}), 400


@app.get("/api/edesk/status")
def edesk_status():
    user, error = _authenticated_user()
    if error is not None:
        return error
    status = operation_status.get(user["sub"], {})
    stage = status.get("stage", "idle")
    path = status.get("path")
    if path and path.exists():
        try:
            stage = json.loads(path.read_text(encoding="utf-8")).get("stage", stage)
        except (OSError, ValueError):
            pass
    counters = {}
    if path and path.exists():
        try:
            counters = json.loads(path.read_text(encoding='utf-8'))
        except (OSError, ValueError):
            pass
    return jsonify({"stage": stage, "operationId": status.get("operationId"),
        "completed": counters.get('completed', status.get('completed', 0)),
        "total": status.get('total', 0)})


@app.post("/api/edesk/review")
def review_hours():
    from local_edesk import journal
    user, error = _authenticated_user()
    if error is not None:
        return error
    body = request.get_json(silent=True) or {}
    if not isinstance(body, dict):
        return _failure("Dados inválidos.", 400)
    data = body.get("request", {})
    if not isinstance(data, dict):
        return _failure("Dados inválidos.", 400)
    existing = journal.states(user["sub"])
    items = [{"key": key, "state": existing.get(key, "new")}
             for _, _, key in journal.entries(data)]
    return jsonify({"items": items})


@app.route("/api/edesk/history", methods=["GET", "POST"])
def edesk_history():
    from local_edesk import journal
    user, error = _authenticated_user()
    if error is not None:
        return error
    if request.method == "POST":
        if automation_lock.locked():
            return _failure("Aguarde o envio terminar antes de conferir ou restaurar o histórico.", 409)
        body = request.get_json(silent=True) or {}
        if not isinstance(body, dict):
            return _failure("Histórico inválido.", 400)
        items = body.get("items")
        if not isinstance(items, dict) or len(items) > 100000 or any(
            not isinstance(key, str) or len(key) != 64 or
            any(c not in "0123456789abcdef" for c in key) or
            not isinstance(value, str) or value not in {"confirmed", "uncertain"} for key, value in items.items()
        ):
            return _failure("Histórico de envios inválido.", 400)
        if not automation_lock.acquire(blocking=False):
            return _failure("Aguarde o envio terminar antes de restaurar o histórico.", 409)
        try:
            existing = journal.states(user["sub"])
            for state in ("confirmed", "uncertain"):
                journal.set_state(user["sub"], [key for key, value in items.items()
                                  if value == state and existing.get(key) != "confirmed"], state)
        finally:
            automation_lock.release()
    return jsonify({"items": journal.states(user["sub"])})


def _validate_automation_request(action: str, data: object, send: object):
    if not isinstance(data, dict):
        return "Os dados da automação devem ser um objeto JSON."
    if not isinstance(send, bool):
        return "O campo enviar deve ser verdadeiro ou falso."

    credentials = data.get("edeskCredenciais")
    if not isinstance(credentials, dict):
        return "Informe as credenciais do E-Desk para esta execução."
    email = credentials.get("email")
    password = credentials.get("senha")
    if (
        not isinstance(email, str)
        or not email.strip()
        or not isinstance(password, str)
        or not password
    ):
        return "As credenciais do E-Desk estão incompletas."

    url = data.get("url")
    if url is not None:
        if not isinstance(url, str):
            return "O endereço do E-Desk é inválido."
        parsed_url = urlsplit(url)
        if (
            parsed_url.scheme != "https"
            or parsed_url.hostname not in EDESK_URL_HOSTS
        ):
            return "A automação só pode acessar os domínios oficiais do E-Desk."

    if action == 'recebidos':
        if send:
            return 'A busca de trabalhos recebidos permite somente consulta.'
    elif action == "conferencia":
        if send:
            return 'A conferencia permite somente consulta, sem envio.'
        targets = data.get('solicitacoes')
        if not isinstance(targets, list) or not 1 <= len(targets) <= 100:
            return 'Selecione entre 1 e 100 solicitacoes por consulta.'
        for target in targets:
            if not isinstance(target, dict) or not str(target.get('solicitacao', '')).isdigit():
                return 'Informe numeros validos de solicitacao.'
            works = target.get('trabalhos', [])
            if not isinstance(works, list) or len(works) > 100 or any(not str(work).isdigit() for work in works):
                return 'Informe numeros validos de trabalho.'
        if 'includeHours' in data and not isinstance(data['includeHours'], bool):
            return 'A opcao de horas deve ser verdadeira ou falsa.'
    elif action == "fases":
        if not send:
            return "A atualização de fases exige confirmação de envio."
        if not isinstance(data.get("fases"), list) or not data["fases"]:
            return "Informe ao menos uma fase para atualizar."
    elif action == "horas":
        if not isinstance(data.get("trabalhos"), list) or not data["trabalhos"]:
            return "Informe ao menos um trabalho para registrar."
    elif action in {"comentarios", "percentual"}:
        from edesk_bot.comment_percentage import parse_percentage
        try:
            percentage = parse_percentage(data.get('percentualRealizado'))
        except ValueError as error:
            return str(error)

        if action == 'percentual':
            if percentage is None or not send:
                return 'Informe a porcentagem e confirme a atualização do trabalho.'
            if not str(data.get('solicitacao') or '').strip() or not str(data.get('idTrabalho') or '').strip():
                return 'Informe a solicitação e o trabalho da porcentagem.'
            if data.get('texto') or data.get('imagemBase64'):
                return 'O envio de porcentagem não recebe conteúdo de comentário.'

        if not isinstance(data.get("solicitacao"), (str, int)):
            return "Informe a solicitação do comentário."
        if not isinstance(data.get("idTrabalho"), (str, int)):
            return "Informe o trabalho do comentário."
        if not send and not data.get("texto") and not data.get("imagemBase64"):
            return "Informe o conteúdo do comentário de teste."

    return None


def _last_json_object(output: str):
    for line in reversed(output.splitlines()):
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            return value
    return None


def _failure(message: str, status_code: int, response_body: str = ""):
    return (
        jsonify(
            {
                "confirmed": False,
                "statusCode": status_code,
                "message": message,
                "responseBody": response_body,
            }
        ),
        status_code,
    )


def _automation_failure_message(output: str):
    if 'EDESK_PERCENTAGE_PENDING' in output:
        return ('O E-Desk respondeu ao salvamento do comentario, mas o percentual nao foi confirmado. '
                'Confira o comentario e o %Realizado no E-Desk antes de reenviar para evitar duplicidade.')

    if "EDESK_COMMENT_REQUEST_NOT_FOUND" in output:
        return ('A integração não localizou a solicitação na Minha Grid. '
                'Nenhum comentário foi enviado nesta tentativa. Confira o número vinculado ao projeto e o acesso dessa conta à solicitação.')

    if "EDESK_COMMENT_BUTTON_NOT_FOUND" in output:
        return ('O botão Comentário não ficou disponível na solicitação. '
                'Nenhum comentário foi enviado nesta tentativa. Confira se essa conta pode cadastrar comentários.')
    if "EDESK_COMMENT_TAB_NOT_OPENED" in output:
        return ('Não foi possível selecionar a aba Comentários da solicitação. '
                'Nenhum comentário foi enviado nesta tentativa. Confira se essa conta tem acesso aos comentários.')
    if "EDESK_COMMENT_REQUEST_NOT_OPENED" in output:
        return ("A integração não abriu o comentário na solicitação. Nenhum comentário foi enviado nesta tentativa. "
                "Confira se o botão Comentários está disponível nessa solicitação.")
    if "EDESK_COMMENT_WORK_NOT_OPENED" in output:
        return ('A integração não abriu a tela do trabalho a partir da Minha Grid. '
                'Nenhum comentário foi enviado nesta tentativa. Confira a solicitação e o trabalho vinculados ao projeto.')

    if "EDESK_GRID_SEARCH_NOT_READY" in output:
        return ('A Minha Grid não disponibilizou o campo de pesquisa da solicitação. '
                'Nenhum comentário foi enviado nesta tentativa. Confira o acesso ao E-Desk e tente novamente.')

    # Return only fixed messages, never raw logs containing user data or session URLs.
    if "Tempo limite de autenticação excedido" in output:
        return ("O login no E-Desk não foi concluído. Confira suas credenciais e conclua "
                "o login na janela do E-Desk antes de tentar novamente." if LOCAL_MODE else
                "O login no E-Desk não foi concluído. Confira suas credenciais.")
    if "Executable doesn't exist" in output:
        return "O navegador da integração não está instalado. Execute a instalação da integração E-Desk."
    return ("O E-Desk não confirmou a operação. Confira a janela do E-Desk e os registros "
            "antes de reenviar." if LOCAL_MODE else
            "O E-Desk não confirmou a conclusão da automação.")


@app.post("/api/edesk/<action>")
def run_edesk_automation(action: str):
    if action not in SCRIPTS:
        return jsonify({"message": "Automação não encontrada."}), 404

    _user, auth_error = _authenticated_user()
    if auth_error is not None:
        return auth_error

    try:
        body = request.get_json()
    except BadRequest:
        return jsonify({"message": "O corpo da solicitação não é JSON válido."}), 400

    if not isinstance(body, dict) or "request" not in body:
        return jsonify({"message": "A solicitação da automação está incompleta."}), 400

    data = body["request"]
    send = body.get("enviar")
    validation_error = _validate_automation_request(action, data, send)
    if validation_error:
        return jsonify({"message": validation_error}), 400

    script = SCRIPTS[action]
    data["enviar"] = send

    if not automation_lock.acquire(blocking=False):
        return _failure("Uma operação do E-Desk já está em andamento neste computador. Aguarde sua conclusão.", 409)
    try:
        uid = _user["sub"]
        keys, skipped = [], 0
        if action == "horas" and send:
            from local_edesk import journal
            try:
                data, keys, skipped = journal.prepare(uid, data, body.get("retryUncertain") is True)
            except ValueError as error:
                return _failure(str(error), 409)
            if not keys:
                return jsonify({'confirmed': True, 'statusCode': 200, 'completed': skipped,
                    'total': skipped, 'message': f'{skipped} hora(s) já confirmadas. Nenhum cadastro foi repetido. Envio finalizado com sucesso.'})
        operation_status[uid] = {"operationId": str(body.get("operationId") or uuid.uuid4()), "stage": "opening"}
        total = len(keys) if action == 'horas' else len(data.get('solicitacoes', [])) if action == 'conferencia' else len(data.get('fases', [])) if action == 'fases' else 1
        operation_status[uid]['total'] = total
        app.logger.info("E-Desk automation started: action=%s browser_visible=%s", action, LOCAL_MODE)
        with tempfile.TemporaryDirectory(prefix="edesk_request_") as directory:
            work_dir = Path(directory)
            data_dir = work_dir / "edesk_data"
            data_dir.mkdir(mode=0o700)
            request_file = work_dir / "request.json"
            request_file.write_text(
                json.dumps(data, ensure_ascii=False),
                encoding="utf-8",
            )
            request_file.chmod(0o600)

            progress_file = work_dir / "progress.json"
            events_file = work_dir / "events.jsonl"
            operation_status[uid]["path"] = progress_file

            environment = {
                "EDESK_DATA_DIR": str(data_dir),
                "EDESK_HEADLESS": "true",
                "PATH": os.environ.get("PATH", ""),
                "PLAYWRIGHT_BROWSERS_PATH": os.environ.get(
                    "PLAYWRIGHT_BROWSERS_PATH",
                    "/ms-playwright",
                ),
                "PYTHONUNBUFFERED": "1",
                "PYTHONUTF8": "1",
                "TMPDIR": str(work_dir),
            }
            if LOCAL_MODE:
                environment = dict(os.environ, EDESK_DATA_DIR=str(data_dir),
                                   EDESK_HEADLESS="false", PYTHONUTF8="1",
                                   PYTHONUNBUFFERED="1")
            if LOCAL_MODE:
                environment['EDESK_PROFILE_DIR'] = _local_browser_profile(uid, data)
                environment['EDESK_DIAGNOSTICS_DIR'] = str(APP_ROOT / '.edesk-local' / 'diagnosticos' / hashlib.sha256(uid.encode('utf-8')).hexdigest())
            environment.update(EDESK_PROGRESS_FILE=str(progress_file), EDESK_EVENTS_FILE=str(events_file))
            environment['EDESK_PROGRESS_TOTAL'] = str(total)
            if keys:
                journal.set_state(uid, keys, "pending")

            try:
                process = subprocess.Popen(
                    [
                        sys.executable,
                        str(EDESK_SCRIPTS_DIR / script),
                        str(request_file),
                    ],
                    cwd=EDESK_SCRIPTS_DIR,
                    env=environment,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    start_new_session=True,
                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                )
            except OSError:
                if keys:
                    journal.delete(uid, keys)
                app.logger.exception(
                    "Could not start E-Desk automation: %s",
                    action,
                )
                return _failure(
                    "Não foi possível iniciar a automação do E-Desk.",
                    503,
                )

            try:
                stdout, _stderr = process.communicate(
                    timeout=SCRIPT_TIMEOUT_SECONDS,
                )
            except subprocess.TimeoutExpired:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
                else:
                    os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
                if keys:
                    journal.finish(uid, keys, events_file)
                app.logger.warning("E-Desk automation timed out: %s", action)
                return _failure(
                    "A automação do E-Desk excedeu o tempo limite.",
                    504,
                )

            if progress_file.exists():
                try:
                    operation_status[uid]['completed'] = json.loads(progress_file.read_text(encoding='utf-8')).get('completed', 0)
                except (OSError, ValueError):
                    pass
            uncertain = journal.finish(uid, keys, events_file) if keys else 0
            result = _last_json_object(stdout) if action in {"fases", "percentual", "comentarios", "horas", "conferencia", "recebidos"} else None
            if keys:
                states = journal.states(uid)
                verified = sum(states.get(key) == 'confirmed' for key in keys)
                if verified == len(keys):
                    # A browser cleanup/navigation error cannot undo verified
                    # registrations. Every key still needs its persisted receipt.
                    if process.returncode != 0:
                        app.logger.warning('Hours confirmed; browser cleanup exited with code %s', process.returncode)
                    message = f'{verified} hora(s) conferidas no E-Desk. Nenhuma hora pendente. Cadastro finalizado com sucesso.'
                    if result and result.get('operation') == 'horas' and result.get('retried'):
                        message += f" {result['retried']} hora(s) reprocessadas após conferência de ausência."
                    if skipped:
                        message += f' {skipped} hora(s) já confirmadas foram preservadas.'
                    operation_status[uid].update(completed=len(keys), stage='finished')
                    return jsonify({'confirmed': True, 'statusCode': 200, 'completed': verified + skipped,
                        'total': len(keys) + skipped, 'message': message,
                        'responseBody': json.dumps(result, ensure_ascii=False) if result else ''})
            if process.returncode != 0:
                app.logger.warning(
                    "E-Desk automation failed: action=%s exit_code=%s",
                    action,
                    process.returncode,
                )
                return _failure(
                    result['message'] if action in {'horas', 'conferencia', 'recebidos'} and result and result.get('operation') == action
                        and isinstance(result.get('message'), str) else _automation_failure_message(stdout + "\n" + _stderr),
                    502,
                    json.dumps(result, ensure_ascii=False) if result else "",
                )

            if action == 'comentarios' and send and data.get('percentualRealizado') is not None and (
                result is None or result.get('ok') is not True
                or result.get('operation') != 'comentarios'
                or result.get('commentSaved') is not True
                or result.get('percentageConfirmed') is not True
            ):
                return _failure('A integração não confirmou a porcentagem. Confira o comentário no E-Desk e use Enviar só % para não duplicá-lo.',
                    502, json.dumps(result, ensure_ascii=False) if result else '')

            if action in {"fases", "percentual", "conferencia", "recebidos"} and (
                result is None or result.get("ok") is not True
                or (action == 'percentual' and result.get('operation') != 'percentual')
                or (action == 'conferencia' and (result.get('operation') != 'conferencia' or not isinstance(result.get('rows'), list)))
                or (action == 'recebidos' and (result.get('operation') != 'recebidos' or not isinstance(result.get('rows'), list)))
            ):
                message = (
                    result.get("message")
                    if result and isinstance(result.get("message"), str)
                    else "O E-Desk não confirmou a atualização."
                )
                return _failure(
                    message,
                    502,
                    json.dumps(result, ensure_ascii=False) if result else "",
                )

            message = (
                result.get("message")
                if result and isinstance(result.get("message"), str)
                else "Operação concluída no E-Desk."
            )
            if keys:
                states = journal.states(uid)
                missing = sum(states.get(key) != 'confirmed' for key in keys)
                if missing:
                    return _failure(
                        f'{missing} hora(s) aguardam conferência no E-Desk. '
                        'O cadastro completo não foi confirmado. Confira os registros antes de reenviar.', 502)
            if skipped:
                message += f" {skipped} hora(s) já confirmadas foram ignoradas."
            return jsonify(
                {
                    "confirmed": True,
                    "completed": operation_status[uid].get('completed', 0),
                    "total": operation_status[uid].get('total', 0),
                    "statusCode": 200,
                    "message": message,
                    "responseBody": (
                        json.dumps(result, ensure_ascii=False) if result else ""
                    ),
                }
            )
    except OSError:
        app.logger.exception("Could not prepare E-Desk request: %s", action)
        return _failure(
            "Não foi possível preparar a automação do E-Desk.",
            500,
        )
    finally:
        if _user and _user.get("sub") in operation_status:
            status = operation_status[_user["sub"]]
            progress_path = status.get('path')
            if progress_path and progress_path.exists():
                try:
                    status['completed'] = json.loads(progress_path.read_text(encoding='utf-8')).get('completed', 0)
                except (OSError, ValueError):
                    pass
            status.pop("path", None)
            status["stage"] = "finished"
        automation_lock.release()
