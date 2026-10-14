"""Durable, user-scoped send ledger. Never stores passwords or comment text."""
import hashlib
import json
import os
import sqlite3
from datetime import datetime
from contextlib import contextmanager
from pathlib import Path


@contextmanager
def database():
    path = Path(os.environ.get("EDESK_JOURNAL_PATH") or
                Path(__file__).resolve().parents[1] / ".edesk-local/history.sqlite3")
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path, timeout=10)
    connection.execute("CREATE TABLE IF NOT EXISTS hours (uid TEXT, key TEXT, state TEXT, "
                       "updated TEXT DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(uid,key))")
    try:
        with connection:
            yield connection
    finally:
        connection.close()


def hour_key(work, hour):
    identity = [str(work.get(field, "")).strip() for field in ("solicitacao", "idTrabalho")]
    # Changing the description does not make the same time interval a new hour.
    for field, pattern in (("data", "%d/%m/%Y"), ("inicio", "%H:%M"), ("fim", "%H:%M")):
        value = str(hour.get(field, "")).strip()
        try:
            value = datetime.strptime(value, pattern).strftime(pattern)
        except ValueError:
            pass
        identity.append(value)
    tipo = str(hour.get("tipo") or "0").strip().lower()
    identity.append({"interno": "0", "externo": "1", "padrão": "3", "padrao": "3",
                     "padrão (interno)": "4", "padrao (interno)": "4"}.get(tipo, tipo))
    return hashlib.sha256(json.dumps(identity, ensure_ascii=False).encode()).hexdigest()


def entries(data):
    works = data.get("trabalhos", [])
    if not isinstance(works, list):
        return []
    return [(work, hour, hour_key(work, hour))
            for work in works if isinstance(work, dict) and isinstance(work.get("horas"), list)
            for hour in work["horas"] if isinstance(hour, dict)]


def states(uid):
    with database() as db:
        return dict(db.execute("SELECT key,state FROM hours WHERE uid=?", (uid,)))


def set_state(uid, keys, state):
    with database() as db:
        for key in keys:
            db.execute("INSERT INTO hours(uid,key,state) VALUES(?,?,?) "
                       "ON CONFLICT(uid,key) DO UPDATE SET state=excluded.state,updated=CURRENT_TIMESTAMP",
                       (uid, key, state))


def delete(uid, keys):
    with database() as db:
        db.executemany("DELETE FROM hours WHERE uid=? AND key=?", [(uid, key) for key in keys])


def prepare(uid, data, retry_uncertain=False):
    works = data.get("trabalhos")
    if not isinstance(works, list) or any(
        not isinstance(work, dict) or not isinstance(work.get("horas"), list) or
        not work["horas"] or any(not isinstance(hour, dict) for hour in work["horas"])
        for work in works
    ):
        raise ValueError("A lista de trabalhos e horas está incompleta.")
    existing = states(uid)
    items = entries(data)
    if not items:
        raise ValueError("Informe ao menos uma hora válida para enviar.")
    for work, hour, _ in items:
        if not str(work.get("solicitacao", "")).strip() or not str(work.get("idTrabalho", "")).strip():
            raise ValueError("Informe a solicitação e o trabalho de cada hora.")
        try:
            datetime.strptime(str(hour.get("data", "")), "%d/%m/%Y")
            start = datetime.strptime(str(hour.get("inicio", "")), "%H:%M")
            end = datetime.strptime(str(hour.get("fim", "")), "%H:%M")
            if start >= end:
                raise ValueError()
        except ValueError:
            raise ValueError("Há uma hora com data ou intervalo inválido.") from None
    keys = [key for _, _, key in items]
    if len(set(keys)) != len(keys):
        raise ValueError("Há horas repetidas na seleção. Remova a repetição antes de enviar.")
    if not retry_uncertain and any(existing.get(key) in {"pending", "uncertain"} for key in keys):
        raise ValueError("Há horas de uma tentativa anterior que precisam de conferência no E-Desk antes de reenviar.")
    if retry_uncertain:
        delete(uid, [key for key in keys if existing.get(key) in {'pending', 'uncertain'}])
    works, selected = [], []
    for work in data["trabalhos"]:
        hours = []
        for hour in work.get("horas", []):
            key = hour_key(work, hour)
            if existing.get(key) == "confirmed":
                continue
            hours.append({**hour, "_sendKey": key,
                          "_retryUnconfirmed": existing.get(key) in {'pending', 'uncertain'}})
            selected.append(key)
        if hours:
            works.append({**work, "horas": hours})
    return {**data, "trabalhos": works}, selected, len(keys) - len(selected)


def finish(uid, keys, events_file):
    attempted, confirmed, not_submitted = set(), set(), set()
    if events_file.exists():
        for line in events_file.read_text(encoding="utf-8").splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            key = event.get("key")
            if key not in keys:
                continue
            if event.get("state") == "started":
                attempted.add(key)
            elif event.get("state") == "confirmed":
                confirmed.add(key)
            elif event.get("state") == "not_submitted":
                not_submitted.add(key)
    attempted -= not_submitted
    set_state(uid, attempted - confirmed, "uncertain")
    set_state(uid, confirmed, "confirmed")
    delete(uid, set(keys) - attempted - confirmed)
    return len(attempted - confirmed)
