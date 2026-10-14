(() => {
  const pending = new Map();
  window.addEventListener('message', event => {
    if (event.source !== window || event.origin !== location.origin || event.data?.channel !== 'gerenciador-edesk-response') return;
    const entry = pending.get(event.data.id);
    if (!entry) return;
    pending.delete(event.data.id);
    clearTimeout(entry.timer);
    entry.resolve(JSON.stringify(event.data.result));
  });
  window.edeskExtensionCall = json => new Promise((resolve, reject) => {
    const id = crypto.randomUUID();
    const timer = setTimeout(() => {pending.delete(id); reject(new Error('Extensão não respondeu.'));}, 10000);
    pending.set(id, {resolve, timer});
    window.postMessage({channel: 'gerenciador-edesk-request', id, payload: JSON.parse(json)}, location.origin);
  });
})();
