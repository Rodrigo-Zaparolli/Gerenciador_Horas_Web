"""Optional local speech runtime. Imported only after pilot authorization."""
import base64
import binascii
import io
import json
import sys
import threading
from collections import OrderedDict
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent/'.edesk-local'/'beta-voice'
OWNER_EMAIL='rodrigozaparolli79@gmail.com'
_lock=threading.Lock()
_tts=None
_stt=None
_cache=OrderedDict()

def allowed(user):
    return bool(user.get('sub')) and str(user.get('email','')).strip().lower()==OWNER_EMAIL

def ready():
    return all((ROOT/path).exists() for path in [
        'vendor/kokoro_onnx','vendor/vosk','kokoro-v1.0.onnx',
        'voices-v1.0.bin','vosk-model-small-pt-0.3/final.mdl'])

def _dependencies():
    if not ready():
        raise RuntimeError('Execute scripts/setup_beta_voice.ps1 neste computador para preparar a voz da BETA.')
    path=str(ROOT/'vendor')
    if path not in sys.path: sys.path.insert(0,path)

def execute(body):
    global _tts,_stt
    if not isinstance(body,dict):raise ValueError('Pedido inválido.')
    action=body.get('action')
    if action=='status':return {'ready':ready(),'voice':'Dora','local':True}
    if action not in ('speech','recognize'):raise ValueError('Comando de áudio inválido.')
    with _lock:
        _dependencies()
        if action=='recognize':
            import vosk
            rate=body.get('sampleRate')
            if isinstance(rate,bool) or not isinstance(rate,int) or not 8000<=rate<=96000:raise ValueError('Taxa de áudio inválida.')
            try: pcm=base64.b64decode(body.get('pcm',''),validate=True)
            except (ValueError,TypeError,binascii.Error):raise ValueError('Áudio inválido.') from None
            if not 0<len(pcm)<=2000000 or len(pcm)%2:raise ValueError('Áudio inválido.')
            if _stt is None:
                vosk.SetLogLevel(-1);_stt=vosk.Model(str(ROOT/'vosk-model-small-pt-0.3'))
            mode=body.get('mode')
            phrases=['beta','olá beta','oi beta','abrir beta','[unk]']
            if mode!='asleep':phrases += [
                'enviar horas do dia','enviar as horas do dia','enviar horas de hoje','enviar minhas horas de hoje',
                'fechar beta','cancelar','cancelar envio','pode conferir','sim','não','quero',
                'pode ler','leia','ler as horas','leia as horas','por voz','leitura por voz',
                'conferência visual','conferir na tela','vou conferir na tela','na tela','visual','pode enviar','confirmar envio']
            rec=vosk.KaldiRecognizer(_stt,rate,json.dumps(phrases,ensure_ascii=False))
            rec.AcceptWaveform(pcm)
            text=json.loads(rec.FinalResult()).get('text','').replace('[unk]','').strip()
            return {'text':text}
        text=body.get('text');speed=body.get('speed',.98)
        if not isinstance(text,str) or not text.strip() or len(text)>1500:raise ValueError('Texto inválido.')
        if isinstance(speed,bool) or not isinstance(speed,(int,float)) or not .85<=speed<=1.15:raise ValueError('Velocidade inválida.')
        key=(text,speed)
        if key not in _cache:
            from kokoro_onnx import Kokoro
            import numpy as np
            import soundfile as sf
            if _tts is None:_tts=Kokoro(str(ROOT/'kokoro-v1.0.onnx'),str(ROOT/'voices-v1.0.bin'))
            # This export declares float speed; the wrapper assumes int32.
            session=_tts.sess
            class TypedSession:
                def get_inputs(self):return session.get_inputs()
                def run(self,outputs,inputs):
                    inputs=dict(inputs)
                    if any(i.name=='speed' and i.type=='tensor(float)' for i in session.get_inputs()):
                        inputs['speed']=np.array([speed],dtype=np.float32)
                    return session.run(outputs,inputs)
            _tts.sess=TypedSession()
            try:samples,rate=_tts.create(text,voice='pf_dora',speed=speed,lang='pt-br')
            finally:_tts.sess=session
            buffer=io.BytesIO();sf.write(buffer,samples,rate,format='WAV',subtype='PCM_16')
            _cache[key]=buffer.getvalue()
            while len(_cache)>32 or sum(map(len,_cache.values()))>16*1024*1024:_cache.popitem(last=False)
        else:_cache.move_to_end(key)
        return {'audio':base64.b64encode(_cache[key]).decode('ascii')}
