(() => {
  let active = null, nextId = 0;
  const constructor = () => window.SpeechRecognition || window.webkitSpeechRecognition;
  window.projectVoiceSupported = () => window.isSecureContext && typeof constructor() === 'function';
  const errors = {
    'not-allowed': 'Permita o microfone nas configurações deste site e tente novamente.',
    'service-not-allowed': 'O serviço de voz foi bloqueado pelo navegador ou pela configuração da empresa.',
    'audio-capture': 'Não foi possível acessar o microfone. Confira a conexão e as permissões.',
    'network': 'O serviço de voz não respondeu. Verifique a conexão e tente novamente.',
    'language-not-supported': 'O reconhecimento em português não está disponível neste navegador. Tente no Chrome atualizado.',
    'no-speech': 'Nenhuma fala foi identificada. Clique no microfone e tente novamente.'
  };
  function emit(session, type, value = '') { session.callback(JSON.stringify({type, value})); }
  function release(session, abort = false) {
    if (active !== session) return;
    active = null;
    clearTimeout(session.stopTimer);
    document.removeEventListener('visibilitychange', session.visibility);
    session.recognition.onstart = session.recognition.onresult = session.recognition.onerror = session.recognition.onend = null;
    if (abort) { try { session.recognition.abort(); } catch (_) {} }
    emit(session, 'state', 'idle');
  }
  window.projectVoiceCancel = id => {
    if (active?.id === id) release(active, true);
  };
  window.projectVoiceStop = id => {
    if (active?.id !== id || active.stopping) return;
    const session = active;
    session.stopping = true;
    emit(session, 'state', 'stopping');
    try { session.recognition.stop(); }
    catch (_) { release(session, true); return; }
    session.stopTimer = setTimeout(() => release(session, true), 2500);
  };
  window.projectVoiceStart = callback => {
    if (active) release(active, true);
    const id = ++nextId;
    if (!window.projectVoiceSupported()) {
      callback(JSON.stringify({type:'error', value:'Ditado indisponível neste navegador. Continue digitando ou tente no Chrome atualizado.'}));
      return id;
    }
    let recognition;
    try { recognition = new (constructor())(); }
    catch (_) {
      callback(JSON.stringify({type:'error', value:'Não foi possível iniciar o reconhecimento de voz.'}));
      return id;
    }
    const session = {id, callback, recognition, finalIndexes:new Set(), stopping:false};
    active = session;
    recognition.lang = 'pt-BR';
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.maxAlternatives = 1;
    recognition.onstart = () => { if (active === session) emit(session, 'state', 'listening'); };
    recognition.onresult = event => {
      if (active !== session) return;
      const interim = [];
      for (let index = event.resultIndex; index < event.results.length; index++) {
        if (active !== session) return;
        const result = event.results[index], text = result[0]?.transcript?.trim() || '';
        if (result.isFinal && !session.finalIndexes.has(index)) {
          session.finalIndexes.add(index);
          if (text) emit(session, 'final', text);
        } else if (!result.isFinal && text) interim.push(text);
      }
      if (active === session) emit(session, 'interim', interim.join(' '));
    };
    recognition.onerror = event => {
      if (active !== session) return;
      if (event.error !== 'aborted') emit(session, 'error', errors[event.error] || 'Não foi possível reconhecer a fala. Tente novamente.');
      release(session, true);
    };
    recognition.onend = () => release(session);
    session.visibility = () => { if (document.hidden) release(session, true); };
    document.addEventListener('visibilitychange', session.visibility);
    emit(session, 'state', 'starting');
    try { recognition.start(); }
    catch (_) {
      emit(session, 'error', 'Não foi possível iniciar o microfone. Verifique as permissões e tente novamente.');
      release(session, true);
    }
    return id;
  };
  window.addEventListener('pagehide', () => { if (active) release(active, true); });
})();
