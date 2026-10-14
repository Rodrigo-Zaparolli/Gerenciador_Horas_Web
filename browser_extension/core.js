export function requestMatches(text, id) {
  if (!/^\d+$/.test(String(id))) return false;
  const label = normalize(text).match(/solicitacao\s*:?\s*(\d+)(?!\d)/);
  return !!label && label[1] === String(id);
}
export const normalize = value => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
export function retroactiveWorkUrl(workUrl, requestUrl) {
  const origin = 'https://promob.e-desk.com.br';
  const work = new URL(workUrl), request = new URL(requestUrl);
  if (work.origin !== origin || request.origin !== origin) throw Error('Endereço do E-Desk inválido.');
  const guid = work.searchParams.get('GUID') || request.searchParams.get('GUID');
  const id = work.searchParams.get('id_trabalho') || work.searchParams.get('idTrabalho');
  if (!guid || !id || !/^\d+$/.test(id)) throw Error('Identificador da tela do trabalho ausente.');
  const target = new URL('/Portal/TrabalhoRetroativo.aspx', origin);
  target.searchParams.set('GUID', guid);
  target.searchParams.set('id_trabalho', id);
  const solicitation = work.searchParams.get('solicitacao') || request.searchParams.get('solicitacao');
  if (solicitation) target.searchParams.set('solicitacao', solicitation);
  return target.href;
}
export function phaseKey(value) {
  const key = normalize(value).replace(/^promob\s*-?\s*/, '').replace(/-/g, ' ').replace(/\s+/g, ' ');
  return ['gerencia do projeto', 'gerenciamento do projeto', 'gerenciamento de projeto'].includes(key)
    ? 'gerenciamento de projetos' : key;
}
export function date(value) {
  const text = String(value ?? '').trim();
  const iso = /^(\d{4})-(\d{2})-(\d{2})/.exec(text);
  const formatted = iso ? `${iso[3]}/${iso[2]}/${iso[1]}` : text;
  const match = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(formatted);
  if (!match) throw Error('Data inválida.');
  const parsed = new Date(Date.UTC(+match[3], +match[2] - 1, +match[1]));
  if (parsed.getUTCDate() !== +match[1] || parsed.getUTCMonth() !== +match[2] - 1 || parsed.getUTCFullYear() !== +match[3]) throw Error('Data inválida.');
  return formatted;
}
export function hourType(value) {
  const key = normalize(value || '0');
  const type = ({interno: '0', externo: '1', padrao: '3', 'padrao (interno)': '4'})[key] ?? key;
  if (!['0', '1', '3', '4'].includes(type)) throw Error('Tipo de hora inválido.');
  return type;
}
export function appendComment(previous, current, day, description) {
  if (previous && current && !current.startsWith(previous)) throw Error('O comentário mudou. Envio interrompido para preservar o histórico.');
  const existing = current || previous;
  const clean = String(description ?? '').trim().replace(new RegExp(`^${day.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*:\\s*-?\\s*`), '');
  if (!clean) throw Error('Informe o descritivo da hora.');
  return existing + (existing && !/[\r\n]$/.test(existing) ? '\n' : '') + `${day}: - ${clean}`;
}
export async function hourKey(work, hour) {
  const values = [String(work.solicitacao).trim(), String(work.idTrabalho).trim(), date(hour.data), hour.inicio, hour.fim, hourType(hour.tipo)];
  // Match the existing Python journal, including json.dumps separators.
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('[' + values.map(value => JSON.stringify(value)).join(', ') + ']'));
  return [...new Uint8Array(bytes)].map(value => value.toString(16).padStart(2, '0')).join('');
}
export async function hourEntries(request) {
  if (!Array.isArray(request.trabalhos) || !request.trabalhos.length) throw Error('Selecione ao menos uma hora.');
  const entries = [];
  for (const work of request.trabalhos) {
    if (!/^\d+$/.test(String(work.solicitacao)) || !/^\d+$/.test(String(work.idTrabalho)) || !Array.isArray(work.horas) || !work.horas.length) throw Error('Solicitação ou trabalho inválido.');
    for (const hour of work.horas) {
      date(hour.data);
      if (![hour.inicio, hour.fim].every(value => /^([01]\d|2[0-3]):[0-5]\d$/.test(value)) || hour.inicio >= hour.fim) throw Error('Intervalo de horas inválido.');
      appendComment('', '', hour.data, hour.descritivo ?? hour.descricao ?? hour.comentario);
      entries.push({work, hour, key: await hourKey(work, hour)});
    }
  }
  if (new Set(entries.map(entry => entry.key)).size !== entries.length) throw Error('Há horas repetidas na seleção.');
  return entries;
}
export function cleanRequest(request) {
  if (!request || typeof request !== 'object' || Array.isArray(request)) throw Error('Dados inválidos.');
  // Allowlist: no password, token, arbitrary URL, or executable code enters jobs.
  return Object.fromEntries(['id', 'cliente', 'solicitacao', 'idTrabalho', 'tipo', 'texto', 'imagemBase64', 'fases', 'trabalhos'].filter(key => key in request).map(key => [key, request[key]]));
}
