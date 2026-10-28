"""Exercise the real browser bridge with simulated native HTTP replies."""
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
with sync_playwright() as p:
 for channel in ['chrome','msedge']:
  browser=p.chromium.launch(channel=channel,headless=True);page=browser.new_page()
  page.goto('about:blank')
  page.evaluate("""() => {
    Object.defineProperty(navigator,'permissions',{value:{query:async()=>({state:'granted'})}});
    window.sent=[];window.waiters=[];
    window.fetch=async(url,init)=>{const action=init.method==='GET'?'health':JSON.parse(init.body).action;sent.push(action);if(action==='health')return {status:200,json:async()=>({service:'fixture'})};return await new Promise(resolve=>waiters.push(resolve));};
    window.release=()=>waiters.shift()({status:200,json:async()=>({ok:true})});
  }""")
  page.add_script_tag(path=str(ROOT/'web/native_local_files_v2.js'))
  page.evaluate("()=>{window.first=nativeLocalFilesRequest(JSON.stringify({action:'excel-editor-read'}));window.second=nativeLocalFilesRequest(JSON.stringify({action:'excel-editor-preview'}));}")
  page.wait_for_function('sent.length===1')
  assert page.evaluate('sent')==['excel-editor-read']
  page.evaluate("nativeLocalFilesRequest(JSON.stringify({action:'health'}))")
  assert page.evaluate('sent')==['excel-editor-read','health']
  page.evaluate('release()');page.wait_for_function('sent.length===3')
  page.evaluate('release()');page.evaluate('Promise.all([first,second])')
  page.evaluate("""()=>{window.realTimeout=setTimeout;window.setTimeout=(fn,ms)=>realTimeout(fn,ms<=2500?0:ms);window.count=0;
    window.fetch=async()=>{count++;return {status:count<3?400:200,json:async()=>count<3?{message:'Aguarde a leitura ou grava\u00e7\u00e3o da planilha em andamento.'}:{ok:true}}};}""")
  result=page.evaluate("nativeLocalFilesRequest(JSON.stringify({action:'excel-editor-preview'})).then(JSON.parse)")
  assert result['status']==200 and page.evaluate('count')==3
  page.evaluate('window.count=0')
  result=page.evaluate("nativeLocalFilesRequest(JSON.stringify({action:'excel-editor-write'})).then(JSON.parse)")
  assert result['status']==400 and page.evaluate('count')==1,'writes must not retry'
  page.evaluate("()=>{window.originalNow=Date.now;window.ticks=0;Date.now=()=>ticks++===0?0:60001;window.fetch=async()=>({status:400,json:async()=>({message:'Aguarde a leitura ou grava\u00e7\u00e3o da planilha em andamento.'})})}")
  expired=page.evaluate("nativeLocalFilesRequest(JSON.stringify({action:'excel-editor-read'})).then(JSON.parse)")
  assert 'continua ocupada' in expired['data']['message']
  assert 'Aguarde a leitura' not in expired['data']['message']
  page.evaluate('()=>{Date.now=originalNow}')
  page.evaluate("()=>{window.count=0;window.fetch=async()=>{count++;throw new Error('fixture connection failure')}}")
  result=page.evaluate("nativeLocalFilesRequest(JSON.stringify({action:'excel-editor-preview'})).then(JSON.parse)")
  assert result['error']=='connection' and page.evaluate('count')==1
  page.evaluate("()=>{window.fetch=async()=>({status:200,json:async()=>({ok:true})})}")
  assert page.evaluate("nativeLocalFilesRequest(JSON.stringify({action:'excel-editor-read'})).then(JSON.parse)")['status']==200
  print('EXCEL_QUEUE_SERIAL_READ_RETRY_NO_WRITE_RETRY_PASS',channel,flush=True)
  browser.close()
