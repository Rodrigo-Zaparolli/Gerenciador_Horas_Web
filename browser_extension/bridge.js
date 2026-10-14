// Only the two explicitly listed application origins can reach this bridge.
const appOrigins = new Set(['https://gerenciador-horas.web.app', 'https://gerenciador-horas.firebaseapp.com']);
window.addEventListener('message', async event => {
  if (event.source !== window || event.origin !== location.origin || !appOrigins.has(event.origin)) return;
  const message = event.data;
  if (message?.channel !== 'gerenciador-edesk-request' || typeof message.id !== 'string') return;
  try {
    const result = await chrome.runtime.sendMessage({type: 'app', payload: message.payload});
    window.postMessage({channel: 'gerenciador-edesk-response', id: message.id, result}, location.origin);
  } catch (_) {
    window.postMessage({channel: 'gerenciador-edesk-response', id: message.id,
      result: {error: 'Recarregue o app após instalar ou atualizar a extensão.'}}, location.origin);
  }
});
