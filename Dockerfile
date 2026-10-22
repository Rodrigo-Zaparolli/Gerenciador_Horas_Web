FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

WORKDIR /app

COPY cloud_run/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt \
    && playwright install --with-deps chromium

COPY cloud_run /app/cloud_run
COPY edesk_bot/config.py /app/edesk_bot/config.py
COPY edesk_bot/edesk_comentario.py /app/edesk_bot/edesk_comentario.py
COPY edesk_bot/edesk_percentual.py /app/edesk_bot/edesk_percentual.py
COPY edesk_bot/edesk_fases.py /app/edesk_bot/edesk_fases.py
COPY edesk_bot/edesk_horas.py /app/edesk_bot/edesk_horas.py
COPY edesk_bot/comment_percentage.py /app/edesk_bot/comment_percentage.py
COPY edesk_bot/phase_confirmation.py /app/edesk_bot/phase_confirmation.py
COPY edesk_bot/send_progress.py /app/edesk_bot/send_progress.py
COPY edesk_bot/work_selection.py /app/edesk_bot/work_selection.py
COPY edesk_bot/hour_receipt.py /app/edesk_bot/hour_receipt.py
COPY edesk_bot/edesk_conferencia.py /app/edesk_bot/edesk_conferencia.py
COPY edesk_bot/edesk_recebidos.py /app/edesk_bot/edesk_recebidos.py
COPY local_edesk/__init__.py /app/local_edesk/__init__.py
COPY local_edesk/central.py /app/local_edesk/central.py
COPY local_edesk/journal.py /app/local_edesk/journal.py

CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT:-8080} --workers 1 --threads 1 --timeout 900 cloud_run.main:app"]
