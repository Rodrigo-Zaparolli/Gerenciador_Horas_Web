// Offline bridge contract: no browser login, network or user file access.
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const requests = [];
const context = {
  window: {}, navigator: {permissions: {query: async () => ({state:'granted'})}},
  AbortController, setTimeout, clearTimeout,
  fetch: async (url, options) => {
    requests.push({url, body:JSON.parse(options.body)});
    return {status:200,json:async()=>({opened:true})};
  },
};
vm.runInNewContext(fs.readFileSync('web/native_local_files_v2.js','utf8'), context);
(async()=>{
  const base={action:'open',interactive:true,token:'test-token',reference:'desktop-folder://local/owner/12345678-1234-1234-1234-123456789012/Documentos'};
  await context.window.nativeLocalFilesRequest(JSON.stringify({...base,projectId:'2263800'}));
  await context.window.nativeLocalFilesRequest(JSON.stringify(base));
  assert.equal(requests[0].body.projectId,'2263800');
  assert.equal(requests[0].body.reference,base.reference);
  assert.equal(requests[1].body.projectId,undefined);
  assert.equal(requests.length,2);
  assert.equal(context.window.nativeLocalFilesBridgeVersion,'project-link-recovery-8');
  assert.ok(fs.readFileSync('web/index.html','utf8').includes('native_local_files_v2.js?v=project-links-46'));
  console.log('BRIDGE_PROJECT_ID_FORWARDING_OK');
})().catch(error=>{console.error(error.message);process.exitCode=1;});
