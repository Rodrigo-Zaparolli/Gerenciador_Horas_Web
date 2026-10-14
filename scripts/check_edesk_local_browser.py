"""Check public-site to loopback access; never run an E-Desk automation."""
import json
from playwright.sync_api import sync_playwright

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(channel="chrome", headless=True)
    context = browser.new_context()
    page = context.new_page()
    session = context.new_cdp_session(page)
    context_id = session.send("Target.getTargetInfo")["targetInfo"]["browserContextId"]
    session.send("Browser.setPermission", {"permission": {"name": "local-network-access"},
                 "setting": "granted", "origin": "https://gerenciador-horas.web.app",
                 "browserContextId": context_id})
    try:
        session.send("Browser.setPermission", {"permission": {"name": "loopback-network"},
                     "setting": "granted", "origin": "https://gerenciador-horas.web.app",
                     "browserContextId": context_id})
    except Exception:
        pass  # Older Chrome versions use the single permission above.
    page.on("console", lambda message: print(message.text) if message.type == "error" else None)
    page.goto("https://gerenciador-horas.web.app", wait_until="networkidle", timeout=60000)
    result = page.evaluate("""async () => {
      const response = await fetch('http://127.0.0.1:8765/healthz');
      const status = await response.json();
      const denied = await fetch('http://127.0.0.1:8765/api/edesk/horas', {
        method: 'POST', headers: {'Authorization': 'Bearer invalid-test-token', 'Content-Type': 'application/json'},
        body: JSON.stringify({request: {}, enviar: false})
      });
      const protectedEndpoints = {};
      const nativeFiles = await fetch('http://127.0.0.1:8765/api/local-files', {
        method: 'POST', headers: {'Authorization': 'Bearer invalid-test-token', 'Content-Type': 'application/json'},
        body: JSON.stringify({action: 'open', reference: 'invalid'})
      });
      protectedEndpoints.localFiles = nativeFiles.status;
      for (const name of ['status', 'history']) {
        const result = await fetch('http://127.0.0.1:8765/api/edesk/' + name, {
          headers: {'Authorization': 'Bearer invalid-test-token'}
        });
        protectedEndpoints[name] = result.status;
      }
      return {health: status, unauthenticatedStatus: denied.status, protectedEndpoints};
    }""")
    assert result["health"]["service"] == "gerenciador-horas-edesk", result
    assert result["health"]["mode"] == "local", result
    assert result["unauthenticatedStatus"] == 401, result
    assert result["health"]["nativeFiles"] is True, result
    assert result["protectedEndpoints"] == {"status": 401, "history": 401, "localFiles": 401}, result
    print(json.dumps(result))
    browser.close()
