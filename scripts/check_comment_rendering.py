"""Compare native editor with delivered HTML in an isolated 11px destination iframe."""
import json,threading,subprocess,shutil
from pathlib import Path
from functools import partial
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
subprocess.run([shutil.which('dart') or r'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe',str(ROOT/'test/support/comment_render_fixture.dart')],cwd=ROOT,check=True)
fixtures=json.loads((ROOT/'build/comment-render-fixtures.json').read_text())
class Handler(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  if self.path=='/probe':
   body=b'<html><head><base href="/"></head><body style="margin:0"><div id="editor" style="height:450px;width:600px;color:#111827"></div><iframe id="target" style="width:650px;height:450px;border:0"></iframe><script src="comment_native_editor.js"></script></body></html>'
   self.send_response(200);self.send_header('Content-Type','text/html');self.end_headers();self.wfile.write(body)
  else:super().do_GET()
server=ThreadingHTTPServer(('127.0.0.1',0),partial(Handler,directory=str(ROOT/'build/web')))
threading.Thread(target=server.serve_forever,daemon=True).start()
MEASURE=r"""({host,text})=>{
 const root=document.querySelector(host),walk=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
 let n;while(n=walk.nextNode()){if(!n.textContent.includes(text))continue;
 const from=n.textContent.indexOf(text),range=document.createRange();range.setStart(n,from);range.setEnd(n,from+text.length);
 const rect=range.getBoundingClientRect(),parent=n.parentElement,style=getComputedStyle(parent),block=parent.closest('p,li,h1,h2,h3,blockquote');
 return {text:n.textContent,left:rect.left-root.getBoundingClientRect().left,width:rect.width,fontSize:style.fontSize,font:style.fontFamily,weight:style.fontWeight,italic:style.fontStyle,align:block?getComputedStyle(block).textAlign:null};}
 throw Error('Missing expected text: '+text);
}"""
try:
 with sync_playwright() as p:
  for channel in ['chrome','msedge']:
   browser=p.chromium.launch(channel=channel,headless=True)
   page=browser.new_page()
   for name,fixture in fixtures.items():
    page.goto(f'http://127.0.0.1:{server.server_port}/probe')
    page.evaluate("""async delta=>{window.handle=await gerenciadorNativeComment.create(document.querySelector('#editor'),JSON.stringify(delta),()=>{},()=>{});await document.fonts.ready;}""",fixture['delta'])
    page.locator('#target').evaluate("""(e,html)=>e.srcdoc='<html><style>body{margin:0;font:11px Arial}p,li,span{font-size:11px}</style><body><div id="delivered" style="box-sizing:border-box;width:600px;padding:12px 15px">'+html+'</div></body></html>'""",fixture['html'])
    target=page.frame_locator('#target');target.locator('#delivered').wait_for()
    frame=page.locator('#target').element_handle().content_frame()
    words={'default':['Agenda 09/11/2026:'],'times':['Agenda 09/11/2026:','Sanar duvidas e verificar testes'],'structure':['Centralizado','Recuado','Primeiro','Filho','Segundo']}[name]
    for word in words:
     before=page.evaluate(MEASURE,{'host':'#editor','text':word})
     after=frame.evaluate(MEASURE,{'host':'#delivered','text':word})
     for key in ['fontSize','weight','italic','align']:assert before[key]==after[key],(channel,name,word,key,before,after)
     if name!='default':
      assert abs(before['left']-after['left'])<1.5,(channel,name,word,'indent',before,after)
      assert abs(before['width']-after['width'])<1.5,(channel,name,word,'glyph width',before,after)
    page.evaluate('handle.destroy()')
   browser.close()
   print('COMMENT_RENDERING_MATCHES',channel,'size, Times, emphasis, alignment, indentation and lists; no live E-Desk')
finally:server.shutdown()
