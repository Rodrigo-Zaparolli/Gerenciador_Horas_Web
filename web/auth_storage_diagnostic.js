(() => {
  'use strict';
  const key = 'firebase:authUser:AIzaSyCfpnLQ4-npn_S1d9g62Eg32eYfj9wu7M8:[DEFAULT]';
  function describe(raw) {
    if (raw == null) return {present:false};
    try {
      const user = typeof raw === 'string' ? JSON.parse(raw) : raw;
      return {present:true, valid:typeof user?.uid==='string' && !!user.uid,
        refreshCredentialPresent:typeof user?.stsTokenManager?.refreshToken==='string' && !!user.stsTokenManager.refreshToken,
        refreshNeeded:typeof user?.stsTokenManager?.expirationTime==='number' ? user.stsTokenManager.expirationTime<=Date.now() : null};
    } catch (_) { return {present:true, valid:false}; }
  }
  function storage(name) {
    try {return {readable:true,...describe(window[name].getItem(key))};}
    catch (_) {return {readable:false};}
  }
  function indexed() {
    return new Promise(resolve => {
      let finished=false,db;
      const finish=value=>{if(finished)return;finished=true;clearTimeout(timer);db?.close();resolve(value);};
      const timer=setTimeout(()=>finish({readable:false,timeout:true}),2500);
      try {
        const request=indexedDB.open('firebaseLocalStorageDb');
        request.onupgradeneeded=()=>request.transaction.abort();
        request.onerror=()=>finish(request.error?.name==='AbortError' ? {readable:true,present:false} : {readable:false});
        request.onsuccess=()=>{
          db=request.result;
          if(finished){db.close();return;}
          if(!db.objectStoreNames.contains('firebaseLocalStorage')){finish({readable:true,present:false});return;}
          const tx=db.transaction('firebaseLocalStorage','readonly');
          const read=tx.objectStore('firebaseLocalStorage').get(key);
          let result;
          read.onsuccess=()=>{result={readable:true,...describe(read.result?.value)};};
          tx.oncomplete=()=>finish(result||{readable:true,present:false});
          tx.onerror=tx.onabort=()=>finish({readable:false});
        };
      } catch (_) {finish({readable:false});}
    });
  }
  async function inspect() {
    let mode='default';try{mode=localStorage.getItem('gerenciador_horas.auth.storage')==='local'?'local':'default';}catch(_){}
    return {diagnostic:'auth-storage-read-only-1',time:new Date().toISOString(),origin:location.origin,
      configuredStorage:mode,local:storage('localStorage'),session:storage('sessionStorage'),indexed:await indexed()};
  }
  window.gerenciadorAuthDiagnostic={inspect};
  const button=document.getElementById('check'),copy=document.getElementById('copy'),result=document.getElementById('result'),status=document.getElementById('status');
  button?.addEventListener('click',async()=>{
    button.disabled=true;
    try {
      const report=await inspect();result.textContent=JSON.stringify(report,null,2);copy.hidden=false;
      const durable=[report.local,report.indexed].some(store=>store.valid&&store.refreshCredentialPresent);
      status.textContent=durable?'Existe uma sess\u00e3o permanente salva neste navegador.':(!report.local.readable||!report.indexed.readable)?'N\u00e3o foi poss\u00edvel conferir todo o armazenamento. Copie o diagn\u00f3stico para an\u00e1lise.':report.session.valid?'O login encontrado dura somente enquanto o navegador est\u00e1 aberto.':'N\u00e3o foi encontrada uma sess\u00e3o permanente salva neste navegador.';
    } finally {button.disabled=false;}
  });
  copy?.addEventListener('click',async()=>{try{await navigator.clipboard.writeText(result.textContent);copy.textContent='Diagn\u00f3stico copiado';}catch(_){copy.textContent='Selecione e copie o texto abaixo';}});
})();
