"""Shared log formatting; progress and delivery receipts stay with the caller."""
import os
from pathlib import Path


def emit_log(message, prefix, path=None):
    text = str(message)
    # Decorative lines add volume without diagnostic evidence. DEBUG keeps the
    # original detail. Never suppress repeated operational or receipt messages.
    if os.environ.get('EDESK_LOG_LEVEL', 'INFO').upper() != 'DEBUG':
        stripped = text.strip()
        if not stripped or set(stripped) <= set('=-*_# '):
            return
    line = f'{prefix} {text}'
    print(line, flush=True)
    if path is not None:
        try:
            with Path(path).open('a', encoding='utf-8') as stream:
                stream.write(line + '\n')
        except OSError:
            pass  # Logging failure cannot cause a repeated delivery.
