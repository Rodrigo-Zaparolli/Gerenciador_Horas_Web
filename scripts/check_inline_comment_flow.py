import json,threading,sys
from pathlib import Path
from functools import partial
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'web'
class Handler(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  if self.path=='/probe':
   body=b'<html><head><base href="/"></head><body><div id="editor" style="height:350px;color:#123"></div><textarea id="copy" style="margin-top:40px"></textarea><script src="comment_native_editor.js"></script></body></html>'
   self.send_response(200);self.send_header('Content-Type','text/html');self.end_headers();self.wfile.write(body)
  else:super().do_GET()
server=ThreadingHTTPServer(('127.0.0.1',0),partial(Handler,directory=str(root)));threading.Thread(target=server.serve_forever,daemon=True).start()
png='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
try:
 with sync_playwright() as p:
  for channel in ['chrome','msedge']:
   browser=p.chromium.launch(channel=channel,headless=True);page=browser.new_page();errors=[]
   page.on('pageerror',lambda e:errors.append(str(e)))
   def create(delta):
    page.goto(f'http://127.0.0.1:{server.server_port}/probe')
    page.evaluate("""async delta=>{window.events=0;window.model=delta;window.handle=await gerenciadorNativeComment.create(document.querySelector('#editor'),JSON.stringify(delta),(json)=>{window.events++;window.model=JSON.parse(json)},()=>{});}""",delta)
    return page.locator('.ql-editor')
   editor=create([{'insert':'\n'}]);assert editor.get_attribute('lang')=='pt-BR';assert editor.evaluate('(e)=>e.spellcheck') is True
   assert editor.get_attribute('contenteditable')=='true'
   editor.click();page.keyboard.type('implantasao comentarrio');page.wait_for_timeout(100)
   assert page.evaluate('handle.editor.getText()')=='implantasao comentarrio\n'
   page.evaluate("handle.editor.setSelection(0,11)");page.keyboard.insert_text('implanta\u00e7\u00e3o');page.wait_for_timeout(100)
   assert page.evaluate('handle.editor.getText()')=='implanta\u00e7\u00e3o comentarrio\n'
   editor.evaluate("e=>e.addEventListener('contextmenu',event=>window.menuPrevented=event.defaultPrevented)")
   editor.click(button='right');assert page.evaluate('window.menuPrevented') is False;page.keyboard.press('Escape')
   print('INLINE_NATIVE_EDIT_CORRECTION_CONTEXT_MENU_PASS',channel,flush=True)
   editor=create([{'insert':'ab\n'}]);page.evaluate('handle.editor.setSelection(2,0)');page.keyboard.press('Tab');assert page.evaluate('handle.editor.getText()')=='ab\u00a0\u00a0\n',repr(page.evaluate('handle.editor.getText()'))
   page.keyboard.press('Tab');page.keyboard.press('Shift+Tab');page.keyboard.press('Shift+Tab');assert page.evaluate('handle.editor.getText()')=='ab\n'
   delta=[{'insert':'Titulo','attributes':{'bold':True,'font':'Noto Serif','size':'18','color':'#1177bb'}},{'insert':'\n','attributes':{'align':'center'}},{'insert':{'image':png},'attributes':{'style':'width:80px;height:14px;'}},{'insert':'\nFim\n'}]
   editor=create(delta);page.evaluate('handle.editor.setSelection(handle.editor.getLength()-1,0)');page.keyboard.type('!');page.wait_for_timeout(100)
   model=page.evaluate('window.model');assert any(isinstance(o['insert'],dict) and o['insert'].get('image')==png for o in model),model
   assert any(o.get('attributes',{}).get('bold') and o.get('attributes',{}).get('font')=='Noto Serif' and o.get('attributes',{}).get('size')=='18' for o in model),model
   assert '80px' in next(o for o in model if isinstance(o['insert'],dict))['attributes']['style'],model
   page.evaluate("""()=>{const delta=window.model.map(op=>({...op,attributes:op.attributes?{...op.attributes}:undefined}));delta[0].attributes.size='24';delta[0].attributes.font='Roboto Mono';window.model=delta;gerenciadorNativeComment.update(handle,JSON.stringify(delta),0,6,'{}',false);}""")
   assert page.evaluate('handle.editor.getFormat(0,1).size')=='24px'
   assert page.evaluate('handle.editor.getFormat(0,1).font')=='Roboto Mono'
   print('INLINE_TAB_IMAGE_STYLES_PASS',channel,flush=True)
   page.locator('#copy').fill('Texto do Windows\nSegunda linha');page.locator('#copy').select_text();page.keyboard.press('Control+c')
   page.evaluate('handle.editor.setSelection(handle.editor.getLength()-1,0)');page.keyboard.press('Control+v');page.wait_for_timeout(200)
   text=page.evaluate('handle.editor.getText()');assert text.endswith('Fim!Texto do Windows\nSegunda linha\n'),text
   assert '\r' not in text;assert sum(isinstance(o['insert'],dict) for o in page.evaluate('window.model'))==1
   page.evaluate('handle.editor.history.cutoff()');page.keyboard.type('X');page.keyboard.press('Control+z');assert page.evaluate('handle.editor.getText()')==text
   print('INLINE_REAL_CLIPBOARD_UNDO_PASS',channel,flush=True)
   assert not errors,errors
   page.evaluate("gerenciadorNativeComment.update(handle,JSON.stringify(window.model),0,0,'{}',true)")
   assert page.locator('.ql-editor').get_attribute('contenteditable')=='false'
   page.evaluate('gerenciadorNativeComment.destroy(handle)')
   assert page.locator('#editor').inner_html()==''
   browser.close()
finally:server.shutdown()
