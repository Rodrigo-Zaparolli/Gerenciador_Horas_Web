"""Small files shared with the local server; no customer text or credentials."""
import json
import os
from pathlib import Path

_completed = set()

def completed(key):
    _completed.add(str(key))
    stage('sending')


def stage(value):
    location = os.environ.get("EDESK_PROGRESS_FILE")
    if location:
        path = Path(location)
        temporary = path.with_suffix(".tmp")
        try:
            temporary.write_text(json.dumps({"stage": value,
                "completed": len(_completed),
                "total": int(os.environ.get('EDESK_PROGRESS_TOTAL', '0'))}), encoding="utf-8")
            temporary.replace(path)
        except (OSError, ValueError):
            pass  # Progress must never interfere with delivery.


def observe_log(message):
    normalized = str(message).lower()
    if any(text in normalized for text in ("aguardando login", "login manual", "aguardando confirmação do login", "tela de login detectada", "tentando login", "tentativa de login")):
        stage("login")
    elif any(text in normalized for text in ("login confirmado", "login automático confirmado", "autenticação confirmada", "já autenticada")):
        stage("preparing")
    elif ("clicando" in normalized and ("salvar" in normalized or "enviar" in normalized)) or normalized in {"salvando fases no e-desk", "salvando comentário"}:
        stage("sending")


def hour_event(hour, state):
    location = os.environ.get("EDESK_EVENTS_FILE")
    key = hour.get("_sendKey")
    if location and key:
        # Persist the intent before clicking Save. Failure here stops the send.
        with Path(location).open("a", encoding="utf-8") as file:
            file.write(json.dumps({"key": key, "state": state}) + "\n")
            file.flush()
            os.fsync(file.fileno())
        if state == 'confirmed':
            completed(key)
