import {cleanRequest, hourEntries, date} from './core.js';
const storageReady = Promise.all([
  chrome.storage.local.setAccessLevel({accessLevel: 'TRUSTED_CONTEXTS'}),
  chrome.storage.session.setAccessLevel({accessLevel: 'TRUSTED_CONTEXTS'})
]);
const appOrigins = new Set(['https://gerenciador-horas.web.app', 'https://gerenciador-horas.firebaseapp.com']);
const storageKey = uid => `history:${uid}`;
const ledger = async uid => (await chrome.storage.local.get(storageKey(uid)))[storageKey(uid)] ?? {};
async function recover() {
  const {job} = await chrome.storage.session.get('job');
  if (job && !job.result) {
    const tab = await chrome.tabs.get(job.runnerTab).catch(() => null);
    if (!tab) {
      job.result = {confirmed: false, statusCode: 409, message: 'A janela da extensão foi fechada. Confira o E-Desk antes de reenviar.', responseBody: ''};
      delete job.request;
      await chrome.storage.session.set({job});
    }
  }
  return job;
}
let exclusive = Promise.resolve();
function serialized(task) {
  const next = exclusive.then(task, task);
  exclusive = next.catch(() => {});
  return next;
}
async function handle(payload) {
  await storageReady;
  const path = payload?.path;
  const job = await recover();
  if (path === '/healthz') return {service: 'gerenciador-horas-edesk', status: 'ok', mode: 'extension', busy: !!job && !job.result};
  const uid = payload?.uid;
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) throw Error('Entre novamente na sua conta.');
  const body = payload.body;
  if (path === '/api/edesk/session') return {authorized: true};
  if (path === '/api/edesk/status') return job?.uid === uid ? {operationId: job.operationId, stage: job.stage, result: job.result} : {};
  const history = await ledger(uid);
  if (path === '/api/edesk/history') {
    if (body) {
      if (job && !job.result) throw Error('Aguarde o envio terminar.');
      for (const [key, state] of Object.entries(body.items ?? {})) {
        if (!/^[0-9a-f]{64}$/.test(key) || !['confirmed', 'uncertain', 'pending'].includes(state)) throw Error('Histórico inválido.');
      }
      for (const [key, state] of Object.entries(body.items ?? {})) {
        if (history[key] !== 'confirmed') history[key] = state === 'pending' ? 'uncertain' : state;
      }
      await chrome.storage.local.set({[storageKey(uid)]: history});
    }
    return {items: history};
  }
  if (path === '/api/edesk/review') return {items: (await hourEntries(body.request)).map(({key}) => ({key, state: history[key] ?? 'new'}))};
  const action = path?.replace('/api/edesk/', '');
  if (!['horas', 'comentarios', 'fases'].includes(action)) throw Error('Operação não reconhecida.');
  if (job && !job.result) throw Error('Há outro envio em andamento.');
  const request = cleanRequest(body?.request);
  if (JSON.stringify(request).length > 8 * 1024 * 1024) throw Error('Comentário muito grande para a extensão (máximo 8 MB).');
  if (action === 'horas') {
    const entries = await hourEntries(request);
    if (!body.retryUncertain && entries.some(({key}) => ['pending', 'uncertain'].includes(history[key]))) throw Error('Confira as horas incertas no E-Desk antes de reenviar.');
  } else if (action === 'fases') {
    if (!/^\d+$/.test(String(request.id)) || !Array.isArray(request.fases) || !request.fases.length) throw Error('Selecione as fases.');
    for (const phase of request.fases) {
      if (!phase.nome) throw Error('Fase sem nome.');
      const start = date(phase.dataInicial).split('/').reverse().join('-');
      const end = date(phase.dataFinal).split('/').reverse().join('-');
      if (start > end) throw Error('A data inicial da fase deve ser anterior ou igual à final.');
    }
  } else if (!/^\d+$/.test(String(request.solicitacao)) || !/^\d+$/.test(String(request.idTrabalho)) || !request.texto) throw Error('Comentário incompleto.');
  const newJob = {uid, action, request, enviar: body.enviar === true, retryUncertain: body.retryUncertain === true,
    operationId: String(body.operationId ?? crypto.randomUUID()), stage: 'opening', created: Date.now()};
  await chrome.storage.session.set({job: newJob});
  try {
    const runner = await chrome.tabs.create({url: chrome.runtime.getURL('runner.html'), active: action !== 'horas'});
    newJob.runnerTab = runner.id;
    await chrome.storage.session.set({job: newJob});
  } catch (error) { await chrome.storage.session.remove('job'); throw error; }
  return {accepted: true, operationId: newJob.operationId};
}
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (message?.type !== 'app' || !sender.tab || sender.frameId !== 0 || !appOrigins.has(new URL(sender.url).origin)) return;
  serialized(() => handle(message.payload)).then(respond, error => respond({error: error.message}));
  return true;
});
chrome.action.onClicked.addListener(() => chrome.tabs.create({url: 'https://promob.e-desk.com.br/'}));
