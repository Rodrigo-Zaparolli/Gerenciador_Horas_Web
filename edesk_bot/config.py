import os
from pathlib import Path

_DATA_DIR = Path(
    os.environ.get("EDESK_DATA_DIR") or Path(__file__).resolve().parent
).resolve()

EDESK_URL = "https://promob.e-desk.com.br"

PROFILE_DIR = _DATA_DIR / "perfil"
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