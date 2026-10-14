import {edeskDom} from './page-dom.js';
import {date, hourEntries, hourType, retroactiveWorkUrl, requestMatches} from './core.js';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const origin = 'https://promob.e-desk.com.br';
const ownTabs = new Set();
let job, running = false, attempted = false;
const status = document.querySelector('#status');
const start = document.querySelector('#start');
const cancel = document.querySelector('#cancel');
const runnerTab = await chrome.tabs.getCurrent();
async function save() {
  const current = (await chrome.storage.session.get('job')).job;
  if (current?.operationId !== job.operationId || current.runnerTab !== runnerTab.id) throw Error('A operação mudou.');
  await chrome.storage.session.set({job});
}
async function stage(value, message) {job.stage = value; status.textContent = message; await save();}
async function finish(confirmed, message, code = confirmed ? 200 : 409) {
  job.result = {confirmed, statusCode: code, message, responseBody: ''};
  job.stage = 'finished'; delete job.request;
  await save(); status.textContent = message; start.disabled = true; cancel.disabled = true;
}
async function history() {
  const key = `history:${job.uid}`;
  return (await chrome.storage.local.get(key))[key] ?? {};
}
async function record(key, state) {
  const entries = await history(); entries[key] = state;
  await chrome.storage.local.set({[`history:${job.uid}`]: entries});
}
async function create(url) {
  const parsed = new URL(url);
  if (parsed.origin !== origin) throw Error('Navegação para domínio não permitido.');
  const tab = await chrome.tabs.create({url: parsed.href, active: true});
  ownTabs.add(tab.id); return tab.id;
}
async function execute(tabId, action, args = {}, frameId = 0) {
  const tab = await chrome.tabs.get(tabId);
  if (!ownTabs.has(tabId) || new URL(tab.url).origin !== origin) throw Error('A aba do E-Desk foi fechada ou mudou de endereço.');
  const [result] = await chrome.scripting.executeScript({target: {tabId, frameIds: [frameId]}, world: 'MAIN', func: edeskDom, args: [action, args]});
  if (!result?.result || result.result.error) throw Error(result?.result?.error ?? 'Não foi possível ler o E-Desk.');
  for (const url of result.result.urls ?? []) await create(url);
  return result.result;
}
async function frames(tabId) {
  try {
    const tab = await chrome.tabs.get(tabId);
    if (new URL(tab.url).origin !== origin) return [];
    return await chrome.scripting.executeScript({target: {tabId, allFrames: true}, world: 'MAIN', func: edeskDom, args: ['inspect']});
  } catch (_) {return [];}
}
async function wait(predicate, timeout = 30000) {
  const until = Date.now() + timeout;
  while (Date.now() < until) {
    // Track only popups spawned by this operation, never old E-Desk pages.
    for (const tab of await chrome.tabs.query({url: origin + '/*'})) {
      if (ownTabs.has(tab.openerTabId)) ownTabs.add(tab.id);
    }
    for (const tabId of ownTabs) for (const frame of await frames(tabId)) {
      const state = frame.result;
      if (state && !state.error && state.ready && !state.ajax && predicate(state, tabId, frame.frameId)) return {tabId, frameId: frame.frameId, state};
    }
    await sleep(450);
  }
  throw Error('O E-Desk não apresentou a tela esperada. Confira o resultado antes de reenviar.');
}
async function settle(page) {
  await sleep(1200);
  return wait((state, tabId, frameId) => tabId === page.tabId && frameId === page.frameId, 20000);
}
async function reload(page, predicate) {
  const old = await execute(page.tabId, 'inspect', {}, page.frameId);
  await chrome.tabs.reload(page.tabId);
  return wait((state, tabId, frameId) => tabId === page.tabId && frameId === page.frameId &&
    state.documentToken !== old.documentToken && predicate(state));
}
async function click(page, action, args = {}) {
  // A WebForms navigation can destroy the execution context after the click.
  // Wait for the new screen without repeating the click.
  try {await execute(page.tabId, action, args, page.frameId);} catch (error) {
    if (!/frame|context|navigation|removed|Cannot access/i.test(error.message)) throw error;
  }
}
async function openRequest(id) {
  const tabs = await chrome.tabs.query({url: origin + '/*'});
  let guid;
  for (const tab of tabs) {
    const candidate = new URL(tab.url).searchParams.get('GUID');
    if (candidate) {guid = candidate; break;}
  }
  if (!guid) {
    await create(origin + '/');
    await stage('login', 'Entre no E-Desk na aba aberta. Depois o envio continuará automaticamente.');
    const logged = await wait(state => !!new URL(state.url).searchParams.get('GUID'), 300000);
    guid = new URL(logged.state.url).searchParams.get('GUID');
  }
  const gridId = await create(origin + '/Portal/ListaSolicitacao.aspx?GUID=' + encodeURIComponent(guid));
  let grid = await wait((state, tabId) => tabId === gridId && state.grid);
  const before = new Map((await chrome.tabs.query({url: origin + '/*'})).map(tab => [tab.id, tab.url]));
  const fresh = (state, tabId) => before.get(tabId) !== state.url;
  await stage('preparing', 'Localizando solicitação ' + id + '…');
  await click(grid, 'search', {id: String(id)});
  await sleep(1800);
  let request;
  try {
    request = await wait((state, tabId) => fresh(state, tabId) && /\/Solicitacao\.aspx$/i.test(new URL(state.url).pathname), 3000);
  } catch (_) {
    grid = await wait((state, tabId) => tabId === gridId && state.grid);
    await click(grid, 'open-request', {id: String(id)});
    request = await wait((state, tabId) => fresh(state, tabId) && /\/Solicitacao\.aspx$/i.test(new URL(state.url).pathname));
  }
  // Portal query values may be encrypted identifiers, not the displayed number.
  if (!requestMatches(request.state.text, id)) throw Error('A tela nao confirmou o numero da solicitacao selecionada.');
  return request;
}
async function openWork(work) {
  const request = await openRequest(work.solicitacao);
  const before = new Map((await chrome.tabs.query({url: origin + '/*'})).map(tab => [tab.id, tab.url]));
  try {await execute(request.tabId, 'open-work', {id: String(work.idTrabalho)}, request.frameId);} catch (error) {
    if (!error.message.includes('Trabalho não localizado')) throw error;
    await click(request, 'tab', {name: 'Trabalhos'});
    await settle(request);
    await click(request, 'open-work', {id: String(work.idTrabalho)});
  }
  const page = await wait((state, tabId) => before.get(tabId) !== state.url && /\/Trabalho\.aspx$/i.test(new URL(state.url).pathname));
  const url = new URL(page.state.url);
  const urlMatches = url.searchParams.get('solicitacao') === String(work.solicitacao) &&
    (url.searchParams.get('id_trabalho') || url.searchParams.get('idTrabalho')) === String(work.idTrabalho);
  const labelMatches = new RegExp('Solicita[cç][aã]o\\s*/\\s*Trabalho\\s*:?\\s*' +
    work.solicitacao + '\\s*/\\s*' + work.idTrabalho + '(?!\\d)', 'i').test(page.state.text);
  if (!urlMatches && !labelMatches) throw Error('A tela não confirmou a solicitação e o trabalho selecionados.');
  return {...page, requestUrl: request.state.url};
}
async function sendHours() {
  const entries = await hourEntries(job.request);
  let lastWork, page, sent = 0, skipped = 0;
  for (const {work, hour, key} of entries) {
    const stored = (await history())[key];
    if (stored === 'confirmed') {skipped++; continue;}
    if (['pending','uncertain'].includes(stored) && !job.retryUncertain) throw Error('Confira a tentativa anterior antes de reenviar.');
    const identity = work.solicitacao + '/' + work.idTrabalho;
    if (identity !== lastWork) {
      const opened = await openWork(work);
      const url = retroactiveWorkUrl(opened.state.url, opened.requestUrl);
      await stage('preparing', 'Abrindo a tela de lançamento de horas…');
      const tabId = await create(url);
      page = await wait((state, id) => id === tabId && state.hours);
      lastWork = identity;
    }
    const initial = await execute(page.tabId, 'hour-read', {hour}, page.frameId);
    if (initial.count > 0) {
      if (job.enviar) await record(key, 'confirmed');
      skipped++; continue;
    }
    await execute(page.tabId, 'hour-type', {tipo: hourType(hour.tipo)}, page.frameId);
    await settle(page);
    const args = {hour, count: initial.count, previous: initial.previous, tipo: hourType(hour.tipo),
      description: hour.descritivo ?? hour.descricao ?? hour.comentario};
    const filled = await execute(page.tabId, 'hour-fill', args, page.frameId);
    if (!job.enviar) continue;
    // Persist BEFORE a potentially successful click. Never auto retry uncertain saves.
    await record(key, 'uncertain'); attempted = true;
    await stage('sending', `Enviando hora ${sent + 1}: ${identity}, ${hour.data}…`);
    await click(page, 'save-hour');
    await sleep(1800);
    await execute(page.tabId, 'confirm-long-hour', {}, page.frameId).catch(() => {});
    await settle(page);
    // Confirm persistence from a new server-rendered document, not merely
    // from the values filled in the previous DOM or optimistic UI updates.
    page = await reload(page, state => state.hours);
    let confirmed = false;
    for (let attempt = 0; attempt < 20; attempt++) {
      const result = await execute(page.tabId, 'hour-check', {hour}, page.frameId);
      if (result.count === initial.count + 1 && result.comment.startsWith(filled.comment)) {confirmed = true; break;}
      await sleep(600);
    }
    if (!confirmed) throw Error('Não foi possível confirmar a hora na tabela e a preservação do comentário. Confira no E-Desk antes de reenviar.');
    await record(key, 'confirmed'); sent++;
  }
  await finish(job.enviar, job.enviar ? `${sent} hora(s) confirmada(s). ${skipped} já registrada(s), sem reenvio.` : 'Teste concluído: campos preparados, sem salvar no E-Desk.', 200);
}
async function sendPhases() {
  const phases = job.request.fases.map(phase => ({...phase, dataInicial: date(phase.dataInicial), dataFinal: date(phase.dataFinal)}));
  const page = await openRequest(job.request.id);
  if (!page.state.phases) {await click(page, 'tab', {name: 'Fases'}); await settle(page);}
  await execute(page.tabId, 'phases', {phases, fill: true}, page.frameId);
  if (!job.enviar) return finish(false, 'Teste concluído: apenas as fases selecionadas foram preenchidas, sem salvar.', 200);
  attempted = true; await stage('sending', 'Salvando as fases selecionadas…');
  await click(page, 'save-phases'); await settle(page);
  const refreshed = await reload(page, state => /Solicitacao\.aspx/i.test(state.url));
  if (!refreshed.state.phases) {await click(refreshed, 'tab', {name: 'Fases'}); await settle(refreshed);}
  const result = await execute(refreshed.tabId, 'phases', {phases, fill: false}, refreshed.frameId);
  if (!result.values.every((values, index) => values[0] === phases[index].dataInicial && values[1] === phases[index].dataFinal)) throw Error('As datas não foram confirmadas após recarregar o E-Desk.');
  await finish(true, `${phases.length} fase(s) confirmada(s) após recarregar o E-Desk.`);
}
async function sendComment() {
  const page = await openWork(job.request);
  await click(page, 'open-comment');
  const popup = await wait(state => state.comment);
  await execute(popup.tabId, 'comment-type', {tipo: String(job.request.tipo)}, popup.frameId);
  await settle(popup);
  const filled = await execute(popup.tabId, 'comment-fill', {text: job.request.texto, image: job.request.imagemBase64}, popup.frameId);
  const baseline = await execute(page.tabId, 'comment-evidence', {text: filled.text}, page.frameId);
  if (!job.enviar) return finish(false, 'Teste concluído: comentário preparado, sem salvar.', 200);
  attempted = true; await stage('sending', 'Salvando o comentário…');
  await click(popup, 'save-comment');
  await sleep(2200);
  const refreshed = await reload(page, state => /Trabalho\.aspx/i.test(state.url));
  const evidence = await execute(refreshed.tabId, 'comment-evidence', {text: filled.text}, refreshed.frameId);
  // A reload followed by a new rendered record is required. Image persistence
  // needs manual review until the E-Desk attachment listing is validated.
  if (filled.text && !filled.hasImage && evidence.count === baseline.count + 1) {
    await finish(true, 'Comentário confirmado no histórico após recarregar o E-Desk.');
  } else {
    await finish(false, 'O comentário foi enviado para salvar. Confira o texto e as imagens no histórico do E-Desk antes de repetir; não foi possível confirmar o registro completo automaticamente.');
  }
}
try {
  // The worker attaches runnerTab immediately after creating this page.
  for (let attempt = 0; attempt < 20; attempt++) {
    job = (await chrome.storage.session.get('job')).job;
    if (job?.runnerTab === runnerTab.id) break;
    await sleep(100);
  }
  if (!job || job.runnerTab !== runnerTab.id || job.result) throw Error('Esta operação já terminou ou não está disponível.');
  if (job.started) {
    await finish(false, 'A aba foi recarregada durante a operação. Confira o E-Desk antes de reenviar.', 409);
    throw Error('A operação foi interrompida. Confira o resultado no E-Desk.');
  }
  document.querySelector('#summary').textContent = job.action === 'horas'
    ? (await hourEntries(job.request)).map(({work,hour}) => `${work.solicitacao}/${work.idTrabalho} · ${hour.data} · ${hour.inicio}–${hour.fim}\n${hour.descritivo ?? hour.descricao ?? ''}`).join('\n\n')
    : job.action === 'fases' ? `Solicitação ${job.request.id}\n` + job.request.fases.map(phase => `${phase.nome}: ${date(phase.dataInicial)}–${date(phase.dataFinal)}`).join('\n')
    : `Solicitação ${job.request.solicitacao} / trabalho ${job.request.idTrabalho}\nComentário preparado no aplicativo.`;
  status.textContent = 'Abra o E-Desk para conferir a conta, depois clique em Iniciar envio.';
  start.disabled = false;
  const begin = async () => {
    if (running) return;
    running = true; start.disabled = true; cancel.disabled = true;
    try {
      job.started = true; await save();
      await ({horas: sendHours, fases: sendPhases, comentarios: sendComment})[job.action]();
    }
    catch (error) {await finish(false, error.message + (attempted ? ' Não reenvie sem conferir os registros já salvos.' : ''), 409);}
  };
  start.addEventListener('click', begin);
  if (job.action === 'horas') {
    document.querySelector('#summary').hidden = true;
    start.hidden = true; cancel.hidden = true;
    document.querySelector('main > p').textContent = 'Enviando as horas selecionadas no aplicativo.';
    await begin();
  }
  cancel.addEventListener('click', () => {if (!running) finish(false, 'Envio cancelado antes de salvar.', 499);});
} catch (error) {status.textContent = error.message; start.disabled = true;}
