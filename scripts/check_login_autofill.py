from pathlib import Path
from functools import partial
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
import threading,json
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1]/'build/login-autofill-probe'
class H(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
s=ThreadingHTTPServer(('127.0.0.1',0),partial(H,directory=str(root)));threading.Thread(target=s.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  for channel in ['chrome','msedge']:
   b=p.chromium.launch(channel=channel,headless=True);page=b.new_page(viewport={'width':1280,'height':900});page.goto(f'http://127.0.0.1:{s.server_port}');page.wait_for_selector('flt-glass-pane',state='attached');page.locator('flt-semantics-placeholder').evaluate('(e)=>e.click()');page.get_by_role('textbox',name='E-mail',exact=True).click();page.wait_for_timeout(300)
   fields=page.locator('input').evaluate_all('(es)=>es.map(e=>({type:e.type,autocomplete:e.autocomplete,name:e.name,aria:e.getAttribute("aria-label")}))')
   assert any(f['name']=='username' for f in fields),fields
   page.get_by_role('textbox',name='Senha',exact=True).click();page.wait_for_timeout(300)
   fields=page.locator('input').evaluate_all('(es)=>es.map(e=>({type:e.type,autocomplete:e.autocomplete,name:e.name}))')
   assert any(f['type']=='password' and f['autocomplete']=='current-password' for f in fields),fields
   print('LOGIN_AUTOFILL_HINTS_OK',channel,flush=True)
   b.close()
finally:s.shutdown()
