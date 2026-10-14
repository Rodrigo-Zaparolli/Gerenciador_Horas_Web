"""Run only on loopback: python -m local_edesk.server."""
import os

os.environ["EDESK_LOCAL_MODE"] = "true"

from cloud_run.main import app
from waitress import serve
from local_edesk import central


if __name__ == "__main__":
    listen = '127.0.0.1:8765'
    if central.enabled():
        listen += f' {central.address()}:8765'
    print(f"Integração E-Desk ativa: {listen}", flush=True)
    serve(app, listen=listen, threads=8,
          channel_timeout=960, max_request_body_size=15 * 1024 * 1024)
