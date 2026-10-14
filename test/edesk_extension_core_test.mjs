import test from 'node:test';
import assert from 'node:assert/strict';
import {appendComment, cleanRequest, date, hourEntries, hourKey, phaseKey, retroactiveWorkUrl, requestMatches} from '../browser_extension/core.js';

test('retroactive hours accept both work parameter names and preserve the validated request session', () => {
  const request = 'https://promob.e-desk.com.br/Portal/Solicitacao.aspx?GUID=session&solicitacao=2265173';
  for (const parameter of ['id_trabalho', 'idTrabalho']) {
    const result = new URL(retroactiveWorkUrl(`https://promob.e-desk.com.br/Portal/Trabalho.aspx?${parameter}=123`, request));
    assert.equal(result.pathname, '/Portal/TrabalhoRetroativo.aspx');
    assert.equal(result.searchParams.get('id_trabalho'), '123');
    assert.equal(result.searchParams.get('GUID'), 'session');
    assert.equal(result.searchParams.get('solicitacao'), '2265173');
  }
  assert.throws(() => retroactiveWorkUrl('https://promob.e-desk.com.br/Portal/Trabalho.aspx', request));
  assert.throws(() => retroactiveWorkUrl('https://example.com/?id_trabalho=123', request));
});

const work = {solicitacao: '2265173', idTrabalho: '2', horas: [{data:'09/10/2026', inicio:'08:00', fim:'09:00', descricao:'Consultoria', tipo:'Interno'}]};
test('preserves complete history and appends below, rejects concurrent change', () => {
  assert.equal(appendComment('Anterior\n', 'Anterior\n', '09/10/2026', 'Consultoria'), 'Anterior\n09/10/2026: - Consultoria');
  assert.equal(appendComment('Anterior', '', '09/10/2026', '09/10/2026: - Consultoria'), 'Anterior\n09/10/2026: - Consultoria');
  assert.throws(() => appendComment('Anterior', 'Outro texto', '09/10/2026', 'Consultoria'));
});
test('identity excludes comments and normalizes hour type', async () => {
  const hour = work.horas[0];
  assert.equal(await hourKey(work, hour), await hourKey(work, {...hour, descricao:'Editado', tipo:'0'}));
  assert.notEqual(await hourKey(work, hour), await hourKey({...work,idTrabalho:'3'}, hour));
  assert.match(await hourKey(work,hour), /^[0-9a-f]{64}$/);
  assert.equal(await hourKey(work,hour), 'cf1192038fcb4752ca00445656fada92a9a4041604457a043b24ccaec58084eb');
});
test('validates actual dates, intervals and duplicate selections', async () => {
  assert.equal(date('2026-10-09T00:00:00'), '09/10/2026');
  assert.throws(() => date('31/02/2026'));
  assert.equal((await hourEntries({trabalhos:[work]})).length, 1);
  await assert.rejects(hourEntries({trabalhos:[{...work,horas:[...work.horas,...work.horas]}]}));
  await assert.rejects(hourEntries({trabalhos:[{...work,horas:[{...work.horas[0],fim:'07:00'}]}]}));
});
test('normalizes phase names without selecting unrelated stages', () => {
  assert.equal(phaseKey('Promob - Pós-Implantação'), 'pos implantacao');
  assert.equal(phaseKey('Gerência do Projeto'), 'gerenciamento de projetos');
  assert.notEqual(phaseKey('Consultoria'), phaseKey('Implantação'));
});
test('never retains passwords, tokens, arbitrary URLs or code', () => {
  const clean = cleanRequest({...work, edeskCredenciais:{senha:'secret'}, token:'secret',url:'https://evil.test',script:'code'});
  assert.deepEqual(Object.keys(clean).sort(), ['idTrabalho','solicitacao']);
});

test('validates visible solicitation number instead of encrypted portal URL identifiers', () => {
  assert.equal(requestMatches('Solicita\u00e7\u00e3o: 2265173 - Rimo', '2265173'), true);
  assert.equal(requestMatches('Solicita\u00e7\u00e3o 2265173', '2265173'), true);
  assert.equal(requestMatches('Solicita\u00e7\u00e3o: 2263892 Outros textos 2265173', '2265173'), false);
  assert.equal(requestMatches('Solicita\u00e7\u00e3o: 22651730', '2265173'), false);
  assert.equal(requestMatches('Comentario sobre 2265173', '2265173'), false);
});
