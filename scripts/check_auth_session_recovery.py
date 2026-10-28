"""Verify selective Auth cleanup with real browser storage; no real accounts."""
import json
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT = Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *args): pass
server = ThreadingHTTPServer(('127.0.0.1', 0), partial(Handler, directory=str(ROOT / 'web')))
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with sync_playwright() as p:
        for channel in ['chrome', 'msedge']:
            browser = p.chromium.launch(channel=channel, headless=True)
            page = browser.new_page()
            page.goto(f'http://127.0.0.1:{server.server_port}/recuperar-acesso.html')
            page.evaluate("""async () => {
                const key = 'firebase:authUser:AIzaSyCfpnLQ4-npn_S1d9g62Eg32eYfj9wu7M8:[DEFAULT]';
                window.targetKey = key;
                for (const storage of [localStorage, sessionStorage]) {
                    storage.setItem(key, 'malformed-session');
                    storage.setItem('project-links', 'preserve-links');
                    storage.setItem('comment-draft', 'preserve-draft');
                    storage.setItem('firebase:authUser:other-key:[DEFAULT]', 'other-app');
                }
                await new Promise((resolve,reject) => {
                    const req = indexedDB.open('firebaseLocalStorageDb',1);
                    req.onupgradeneeded = () => req.result.createObjectStore('firebaseLocalStorage',{keyPath:'fbase_key'});
                    req.onerror = () => reject(req.error);
                    req.onsuccess = () => {
                        const db = req.result;
                        const tx = db.transaction('firebaseLocalStorage','readwrite');
                        const store = tx.objectStore('firebaseLocalStorage');
                        store.put({fbase_key:key,value:{corrupted:true}});
                        store.put({fbase_key:'project-links',value:{folder:'preserve-me'}});
                        store.put({fbase_key:'firebase:authUser:other-key:[DEFAULT]',value:'other-app'});
                        tx.oncomplete = () => {db.close();resolve()};
                    };
                });
            }""")
            page.get_by_role('button',name='Recuperar meu acesso').click()
            page.locator('#return').wait_for(state='visible')
            assert page.evaluate("[localStorage,sessionStorage].every(s=>s.getItem(targetKey)===null && s.getItem('project-links')==='preserve-links' && s.getItem('comment-draft')==='preserve-draft' && s.getItem('firebase:authUser:other-key:[DEFAULT]')==='other-app')")
            result = page.evaluate("""async()=>await new Promise(resolve=>{
                const req=indexedDB.open('firebaseLocalStorageDb');
                req.onsuccess=()=>{const db=req.result;const tx=db.transaction('firebaseLocalStorage');const all=tx.objectStore('firebaseLocalStorage').getAll();all.onsuccess=()=>{resolve(all.result);db.close()}};
            })""")
            assert len(result)==2 and all(row['fbase_key'] != page.evaluate('targetKey') for row in result),result
            page.reload()
            assert page.locator('#return').is_hidden()  # never clean without a click
            # Idempotent cleanup, including an absent Auth database.
            page.evaluate("() => gerenciadorAuthRecovery.recover()")
            print('AUTH_RECOVERY_PRESERVES_LINKS_DRAFTS_OTHER_ACCOUNTS_PASS',channel,flush=True)
            # A fresh profile must not retain an empty Auth database.
            fresh = browser.new_context()
            clean = fresh.new_page()
            clean.goto(f'http://127.0.0.1:{server.server_port}/recuperar-acesso.html')
            clean.get_by_role('button', name='Recuperar meu acesso').click()
            clean.locator('#return').wait_for(state='visible')
            assert clean.evaluate("async () => !(await indexedDB.databases()).some(db => db.name === 'firebaseLocalStorageDb')")
            clean.reload()
            clean.evaluate("Object.defineProperty(window,'localStorage',{get(){throw new Error('blocked')}})")
            clean.get_by_role('button', name='Recuperar meu acesso').click()
            clean.wait_for_function("document.querySelector('#status').textContent.includes('localStorage')")
            assert clean.locator('#return').is_hidden()
            assert clean.get_by_role('button', name='Recuperar meu acesso').is_enabled()
            fresh.close()
            print('AUTH_RECOVERY_ABSENT_DATABASE_BLOCKED_STORAGE_PASS', channel, flush=True)
            browser.close()
finally:
    server.shutdown()
