(() => {
  window.nativeLocalFilesBridgeVersion = 'workbook-tools-10';
  const permissionMessage = 'O navegador bloqueou o acesso a este computador. Clique no ícone ao lado do endereço do site, abra as permissões e permita o acesso à rede local ou a este dispositivo. Depois clique novamente na pasta ou planilha.';
  async function permissionState() {
    for (const name of ['loopback-network', 'local-network-access']) {
      try { return (await navigator.permissions.query({name})).state; }
      catch (_) { /* Older browsers may not expose this permission. */ }
    }
    return 'unknown';
  }
  const performRequest = async raw => {
    const args = JSON.parse(raw), health = args.action === 'health';
    if (!['health', 'authorize', 'pick-file', 'pick-folder', 'create-folder', 'open', 'read', 'preview', 'excel-editor-read', 'excel-editor-write', 'excel-editor-preview','excel-editor-sheets', 'project-move-prepare', 'project-move-commit'].includes(args.action))
      return JSON.stringify({error:'invalid', message:'Ação local inválida.'});
    const permission = await permissionState();
    if (permission === 'denied') return JSON.stringify({error:'permission', message:permissionMessage});
    if (health && !args.interactive && permission === 'prompt')
      return JSON.stringify({status:0, data:{status:'permission-required'}});
    const controller = new AbortController();
    // A capability probe must finish while the browser still accepts the
    // user's click for the fallback folder/file picker. Interactive Windows
    // selection keeps its longer timeout.
    const timer = setTimeout(() => controller.abort(), health ? 1000 : 600000);
    try {
      const response = await fetch(`http://127.0.0.1:8765/${health ? 'healthz' : 'api/local-files'}`, {
        method:health ? 'GET' : 'POST', targetAddressSpace:'loopback',
        cache:'no-store', signal:controller.signal,
        ...(health ? {} : {headers:{'Authorization':`Bearer ${args.token}`, 'Content-Type':'application/json'},
          body:JSON.stringify({action:args.action, reference:args.reference, name:args.name, range:args.range,
            ...(typeof args.projectId === 'string' ? {projectId:args.projectId} : {}),
            ...(['project-move-prepare','project-move-commit'].includes(args.action) ? {destination:args.destination, sourceReference:args.sourceReference, excelReference:args.excelReference, operation:args.operation} : {}),
            ...(['excel-editor-read','excel-editor-write','excel-editor-preview'].includes(args.action) ? {worksheet:args.worksheet, firstRow:args.firstRow, firstColumn:args.firstColumn, revision:args.revision, changes:args.changes, serviceType:args.serviceType, sheetNames:args.sheetNames} : {})})})
      });
      if (response.status === 404) return JSON.stringify({error:'update', message:'Atualize a integração: encerre-a e execute Iniciar abertura local.cmd novamente.'});
      const data = await response.json();
      if (args.action === 'preview' && args.token !== 'invalid-diagnostic-token') {
        // Diagnostic flags only: never retain tokens, filenames, paths or images.
        try { localStorage.setItem('nativeExcelPreviewDiagnostic', JSON.stringify({
          ponte:window.nativeLocalFilesBridgeVersion, acaoEnviada:'preview',
          arquivoInformado:typeof args.reference === 'string' && args.reference.length>0,
          intervaloInformado:typeof args.range === 'string' && args.range.length>0,
          status:response.status, operacaoRecusada:data?.message==='Ação local inválida.',
          imagemRecebida:typeof data?.imagemBase64 === 'string' && data.imagemBase64.length>0
        })); } catch (_) { /* Storage may be unavailable; operation still works. */ }
      }
      return JSON.stringify({status:response.status, data});
    } catch (error) {
      if (await permissionState() === 'denied') return JSON.stringify({error:'permission', message:permissionMessage});
      return JSON.stringify({error:error.name === 'AbortError' ? 'timeout' : 'connection',
        message:error.name === 'AbortError'
          ? 'A abertura ficou aguardando. Verifique a permissão do navegador e a janela de seleção do Windows antes de tentar novamente.'
          : 'Não foi possível acessar a integração neste computador. Verifique se Iniciar abertura local.cmd está ativo e se o site tem permissão de acesso à rede local ou a este dispositivo.'});
    } finally {clearTimeout(timer);}
  };
  // Excel has one native operation lock. Share a queue across every modal in
  // this page so a closing editor cannot race the next editor's preview.
  let excelTail = Promise.resolve();
  window.nativeLocalFilesRequest = raw => {
    const args = JSON.parse(raw);
    if (!String(args.action).startsWith('excel-editor-')) return performRequest(raw);
    const job = excelTail.then(async () => {
      const started = Date.now();
      let attempts = 0;
      let result;
      for (;;) {
        result = await performRequest(raw);
        const reply = JSON.parse(result);
        // Only this exact pre-operation lock refusal is retryable. Never
        // repeat a write, a timeout, or an operation with an ambiguous result.
        const busy = reply.data?.message === 'Aguarde a leitura ou grava\u00e7\u00e3o da planilha em andamento.';
        const reading = ['excel-editor-read','excel-editor-preview','excel-editor-sheets'].includes(args.action);
        if (reading && busy && Date.now() - started >= 60000) {
          // Give callers a final error, not another retryable refusal. This
          // prevents a second retry layer from waiting another twelve times.
          reply.data = {...reply.data, message:'A integra\u00e7\u00e3o continua ocupada com outra opera\u00e7\u00e3o na planilha. Aguarde a conclus\u00e3o antes de atualizar novamente.'};
          result = JSON.stringify(reply);
          break;
        }
        if (!reading || !busy) break;
        attempts++;
        await new Promise(resolve => setTimeout(resolve, Math.min(500 * attempts, 2500)));
      }
      try {
        localStorage.setItem('nativeSpreadsheetDiagnostic', JSON.stringify({
          bridge: window.nativeLocalFilesBridgeVersion, action:args.action,
          status:JSON.parse(result).status ?? null, busyRetries:attempts,
          elapsedMs:Date.now()-started
        }));
      } catch (_) {}
      return result;
    });
    excelTail = job.catch(() => {});
    return job;
  };
})();
