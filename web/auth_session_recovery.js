/* Only Firebase Auth records for this app are removed. Never clear a store. */
(() => {
  'use strict';
  const apiKey = 'AIzaSyCfpnLQ4-npn_S1d9g62Eg32eYfj9wu7M8';
  const keys = ['authUser', 'authEvent', 'redirectUser', 'persistence']
    .map(name => `firebase:${name}:${apiKey}:[DEFAULT]`);
  const deadline = (promise, ms = 8000) => new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timeout')), ms);
    promise.then(value => { clearTimeout(timer); resolve(value); },
      error => { clearTimeout(timer); reject(error); });
  });
  async function resetIndexedAuth() {
    let cancelled = false;
    const operation = new Promise((resolve, reject) => {
      const request = indexedDB.open('firebaseLocalStorageDb');
      // An absent database has no session to remove. Do not create it.
      request.onupgradeneeded = () => request.transaction.abort();
      request.onerror = () => request.error?.name === 'AbortError'
        ? resolve() : reject(request.error);
      request.onsuccess = () => {
        const db = request.result;
        if (cancelled || !db.objectStoreNames.contains('firebaseLocalStorage')) {
          db.close(); resolve(); return;
        }
        const tx = db.transaction('firebaseLocalStorage', 'readwrite');
        const store = tx.objectStore('firebaseLocalStorage');
        keys.forEach(key => store.delete(key));
        tx.oncomplete = () => { db.close(); resolve(); };
        tx.onerror = tx.onabort = () => { db.close(); reject(tx.error); };
      };
    });
    try { await deadline(operation); } catch (error) { cancelled = true; throw error; }
  }
  async function recover() {
    const errors = [];
    for (const name of ['localStorage', 'sessionStorage']) {
      try { keys.forEach(key => window[name].removeItem(key)); }
      catch (_) { errors.push(name); }
    }
    try { await resetIndexedAuth(); } catch (_) { errors.push('IndexedDB'); }
    if (errors.length) throw new Error(errors.join(', '));
  }
  window.gerenciadorAuthRecovery = { recover };
  const button = document.getElementById('recover');
  const status = document.getElementById('status');
  button?.addEventListener('click', async () => {
    button.disabled = true;
    status.textContent = 'Recuperando a sess\u00e3o local...';
    try {
      await recover();
      status.textContent = 'Sess\u00e3o redefinida. Volte ao sistema e entre novamente com Manter conectado marcado.';
      document.getElementById('return').hidden = false;
    } catch (error) {
      status.textContent = 'N\u00e3o foi poss\u00edvel acessar o armazenamento: ' + error.message + '. Feche as outras abas do sistema e tente novamente. Se continuar, verifique extens\u00f5es e bloqueios do navegador.';
      button.disabled = false;
    }
  });
})();
