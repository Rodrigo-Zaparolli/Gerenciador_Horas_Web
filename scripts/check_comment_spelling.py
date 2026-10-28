"""Real keyboard and local Hunspell tests; native browser spellcheck disabled."""
import threading,json
from pathlib import Path
from functools import partial
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  if self.path=='/probe':
   body=b'<html lang="pt-BR"><head><base href="/"></head><body><div id="editor" style="height:400px;color:#123"></div><script src="comment_native_editor.js"></script></body></html>'
   self.send_response(200);self.send_header('Content-Type','text/html');self.end_headers();self.wfile.write(body)
  else:super().do_GET()
s=ThreadingHTTPServer(('127.0.0.1',0),partial(Handler,directory=str(ROOT/'web')));threading.Thread(target=s.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  for channel in ['chrome','msedge']:
   browser=p.chromium.launch(channel=channel,headless=True);page=browser.new_page();errors=[]
   page.on('pageerror',lambda e:errors.append(str(e)))
   page.goto(f'http://127.0.0.1:{s.server_port}/probe')
   page.evaluate("async delta=>{window.handle=await gerenciadorNativeComment.create(document.querySelector('#editor'),JSON.stringify(delta),(json)=>window.delta=JSON.parse(json),()=>{});handle.editor.root.spellcheck=false;}",[{'insert':'\n'}])
   editor=page.locator('.ql-editor');editor.click()
   for word in ['Este','comentario','precisa','de','correcao']:
    page.keyboard.type(word);page.keyboard.press('Space')
   assert page.evaluate('handle.editor.getText()')=='Este comentario precisa de correcao \n'
   page.wait_for_function("Number(document.querySelector('.ql-editor').dataset.spellingErrors)>=2",timeout=30000)
   rect=page.evaluate("""()=>{for(const h of CSS.highlights.values())for(const range of h.values())if(range.toString()==='comentario'){const r=range.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}}}""")
   assert rect,'missing real highlight range'
   page.screenshot(path=str(ROOT/f'build/comment-local-spelling-underlines-{channel}.png'))
   page.mouse.click(rect['x'],rect['y'],button='right')
   menu=page.locator('.comment-spelling-menu');menu.wait_for()
   suggestion=menu.get_by_role('menuitem',name='coment\u00e1rio',exact=True);suggestion.wait_for(timeout=15000);suggestion.click()
   assert 'Este coment\u00e1rio precisa de correcao' in page.evaluate('handle.editor.getText()')
   assert 'spelling' not in json.dumps(page.evaluate('window.delta'))
   editor.click();page.keyboard.press('Control+End');page.keyboard.press('Space');page.keyboard.type('Fim')
   assert ' Fim' in page.evaluate('handle.editor.getText()')
   page.wait_for_function("Number(document.querySelector('.ql-editor').dataset.spellingErrors)>0",timeout=15000)
   page.screenshot(path=str(ROOT/f'build/comment-local-spelling-{channel}.png'))
   page.evaluate('gerenciadorNativeComment.destroy(handle)')
   assert page.locator('.comment-spelling-status').count()==0
   assert page.evaluate('CSS.highlights.size')==0
   assert not errors,errors
   print('LOCAL_PT_SPELLING_SPACE_SUGGESTION_CLEAN_DELTA_PASS',channel,flush=True)
   browser.close()
finally:s.shutdown()
