"""Uses real browser filesystem handles in an isolated origin, no user files."""
from pathlib import Path
from playwright.sync_api import sync_playwright

root = Path(__file__).resolve().parents[1]
with sync_playwright() as p:
    browser = p.chromium.launch(channel='chrome', headless=True)
    page = browser.new_page()
    page.route('https://local-files.test/**', lambda route: route.fulfill(content_type='text/html', body='<html><body>Local files test</body></html>'))
    page.goto('https://local-files.test/')
    script = (root/'web/project_local_files.js').read_text(encoding='utf-8')
    page.evaluate(script)
    page.evaluate("""async () => {
      const root = await navigator.storage.getDirectory();
      const base = await root.getDirectoryHandle('Pasta do Projeto', {create:true});
      const file = await base.getFileHandle('exemplo.txt', {create:true});
      const writer = await file.createWritable(); await writer.write('Texto preservado'); await writer.close();
      await base.getDirectoryHandle('Subpasta', {create:true});
      window.showDirectoryPicker = async () => base;
      window.showOpenFilePicker = async () => [file];
    }""")

    def call(action, **args):
        return page.evaluate('async args=>JSON.parse(await window.projectLocalFilesCall(JSON.stringify(args)))', {'uid':'test-user','action':action,**args})

    folder = call('pick-folder')['reference']
    assert folder.startswith('browser-folder://local/test-user/')
    items = call('list', reference=folder)['items']
    assert items == [{'name':'Subpasta','kind':'directory'}, {'name':'exemplo.txt','kind':'file'}]
    assert call('read', reference=folder, name='exemplo.txt')['base64'] == 'VGV4dG8gcHJlc2VydmFkbw=='
    created = call('create-folder', name='2265173 - RIMO')['reference']
    assert call('list', reference=created)['items'] == []
    file = call('pick-file')['reference']
    assert call('read', reference=file)['base64'] == 'VGV4dG8gcHJlc2VydmFkbw=='
    page.evaluate("""() => {
      window.showOpenFilePicker = undefined;
      document.body.innerHTML = '<button id="pick">Selecionar arquivo</button>';
      document.querySelector('#pick').onclick = () => {
        window.fallbackResult = window.projectLocalFilesCall(JSON.stringify({uid:'test-user',action:'pick-file'}));
      };
    }""")
    with page.expect_file_chooser() as chooser:
        page.locator('#pick').click()
    chooser.value.set_files({'name':'snapshot.txt','mimeType':'text/plain','buffer':b'Copia local'})
    snapshot = page.evaluate('async()=>JSON.parse(await window.fallbackResult)')['reference']
    assert call('read', reference=snapshot)['base64'] == 'Q29waWEgbG9jYWw='
    page.reload()
    page.evaluate(script)
    assert call('read', reference=snapshot)['base64'] == 'Q29waWEgbG9jYWw='
    with page.expect_download() as download:
        assert call('download', reference=file)['ok']
    assert download.value.suggested_filename == 'exemplo.txt'
    assert 'error' in call('list', reference=folder, path=['..'])
    assert 'error' in call('read', reference=file, uid='other-user')
    page.reload()
    page.evaluate(script)
    assert call('list', reference=created)['items'] == []
    assert call('read', reference=file)['base64'] == 'VGV4dG8gcHJlc2VydmFkbw=='
    page.evaluate("() => {window.showDirectoryPicker=async()=>{throw new DOMException('cancelled','AbortError')}}")
    assert call('pick-folder')['cancelled']
    page.evaluate('window.showDirectoryPicker=undefined')
    assert 'Chrome ou Edge' in call('pick-folder')['error']
    second = browser.new_context()
    other = second.new_page()
    other.route('https://local-files.test/**', lambda route: route.fulfill(content_type='text/html', body='<html><body>Other browser</body></html>'))
    other.goto('https://local-files.test/')
    other.evaluate(script)
    result = other.evaluate('async args=>JSON.parse(await window.projectLocalFilesCall(JSON.stringify(args)))', {'uid':'test-user','action':'list','reference':folder})
    assert 'outro navegador' in result['error']
    second.close()
    browser.close()
print('BROWSER_LOCAL_FILES_OK: pick/create folder, file attachment, read/download, persistence, cancellation, account/browser isolation, traversal rejection, unsupported browser')
