/* Inline Brazilian Portuguese spelling, entirely local to this browser. */
(() => {
  'use strict';
  let sequence = 0;
  function attach(editor) {
    const root = editor.root, host = root.parentElement;
    const name = 'comment-spelling-' + (++sequence);
    const Delta = window.Quill.import('delta');
    const supported = !!(window.Highlight && CSS.highlights);
    let disposed = false, timer, serial = 0, pendingText = '', errors = [], menu, suggestionSerial = 0;
    const ignored = new Set();
    const badge = document.createElement('span'); badge.className = 'comment-spelling-status';
    badge.textContent = 'Carregando corretor...'; badge.setAttribute('role','status');
    host.append(badge);
    const style = document.createElement('style');
    style.textContent = `::highlight(${name}){text-decoration-line:underline;text-decoration-style:wavy;text-decoration-color:#e5484d;text-underline-offset:3px}
.comment-spelling-status{position:absolute;bottom:4px;right:10px;font:11px system-ui;color:inherit;opacity:.8;pointer-events:none}
.comment-spelling-menu{position:fixed;z-index:2147483646;min-width:190px;max-width:300px;padding:5px;background:#17283b;color:#fff;border:1px solid #69829c;border-radius:8px;box-shadow:0 5px 20px #0005;font:14px system-ui}
.comment-spelling-menu button{display:block;width:100%;padding:9px 12px;border:0;border-radius:4px;background:transparent;color:#fff;text-align:left;font:inherit;cursor:pointer}
.comment-spelling-menu button:hover,.comment-spelling-menu button:focus{background:#245370;outline:2px solid #3ac9ef}
.comment-spelling-menu p{padding:5px 12px;margin:0;color:#d4dfe9;font-size:12px}`;
    document.head.append(style);
    const worker = new Worker(new URL('vendor/comment-spelling/worker.js', document.baseURI));
    function text() {
      return editor.getContents().ops.map(op => typeof op.insert === 'string' ? op.insert : '￼').join('');
    }
    function hide() { if (menu) menu.remove(); menu = null; suggestionSerial++; }
    function clear() { errors = []; root.dataset.spellingErrors = '0'; if (supported) CSS.highlights.delete(name); }
    function schedule() {
      if (disposed) return;
      clearTimeout(timer); clear(); hide();
      timer = setTimeout(check, 300);
    }
    function check() {
      if (disposed) return;
      pendingText = text();
      const words = [...new Set([...pendingText.matchAll(/\p{L}[\p{L}\p{M}]*(?:[-'][\p{L}\p{M}]+)*/gu)].map(match => match[0]))]
        .filter(word => word.length > 1 && word.length <= 64 && !ignored.has(word));
      worker.postMessage({type:'check',id:++serial,words});
    }
    function rangeAt(index, length) {
      const [first, a] = editor.getLeaf(index), [last, b] = editor.getLeaf(index + length);
      if (!first?.domNode || !last?.domNode || first.domNode.nodeType !== 3 || last.domNode.nodeType !== 3) return null;
      const range = document.createRange(); range.setStart(first.domNode, a); range.setEnd(last.domNode, b); return range;
    }
    function showErrors(wrong) {
      clear();
      const set = new Set(wrong);
      for (const match of pendingText.matchAll(/\p{L}[\p{L}\p{M}]*(?:[-'][\p{L}\p{M}]+)*/gu)) {
        if (!set.has(match[0]) || ignored.has(match[0])) continue;
        const range = rangeAt(match.index, match[0].length);
        if (range) errors.push({index:match.index,word:match[0],range});
      }
      if (supported) CSS.highlights.set(name,new Highlight(...errors.map(error => error.range)));
      root.dataset.spellingErrors = String(errors.length);
      badge.textContent = 'Corretor portugu\u00eas';
      badge.title = 'Palavras sublinhadas: clique com o bot\u00e3o direito para ver sugest\u00f5es.';
    }
    function addButton(label, action) {
      const button = document.createElement('button'); button.type='button'; button.setAttribute('role','menuitem'); button.textContent=label;
      button.addEventListener('click',event => {event.preventDefault();event.stopPropagation();action();}); menu.append(button); return button;
    }
    function replace(error, replacement) {
      if (!editor.isEnabled() || text().slice(error.index,error.index+error.word.length)!==error.word) {hide();return;}
      const formats=editor.getFormat(error.index,error.word.length);
      hide(); editor.updateContents(new Delta().retain(error.index).delete(error.word.length).insert(replacement,formats),'user');
      editor.setSelection(error.index+replacement.length,0,'user');editor.focus({preventScroll:true});schedule();
    }
    let activeError;
    function context(event) {
      if (disposed || !editor.isEnabled()) return;
      const error=errors.find(error => [...error.range.getClientRects()].some(r=>event.clientX>=r.left-2&&event.clientX<=r.right+2&&event.clientY>=r.top-3&&event.clientY<=r.bottom+4));
      if (!error) {hide();return;}
      event.preventDefault();event.stopImmediatePropagation();hide();activeError=error;
      menu=document.createElement('div');menu.className='comment-spelling-menu';menu.setAttribute('role','menu');
      const loading=document.createElement('p');loading.textContent='Buscando sugest\u00f5es...';menu.append(loading);
      document.body.append(menu);menu.style.left=Math.min(event.clientX,window.innerWidth-310)+'px';menu.style.top=Math.min(event.clientY,window.innerHeight-320)+'px';
      worker.postMessage({type:'suggest',id:++suggestionSerial,word:error.word});
    }
    worker.onmessage=({data})=>{
      if(disposed)return;
      if(data.type==='ready'){badge.textContent='Corretor portugu\u00eas';check();}
      else if(data.type==='unavailable'){badge.textContent='Corretor indispon\u00edvel';clear();}
      else if(data.type==='checked'&&data.id===serial&&pendingText===text())showErrors(data.wrong);
      else if(data.type==='suggestions'&&menu&&data.id===suggestionSerial){
        menu.replaceChildren();const error=activeError;
        if(!data.values.length){const hint=document.createElement('p');hint.textContent='Sem sugest\u00f5es para esta palavra';menu.append(hint);}
        for(const value of data.values)addButton(value,()=>replace(error,value));
        addButton('Ignorar neste coment\u00e1rio',()=>{ignored.add(error.word);hide();check();});
      }
    };
    worker.onerror=()=>{if(!disposed){badge.textContent='Corretor indispon\u00edvel';clear();}};
    const outside=event=>{if(menu&&!menu.contains(event.target))hide();};
    const escape=event=>{if(menu&&event.key==='Escape'){hide();event.preventDefault();event.stopPropagation();}};
    editor.on('text-change',schedule);root.addEventListener('contextmenu',context,true);
    document.addEventListener('pointerdown',outside,true);document.addEventListener('keydown',escape,true);
    return {refresh:schedule,destroy(){disposed=true;clearTimeout(timer);clear();hide();worker.terminate();badge.remove();style.remove();editor.off('text-change',schedule);root.removeEventListener('contextmenu',context,true);document.removeEventListener('pointerdown',outside,true);document.removeEventListener('keydown',escape,true);}};
  }
  window.gerenciadorCommentSpelling={attach};
})();
