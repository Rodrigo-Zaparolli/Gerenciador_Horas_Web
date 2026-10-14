(() => {
  function database() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open('gerenciador-local-files', 1);
      request.onupgradeneeded = () => request.result.createObjectStore('references');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(Error('Não foi possível guardar o vínculo neste navegador.'));
    });
  }
  async function store(uid, kind, handle, file) {
    const id = crypto.randomUUID(), name = handle?.name ?? file.name;
    const db = await database();
    try {
      await new Promise((resolve, reject) => {
        const transaction = db.transaction('references', 'readwrite');
        transaction.objectStore('references').put({uid, kind, handle, file}, id);
        transaction.oncomplete = resolve;
        transaction.onerror = () => reject(Error('Não foi possível guardar o vínculo.'));
        transaction.onabort = transaction.onerror;
      });
    } finally {db.close();}
    return `browser-${kind}://local/${encodeURIComponent(uid)}/${id}/${encodeURIComponent(name)}`;
  }
  async function load(reference, uid) {
    const url = new URL(reference), parts = url.pathname.split('/').slice(1).map(decodeURIComponent);
    if (!['browser-folder:', 'browser-file:'].includes(url.protocol) || url.hostname !== 'local' || parts.length !== 3 || parts[0] !== uid || !/^[0-9a-f-]{36}$/.test(parts[1]) || url.search || url.hash) throw Error('Este vínculo pertence a outra conta. Selecione a pasta ou o arquivo novamente.');
    const db = await database();
    let entry;
    try {entry = await new Promise((resolve, reject) => {
      const request = db.transaction('references').objectStore('references').get(parts[1]);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(Error('Não foi possível ler o vínculo local.'));
    });} finally {db.close();}
    if (!entry || entry.uid !== uid || `browser-${entry.kind}:` !== url.protocol) throw Error('Esta pasta ou arquivo foi vinculado em outro navegador ou computador. Selecione novamente aqui, ou use um link compartilhado.');
    if (entry.handle && await entry.handle.queryPermission({mode:'read'}) !== 'granted' && await entry.handle.requestPermission({mode:'read'}) !== 'granted') throw Error('Permita o acesso à pasta ou ao arquivo para continuar.');
    return entry;
  }
  async function folder(entry, path) {
    let handle = entry.handle;
    if (entry.kind !== 'folder' || !handle) throw Error('Selecione uma pasta.');
    for (const segment of path ?? []) {
      if (typeof segment !== 'string' || !segment || segment === '.' || segment === '..' || /[\/\\]/.test(segment)) throw Error('Caminho inválido.');
      handle = await handle.getDirectoryHandle(segment);
    }
    return handle;
  }
  async function pickFallback() {
    return new Promise(resolve => {
      const input = document.createElement('input'); input.type = 'file';
      input.accept = '.xlsx,.xls,.xlsm,.csv,.doc,.docx,.pdf,.txt';
      input.addEventListener('change', () => {resolve(input.files?.[0] ?? null); input.remove();}, {once:true});
      input.addEventListener('cancel', () => {resolve(null); input.remove();}, {once:true});
      input.hidden = true; document.body.append(input); input.click();
    });
  }
  window.projectLocalFilesCall = async json => {
    try {
      const args = JSON.parse(json);
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(args.uid ?? '')) throw Error('Entre na sua conta para selecionar uma pasta ou arquivo.');
      if (args.action === 'pick-folder' || args.action === 'create-folder') {
        if (!window.showDirectoryPicker) throw Error('Para selecionar ou criar pastas locais, abra o app no Chrome ou Edge do computador. Também é possível informar um link compartilhado.');
        const base = await window.showDirectoryPicker({mode:args.action === 'create-folder' ? 'readwrite' : 'read'});
        let handle = base;
        if (args.action === 'create-folder') {
          const name = String(args.name ?? '').replace(/[<>:"/\\|?*]/g, '-').replace(/\s+/g, ' ').trim().replace(/[. ]+$/, '');
          if (!name || name === '.' || name === '..' || name.length > 200) throw Error('Informe um nome válido para a pasta.');
          handle = await base.getDirectoryHandle(name, {create:true});
        }
        return JSON.stringify({reference:await store(args.uid, 'folder', handle)});
      }
      if (args.action === 'pick-file') {
        let handle, file;
        if (window.showOpenFilePicker) {
          [handle] = await window.showOpenFilePicker({multiple:false, types:[{description:'Documentos do projeto', accept:{'application/octet-stream':['.xlsx','.xls','.xlsm','.csv','.doc','.docx','.pdf','.txt']}}]});
          file = await handle.getFile();
        } else {file = await pickFallback();}
        if (!file) return JSON.stringify({cancelled:true});
        if (file.size > 25 * 1024 * 1024) throw Error('Selecione um arquivo de até 25 MB.');
        return JSON.stringify({reference:await store(args.uid, 'file', handle, handle ? undefined : file)});
      }
      const entry = await load(args.reference, args.uid);
      if (args.action === 'list') {
        const handle = await folder(entry, args.path), items = [];
        for await (const [name, child] of handle.entries()) {
          items.push({name, kind:child.kind});
          if (items.length > 2000) throw Error('Esta pasta tem muitos itens. Selecione uma subpasta com até 2.000 itens.');
        }
        items.sort((a,b) => a.kind === b.kind ? a.name.localeCompare(b.name) : a.kind === 'directory' ? -1 : 1);
        return JSON.stringify({items});
      }
      let file;
      if (entry.kind === 'file') file = entry.file ?? await entry.handle.getFile();
      else {
        if (typeof args.name !== 'string' || !args.name || /[\/\\]/.test(args.name) || ['.','..'].includes(args.name)) throw Error('Nome de arquivo inválido.');
        const handle = await folder(entry, args.path);
        file = await (await handle.getFileHandle(args.name)).getFile();
      }
      if (file.size > 25 * 1024 * 1024) throw Error('O arquivo excede o limite de 25 MB.');
      if (args.action === 'download') {
        const url = URL.createObjectURL(file), anchor = document.createElement('a');
        anchor.href = url; anchor.download = file.name; document.body.append(anchor); anchor.click(); anchor.remove();
        setTimeout(() => URL.revokeObjectURL(url), 60000);
        return JSON.stringify({ok:true});
      }
      if (args.action === 'read') {
        const bytes = new Uint8Array(await file.arrayBuffer());
        let text = '';
        for (let index = 0; index < bytes.length; index += 32768) text += String.fromCharCode(...bytes.subarray(index,index+32768));
        return JSON.stringify({base64:btoa(text)});
      }
      throw Error('Operação de arquivo não reconhecida.');
    } catch (error) {
      if (error.name === 'AbortError') return JSON.stringify({cancelled:true});
      const message = ['NotFoundError','NotReadableError'].includes(error.name) ? 'O arquivo ou pasta foi movido ou removido. Selecione novamente.' : error.message;
      return JSON.stringify({error:message});
    }
  };
})();
