"""Read-only storage diagnosis using synthetic sessions, never real accounts."""
import json,threading
from pathlib import Path
from functools import partial
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),partial(Handler,directory=str(ROOT/'web')))
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  for channel in ['chrome','msedge']:
   browser=p.chromium.launch(channel=channel,headless=True)
   context=browser.new_context();page=context.new_page();page.goto(f'http://127.0.0.1:{server.server_port}/diagnostico-login.html')
   empty=page.evaluate('window.gerenciadorAuthDiagnostic.inspect()');assert not empty['local']['present'] and not empty['indexed']['present']
   assert page.evaluate("indexedDB.databases().then(dbs=>dbs.every(db=>db.name!=='firebaseLocalStorageDb'))")
   page.evaluate("""async()=>{
    window.fixtureKey='firebase:authUser:AIzaSyCfpnLQ4-npn_S1d9g62Eg32eYfj9wu7M8:[DEFAULT]';
    window.fixtureUser={uid:'private-user-fixture',email:'private-fixture@example.invalid',stsTokenManager:{refreshToken:'PRIVATE_REFRESH_SENTINEL',accessToken:'PRIVATE_ACCESS_SENTINEL',expirationTime:Date.now()+100000}};
    localStorage.setItem(fixtureKey,JSON.stringify(fixtureUser));localStorage.setItem('project-links','unchanged');
    await new Promise((resolve,reject)=>{let r=indexedDB.open('firebaseLocalStorageDb',1);r.onupgradeneeded=()=>r.result.createObjectStore('firebaseLocalStorage',{keyPath:'fbase_key'});r.onerror=()=>reject(r.error);r.onsuccess=()=>{const db=r.result,tx=db.transaction('firebaseLocalStorage','readwrite');tx.objectStore('firebaseLocalStorage').put({fbase_key:fixtureKey,value:fixtureUser});tx.oncomplete=()=>{db.close();resolve()}}});
   }""")
   before=page.evaluate('JSON.stringify({...localStorage})')
   report=page.evaluate('window.gerenciadorAuthDiagnostic.inspect()')
   assert report['local']['valid'] and report['indexed']['valid'] and not report['session']['present'],report
   assert page.evaluate('JSON.stringify({...localStorage})')==before
   text=json.dumps(report)
   assert not any(secret in text for secret in ['private-user-fixture','private-fixture@example.invalid','PRIVATE_REFRESH_SENTINEL','PRIVATE_ACCESS_SENTINEL'])
   page.locator('#check').click();page.wait_for_function("document.querySelector('#result').textContent.includes('auth-storage-read-only-1')")
   assert not any(secret in page.locator('body').inner_text() for secret in ['private-user-fixture','PRIVATE_REFRESH_SENTINEL','PRIVATE_ACCESS_SENTINEL'])
   page.evaluate('localStorage.removeItem(fixtureKey);sessionStorage.setItem(fixtureKey,JSON.stringify(fixtureUser))')
   report=page.evaluate('window.gerenciadorAuthDiagnostic.inspect()');assert report['session']['valid'] and not report['local']['present'] and report['indexed']['valid']
   page.evaluate("Object.defineProperty(indexedDB,'open',{value(){throw new DOMException('blocked','SecurityError')}})")
   report=page.evaluate('window.gerenciadorAuthDiagnostic.inspect()');assert not report['indexed']['readable']
   browser.close();print('AUTH_DIAGNOSTIC_READ_ONLY_AND_REDACTED_OK',channel,flush=True)
finally:server.shutdown()
