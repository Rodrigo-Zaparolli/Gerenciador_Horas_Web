// Tests rule source or the deployed rules using Firebase's rules test API.
// This script never writes documents, creates accounts, or publishes rules.
const fs = require('fs');
const path = require('path');
const project = 'gerenciador-horas';

async function main() {
  let root;
  try { root = path.dirname(require.resolve('firebase-tools/lib/auth')); }
  catch (_) { root = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib'); }
  const auth = require(path.join(root, 'auth'));
  const options = {project, nonInteractive: true};
  const account = auth.getProjectDefaultAccount(process.cwd());
  if (!account) throw new Error('Firebase CLI authentication required');
  auth.setActiveAccount(options, account);
  await require(path.join(root, 'requireAuth')).requireAuth(options);
  const rules = require(path.join(root, 'gcp/rules'));
  const files = process.argv.includes('--live')
    ? await rules.getRulesetContent(await rules.getLatestRulesetName(project, 'cloud.firestore'))
    : [{name: 'firestore.rules', content: fs.readFileSync('firestore.rules', 'utf8')}];
  const cases = [];
  for (const target of ['users/owner', 'users/owner/configuracoes/edesk_integracao',
    'users/owner/projects/project', 'users/owner/projects/project/time_logs/log']) {
    for (const method of ['get', 'create', 'update', 'delete']) {
      for (const uid of ['owner', 'other', null]) {
        cases.push({expectation: uid === 'owner' ? 'ALLOW' : 'DENY',
          request: {path: `/databases/(default)/documents/${target}`, method,
            auth: uid ? {uid, token: {sub: uid}} : null,
            resource: {data: {test: true}}}, resource: {data: {test: true}}});
      }
    }
  }
  cases.push({expectation: 'DENY', request: {path: '/databases/(default)/documents/public/test',
    method: 'get', auth: {uid: 'owner', token: {sub: 'owner'}}}});
  const api = require(path.join(root, 'api'));
  const client = new (require(path.join(root, 'apiv2')).Client)({urlPrefix: api.rulesOrigin(), apiVersion: 'v1'});
  const response = await client.post(`/projects/${project}:test`,
    {source: {files}, testSuite: {testCases: cases}}, {skipLog: {body: true, resBody: true}});
  const body = response.body;
  if (body.issues?.some(issue => issue.severity === 'ERROR')) {
    throw new Error('Rules source rejected: ' + JSON.stringify(body.issues));
  }
  const results = body.testResults || [];
  if (results.length !== cases.length || results.some(result => result.state !== 'SUCCESS')) {
    fs.mkdirSync('build/validation', {recursive: true});
    fs.writeFileSync('build/validation/firestore-rule-results.json', JSON.stringify(body, null, 2));
    throw new Error('Rules tests did not all pass; inspect build/validation/firestore-rule-results.json');
  }
  console.log(`RULES_TESTS_OK ${results.length} ${process.argv.includes('--live') ? 'deployed' : 'source'}`);
}
main().catch(error => { console.error('RULES_TESTS_FAILED ' + error.message); process.exitCode = 1; });
