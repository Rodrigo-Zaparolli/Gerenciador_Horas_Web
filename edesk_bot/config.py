import os
from pathlib import Path

_DATA_DIR = Path(
    os.environ.get("EDESK_DATA_DIR") or Path(__file__).resolve().parent
).resolve()

EDESK_URL = "https://promob.e-desk.com.br"

PROFILE_DIR = Path(os.environ.get("EDESK_PROFILE_DIR") or _DATA_DIR / "perfil").resolve()
SCREENSHOTS_DIR = _DATA_DIR / "screenshots"
LOGS_DIR = _DATA_DIR / "logs"
HEADLESS = os.environ.get("EDESK_HEADLESS", "").lower() in {
    "1",
    "true",
    "yes",
}

COMENTARIO_TIPOS = {
    "Interno": "0",
    "Externo": "1",
    "Padrão": "3",
    "Padrão (Interno)": "4",
}

def restore_session_cookies(context):
    if not os.environ.get('EDESK_PROFILE_DIR'):
        return
    import json
    try:
        path = PROFILE_DIR / 'session-cookies.json'
        if path.exists():
            context.add_cookies(json.loads(path.read_text(encoding='utf-8')))
    except Exception:
        pass  # An unavailable session falls back to normal authentication.


def save_session_cookies(context):
    if not os.environ.get('EDESK_PROFILE_DIR'):
        return
    import json
    try:
        path = PROFILE_DIR / 'session-cookies.json'
        temporary = path.with_suffix('.tmp')
        temporary.write_text(json.dumps(context.cookies()), encoding='utf-8')
        temporary.chmod(0o600)
        temporary.replace(path)
    except Exception:
        pass  # Session caching cannot change delivery confirmation.
