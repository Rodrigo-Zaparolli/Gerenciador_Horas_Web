(() => {
  window.nativeLocalFilesBridgeVersion = 'project-move-4';
  const permissionMessage = 'O navegador bloqueou o acesso a este computador. Clique no ícone ao lado do endereço do site, abra as permissões e permita o acesso à rede local ou a este dispositivo. Depois clique novamente na pasta ou planilha.';
  async function permissionState() {
    for (const name of ['loopback-network', 'local-network-access']) {
      try { return (await navigator.permissions.query({name})).state; }
      catch (_) { /* Older browsers may not expose this permission. */ }
    }
    return 'unknown';
  }
  window.nativeLocalFilesRequest = async raw => {
    const args = JSON.parse(raw), health = args.action === 'health';
    if (!['health', 'pick-file', 'pick-folder', 'create-folder', 'open', 'read', 'preview', 'excel-editor-read', 'excel-editor-write', 'project-move-prepare', 'project-move-commit'].includes(args.action))
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
            ...(['project-move-prepare','project-move-commit'].includes(args.action) ? {destination:args.destination, excelReference:args.excelReference, operation:args.operation} : {}),
            ...(['excel-editor-read','excel-editor-write'].includes(args.action) ? {revision:args.revision, changes:args.changes} : {})})})
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
})();
