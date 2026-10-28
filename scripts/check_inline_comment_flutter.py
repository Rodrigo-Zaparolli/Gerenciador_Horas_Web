import json,threading,sys
from pathlib import Path
from functools import partial
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'build/inline-spelling-probe'
class Handler(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),partial(Handler,directory=str(root)));threading.Thread(target=server.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  for channel in ['chrome','msedge']:
   browser=p.chromium.launch(channel=channel,headless=True);page=browser.new_context(viewport={'width':1200,'height':800}).new_page();errors=[]
   page.on('pageerror',lambda e:errors.append(str(e)))
   page.on('console',lambda e:errors.append(e.text) if e.type=='error' else None)
   page.goto(f'http://127.0.0.1:{server.server_port}/')
   editor=page.locator('.ql-editor');editor.wait_for(timeout=30000);assert editor.evaluate('e=>e.spellcheck') is True
   assert editor.get_attribute('lang')=='pt-BR'
   editor.evaluate('e=>e.spellcheck=false');editor.click();page.keyboard.type('comentario');page.wait_for_timeout(200)
   def state():return json.loads(page.locator('body').get_attribute('data-probe'))
   assert state()['text']=='comentario\n',state()
   page.keyboard.press('Space');page.keyboard.type('com');page.keyboard.press('Space');page.keyboard.type('espacos')
   assert state()['text']=='comentario com espacos\n',state()
   page.wait_for_function("Number(document.querySelector('.ql-editor').dataset.spellingErrors)>0",timeout=30000)
   rect=page.evaluate("""()=>{for(const h of CSS.highlights.values())for(const range of h.values())if(range.toString()==='comentario'){const r=range.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}}}""")
   assert rect,'local spelling underline missing inside Flutter modal'
   page.mouse.click(rect['x'],rect['y'],button='right')
   page.locator('.comment-spelling-menu').get_by_role('menuitem',name='coment\u00e1rio',exact=True).click(timeout=15000)
   assert state()['text']=='coment\u00e1rio com espacos\n',state()
   assert all('spelling' not in str(op.get('attributes',{})) for op in state()['delta'])
   page.keyboard.press('Control+a');page.keyboard.insert_text('coment\u00e1rio');page.wait_for_timeout(150)
   assert state()['text']=='coment\u00e1rio\n',state()
   page.keyboard.press('Tab');page.wait_for_timeout(150);assert state()['text']=='coment\u00e1rio\u00a0\u00a0\n',state()
   page.keyboard.press('Shift+Tab');page.wait_for_timeout(150);assert state()['text']=='coment\u00e1rio\n',state()
   page.keyboard.press('Control+a');page.keyboard.press('Control+b');page.wait_for_timeout(100)
   page.keyboard.press('ArrowRight');page.keyboard.type('!');page.wait_for_timeout(200)
   assert any(o.get('attributes',{}).get('bold') for o in state()['delta']),state()
   page.keyboard.press('Enter');page.keyboard.type('Segunda linha');page.wait_for_timeout(150)
   assert 'Segunda linha' in state()['text'],state()
   # Copy outside Flutter, then return to editor and paste with native Ctrl+V.
   page.mouse.click(100,780);page.wait_for_timeout(100)
   source=page.context.new_page();source.set_content('<textarea id="source"></textarea>')
   source.locator('#source').fill('Texto copiado\nCom duas linhas');source.locator('#source').select_text();source.keyboard.press('Control+c');source.close();page.bring_to_front()
   page.evaluate("window.addEventListener('paste',event=>document.body.setAttribute('data-clipboard-seen',JSON.stringify({text:event.clipboardData?.getData('text/plain'),target:event.target.tagName})),true)")
   editor.click();page.keyboard.press('Control+End');page.keyboard.press('Control+v');page.wait_for_timeout(250)
   assert 'Texto copiado\nCom duas linhas' in state()['text'],(state(),page.locator('body').get_attribute('data-clipboard-seen'))
   assert state()['legacy']==0,state()
   # Existing image insertion still goes through the same Flutter controller.
   page.mouse.click(305,64);page.wait_for_timeout(250)
   assert any(isinstance(o['insert'],dict) for o in state()['delta']),state()
   assert page.locator('.ql-editor img').count()==1
   editor.click();page.keyboard.press('Control+End');page.keyboard.type('depois');page.keyboard.press('Space');page.keyboard.type('da');page.keyboard.press('Space');page.keyboard.type('imagem')
   assert 'depois da imagem' in state()['text'],state()
   page.mouse.click(380,64);page.wait_for_timeout(250)
   page.screenshot(path=f'build/inline-spelling-flutter-{channel}.png')
   assert not errors,errors
   print('FLUTTER_INLINE_SPELLING_PASTE_TAB_FORMAT_IMAGE_PASS',channel,flush=True)
   browser.close()
finally:server.shutdown()
