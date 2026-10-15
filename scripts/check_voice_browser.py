"""Offline speech API regression. Uses fake recognition, never a real microphone."""
import os
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
os.environ['PLAYWRIGHT_BROWSERS_PATH'] = str(ROOT / 'python/ms-playwright')
source = (ROOT / 'web/voice_recognition.js').read_text(encoding='utf-8')
fake = """
window.instances=[];
window.webkitSpeechRecognition=class {
 constructor(){instances.push(this);this.aborted=false;this.stopped=false;}
 start(){this.onstart?.();}
 stop(){this.stopped=true;}
 abort(){this.aborted=true;}
};
window.SpeechRecognition=window.webkitSpeechRecognition;
window.events=[];
window.receive = value => events.push(JSON.parse(value));
window.result = (r,index,text,final=true) => {
 const results=Array.from({length:index+1},()=>Object.assign([{transcript:''}],{isFinal:true}));
 results[index]=Object.assign([{transcript:text}],{isFinal:final});
 r.onresult?.({resultIndex:index,results});
};
"""
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()
    page.route('**/*', lambda route: route.fulfill(body='<html><body>Voice fixture</body></html>', content_type='text/html')
               if route.request.url == 'https://voice.fixture.invalid/' else route.abort())
    page.goto('https://voice.fixture.invalid/')
    page.add_script_tag(content=fake)
    page.add_script_tag(content=source)
    assert page.evaluate('projectVoiceSupported()')
    page.evaluate('window.first=projectVoiceStart(receive);window.rec=instances.at(-1);result(rec,0,"parcial",false)')
    assert not page.evaluate('events.some(e=>e.type==="final")')
    page.evaluate('result(rec,0,"Olá");result(rec,0,"Olá");result(rec,1,"Olá")')
    assert page.evaluate('events.filter(e=>e.type==="final").map(e=>e.value)') == ['Olá', 'Olá']
    assert page.evaluate('rec.lang') == 'pt-BR'
    page.evaluate('window.late=rec.onresult;window.second=projectVoiceStart(receive);')
    assert page.evaluate('rec.aborted')
    before = page.evaluate('events.length')
    page.evaluate('late({resultIndex:0,results:[Object.assign([{transcript:"old session"}],{isFinal:true})]})')
    assert page.evaluate('events.length') == before
    page.evaluate('projectVoiceStop(second)')
    assert page.evaluate('instances.at(-1).stopped')
    page.evaluate('instances.at(-1).onend()')
    assert page.evaluate('events.at(-1)') == {'type': 'state', 'value': 'idle'}
    page.evaluate('projectVoiceStart(receive);instances.at(-1).onerror({error:"not-allowed"})')
    assert page.evaluate('events.some(e=>e.type==="error" && e.value.includes("Permita o microfone"))')
    page.evaluate('projectVoiceStart(receive);Object.defineProperty(document,"hidden",{configurable:true,get:()=>true});document.dispatchEvent(new Event("visibilitychange"))')
    assert page.evaluate('instances.at(-1).aborted')
    page.evaluate('delete window.webkitSpeechRecognition;delete window.SpeechRecognition')
    assert not page.evaluate('projectVoiceSupported()')
    page.evaluate('projectVoiceStart(receive)')
    assert page.evaluate('events.at(-1).type') == 'error'
    adapter = ROOT / 'build/voice_adapter_fixture.js'
    if not adapter.is_file():
        raise AssertionError('Compile scripts/voice_adapter_fixture.dart before running this check.')
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.add_script_tag(path=str(adapter))
    assert page.evaluate('window.voiceAdapterPassed === true'), errors
    assert not errors, errors
    browser.close()
print('VOICE_BROWSER_OK: pt-BR, interim, final deduplication, session isolation, stop, permission, hidden tab, unsupported browser, compiled Dart adapter; no real audio')
