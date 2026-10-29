"""Real Flutter Auth plugin with mocked account endpoints and persistent profiles."""
import base64,json,tempfile,time,threading
from pathlib import Path
from functools import partial
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),partial(Handler,directory=str(ROOT/'build/auth-storage-probe')))
threading.Thread(target=server.serve_forever,daemon=True).start()
origin=f'http://127.0.0.1:{server.server_port}'
def enc(d):return base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip('=')
now=int(time.time());token=enc({'alg':'none'})+'.'+enc({'sub':'diagnostic-only','user_id':'diagnostic-only','aud':'gerenciador-horas','iat':now,'exp':now+3600,'auth_time':now,'firebase':{'sign_in_provider':'password'}})+'.fixture'
refresh_calls=[]
def api(r):
 if 'securetoken.googleapis.com' in r.request.url:refresh_calls.append(True)
 if 'securetoken.googleapis.com' in r.request.url:data={'access_token':token,'id_token':token,'refresh_token':'fixture-only','expires_in':'3600','user_id':'diagnostic-only','token_type':'Bearer'}
 elif 'signInWithPassword' in r.request.url:data={'localId':'diagnostic-only','email':'fixture@example.invalid','idToken':token,'refreshToken':'fixture-only','expiresIn':'3600'}
 else:data={'users':[{'localId':'diagnostic-only','email':'fixture@example.invalid','emailVerified':False,'providerUserInfo':[{'providerId':'password','email':'fixture@example.invalid','rawId':'fixture@example.invalid'}]}]}
 r.fulfill(status=200,content_type='application/json',body=json.dumps(data),headers={'access-control-allow-origin':'*'})
try:
 with sync_playwright() as p:
  for channel in ['chrome','msedge']:
   for compatible,keep in [(True,True),(True,False),(False,True),(False,False)]:
    with tempfile.TemporaryDirectory(prefix='auth-flutter-',ignore_cleanup_errors=True) as profile:
     for stage in ['login','restart']:
      previous_refreshes=len(refresh_calls)
      context=p.chromium.launch_persistent_context(profile,channel=channel,headless=True)
      context.route('https://identitytoolkit.googleapis.com/**',api)
      context.route('https://securetoken.googleapis.com/**',api)
      if compatible:
       context.add_init_script("window.indexedCalls=[];Object.defineProperty(indexedDB,'open',{value(name){window.indexedCalls.push({name,stack:new Error().stack});throw new DOMException('fixture blocked','SecurityError')}})")
      if stage=='login' and compatible:
       context.add_init_script("if(location.origin==='"+origin+"')localStorage.setItem('gerenciador_horas.auth.storage','local')")
      page=context.pages[0];page.goto(origin+'/');page.wait_for_function('window.probeReady===true || !!window.probeError',timeout=90000)
      assert page.evaluate('window.probeError || null') is None,page.evaluate('window.probeError')
      if stage=='login':
       page.evaluate('(keep)=>window.probeLogin(keep)',keep)
       assert page.evaluate('window.probeUid')=='diagnostic-only'
       page.reload();page.wait_for_function('window.probeReady===true || !!window.probeError',timeout=90000)
       assert page.evaluate('window.probeUid')=='diagnostic-only', 'session must survive page reload'
      else:assert page.evaluate('window.probeUid')==('diagnostic-only' if keep else ''),(channel,compatible,keep,page.evaluate('window.probeUid'))
      if stage=='restart' and keep:assert len(refresh_calls)>previous_refreshes,'Expired session must renew after restart'
      if compatible:assert not any(call['name']=='firebaseLocalStorageDb' for call in page.evaluate('window.indexedCalls')),page.evaluate('window.indexedCalls')
      if stage=='login' and keep:
       # Require a refresh after restart, rather than testing only a fresh token.
       page.evaluate("""() => {
        const key=Object.keys(localStorage).find(k=>k.startsWith('firebase:authUser:'));
        if(!key)throw Error('Persistent login was not written to localStorage');
        const user=JSON.parse(localStorage.getItem(key));
        user.stsTokenManager.expirationTime=Date.now()-60000;
        localStorage.setItem(key,JSON.stringify(user));
       }""")
      context.close()
     print('FLUTTER_AUTH_RESTART_PASS',channel,'compatible',compatible,'keep',keep,flush=True)
finally:server.shutdown()
