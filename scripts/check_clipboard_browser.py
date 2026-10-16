"""Test compiled Dart clipboard adapters in Chromium, without real clipboard access."""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
fixture = ROOT / 'build/clipboard_adapter_fixture.js'
assert fixture.is_file(), 'Compile scripts/clipboard_adapter_fixture.dart first'

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(headless=True, executable_path=str(
        ROOT / 'python/ms-playwright/chromium-1187/chrome-win/chrome.exe'))
    page = browser.new_page()
    page.set_content('<html><body></body></html>')
    page.add_script_tag(path=str(fixture))
    page.wait_for_function('document.body.dataset.ready === "true"')

    def events():
        return json.loads(page.evaluate('document.body.dataset.events'))

    def active(value):
        page.evaluate('(value) => document.body.dataset.active = value', value)

    def paste(text='', size=0, change_focus=False):
        return page.evaluate('''({text, size, changeFocus}) => {
          const transfer = new DataTransfer();
          if (text) transfer.setData('text/plain', text);
          if (size) transfer.items.add(new File([new Uint8Array(size)], 'test.png', {type:'image/png'}));
          const event = new ClipboardEvent('paste', {clipboardData:transfer, bubbles:true, cancelable:true});
          document.dispatchEvent(event);
          if (changeFocus) document.body.dataset.active = '';
          return event.defaultPrevented;
        }''', {'text': text, 'size': size, 'changeFocus': change_focus})

    assert paste('Unfocused') is False
    assert events() == []
    active('comment')
    assert paste('Current text\nSecond line') is True
    assert events() == [{'kind': 'text', 'text': 'Current text\nSecond line'}]
    assert paste(size=12) is True
    page.wait_for_function('JSON.parse(document.body.dataset.events).length === 2')
    assert events()[-1] == {'kind': 'comment-image', 'bytes': 12}
    active('image')
    assert paste(size=24) is True
    page.wait_for_function('JSON.parse(document.body.dataset.events).length === 3')
    assert events()[-1] == {'kind': 'image', 'bytes': 24}
    assert paste(size=10 * 1024 * 1024 + 1) is True
    assert events()[-1] == {'kind': 'error'}
    before = events()
    paste(size=16, change_focus=True)
    page.wait_for_timeout(200)
    assert events() == before, 'Late image must not enter an unfocused editor'
    active('comment')
    page.evaluate('document.dispatchEvent(new Event("disposeClipboardFixture"))')
    assert paste('After disposal') is False
    assert events() == before
    browser.close()

print('CLIPBOARD_ADAPTERS_OK: compiled Dart, text once, comment/image routing, focus, size limit, late-event isolation, disposal; synthetic events only')
