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
    # Fake synthesis only: never play audio. Check language, ownership and echo.
    page.evaluate('''
      window.speechEvents=[];window.utterances=[];window.cancelledSpeech=0;
      window.SpeechSynthesisUtterance=class {constructor(text){this.text=text;utterances.push(this);}};
      Object.defineProperty(window,'speechSynthesis',{configurable:true,value:{
        speak:()=>{},cancel:()=>cancelledSpeech++,
        getVoices:()=>[{lang:'en-US'},{lang:'pt-BR',name:'Portuguese fixture'}]
      }});
      window.spokenId=projectSpeechSpeak('Estou ouvindo.',value=>speechEvents.push(value));
      window.echoRec=instances.at(-1);
      window.echoSession=projectVoiceStart(receive);window.echoRec=instances.at(-1);
    ''')
    assert page.evaluate('utterances.at(-1).lang') == 'pt-BR'
    assert page.evaluate('utterances.at(-1).voice.lang') == 'pt-BR'
    before = page.evaluate('events.filter(e=>e.type==="final").length')
    page.evaluate('result(echoRec,0,"Théo enviar horas do dia");utterances.at(-1).onend()')
    assert page.evaluate('speechEvents') == [True]
    assert page.evaluate('events.filter(e=>e.type==="final").length') == before
    page.evaluate('window.projectSpeechQuietUntil=0;result(echoRec,0,"Théo enviar horas do dia");result(echoRec,1,"Théo enviar horas do dia")')
    assert page.evaluate('events.filter(e=>e.type==="final").length') == before + 1
    page.evaluate('''
      window.oldSpeech=projectSpeechSpeak('Primeira resposta',value=>speechEvents.push(value));
      window.lateSpeech=utterances.at(-1).onend;
      window.currentSpeech=projectSpeechSpeak('Segunda resposta',value=>speechEvents.push(value));
      projectSpeechCancel(oldSpeech);lateSpeech();
    ''')
    assert page.evaluate('window.projectSpeechBusy')
    page.evaluate('projectSpeechCancel(currentSpeech)')
    assert not page.evaluate('window.projectSpeechBusy')
    assert page.evaluate('speechEvents') == [True, False, False]
    page.evaluate('projectSpeechSpeak("Resposta interrompida",value=>speechEvents.push(value));projectVoiceStart(receive);Object.defineProperty(document,"hidden",{configurable:true,get:()=>true});document.dispatchEvent(new Event("visibilitychange"))')
    assert page.evaluate('instances.at(-1).aborted')
    assert not page.evaluate('window.projectSpeechBusy')
    page.evaluate('delete window.SpeechSynthesisUtterance')
    assert not page.evaluate('projectSpeechSupported()')
    page.evaluate('projectSpeechSpeak("Sem áudio",value=>speechEvents.push(value))')
    assert page.evaluate('speechEvents.at(-1)') is False
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
    page.wait_for_function('window.voiceAdapterPassed === true', timeout=5000)
    assert not errors, errors
    browser.close()
print('VOICE_BROWSER_OK: recognition and synthesis pt-BR, echo suppression, ownership, cancellation, hidden tab, unsupported fallback, compiled Dart adapters; no real audio')
