/* Browser-native comment editing. Quill 2.0.3 is bundled locally under BSD-3-Clause. */
(function () {
  'use strict';
  let loading;
  function load() {
    if (window.Quill) return Promise.resolve(window.Quill);
    if (!loading) loading = new Promise((resolve, reject) => {
      const css = document.createElement('link'); css.rel = 'stylesheet';
      css.href = new URL('vendor/quill-2.0.3/quill.core.css', document.baseURI).href;
      document.head.append(css);
      const script = document.createElement('script');
      script.src = new URL('vendor/quill-2.0.3/quill.js', document.baseURI).href;
      script.onload = () => resolve(window.Quill); script.onerror = () => { loading = null; reject(new Error('Editor indisponivel')); };
      document.head.append(script);
    });
    return loading;
  }
  function incoming(delta) {
    return { ops: delta.map(op => {
      const result = { ...op, attributes: op.attributes ? { ...op.attributes } : undefined };
      if (result.attributes?.size && /^\d+(\.\d+)?$/.test(String(result.attributes.size))) result.attributes.size += 'px';
      if (result.attributes?.color && /^#[\da-f]{8}$/i.test(result.attributes.color)) result.attributes.color = '#' + result.attributes.color.slice(3);
      return result;
    }) };
  }
  function outgoing(delta) {
    return delta.ops.map(op => {
      const result = { ...op, attributes: op.attributes ? { ...op.attributes } : undefined };
      if (typeof result.attributes?.size === 'string') result.attributes.size = result.attributes.size.replace(/px$/, '');
      if (!result.attributes || !Object.keys(result.attributes).length) delete result.attributes;
      return result;
    });
  }
  function register(Quill) {
    if (Quill.__commentFormats) return;
    const Font = Quill.import('attributors/style/font'); Font.whitelist = null; Quill.register(Font, true);
    const Size = Quill.import('attributors/style/size'); Size.whitelist = null; Quill.register(Size, true);
    const Image = Quill.import('formats/image');
    class CommentImage extends Image {
      static formats(node) { return { ...super.formats(node), ...(node.dataset.commentImageStyle ? { style: node.dataset.commentImageStyle } : {}) }; }
      format(name, value) {
        if (name !== 'style') return super.format(name, value);
        const safe = String(value || '').match(/(?:^|;)\s*(?:width|height)\s*:\s*\d+(?:\.\d+)?(?:px|%)\s*(?=;|$)/g) || [];
        const style = safe.map(s => s.replace(/^;/, '').trim()).join(';');
        this.domNode.dataset.commentImageStyle = style;
        for (const match of style.matchAll(/(width|height)\s*:\s*([\d.]+(?:px|%))/g)) this.domNode.style[match[1]] = match[2];
      }
    }
    Quill.register(CommentImage, true); Quill.__commentFormats = true;
  }
  async function create(host, initial, changed, selected) {
    const Quill = await load(); register(Quill);
    const Delta = Quill.import('delta');
    function tab(range, context, backwards) {
      const prefix = editor.getText(0, range.index).split('\n').pop();
      if (backwards) {
        if (range.length) return false;
        const limit = prefix.length % 4 || 4;
        let count = 0; while (count < limit && /[ \u00a0]/.test(prefix[prefix.length - count - 1] || '\n')) count++;
        if (count) { editor.deleteText(range.index - count, count, 'user'); editor.setSelection(range.index - count, 0, 'silent'); }
      } else {
        const text = '\u00a0'.repeat(4 - prefix.length % 4);
        editor.updateContents(new Delta().retain(range.index).delete(range.length).insert(text, editor.getFormat(range.index, 0)), 'user');
        editor.setSelection(range.index + text.length, 0, 'silent');
      }
      publishSelection(); return false;
    }
    const editor = new Quill(host, { theme: null, placeholder: 'Digite sua resposta ou atualiza\u00e7\u00e3o para o E-Desk...', modules: { toolbar: false,
      keyboard: { bindings: {
        commentTab: { key: 'Tab', shiftKey: false, handler: function(range, context) { return tab(range, context, false); } },
        commentBackTab: { key: 'Tab', shiftKey: true, handler: function(range, context) { return tab(range, context, true); } }
      } }
    }});
    const root = editor.root; host.dataset.commentNativeEditor = 'true'; host.classList.add('comment-native');
    if (!document.getElementById('comment-native-style')) { const style = document.createElement('style'); style.id='comment-native-style'; style.textContent='.comment-native .ql-editor.ql-blank::before{color:var(--comment-placeholder,#8193a5);font-style:normal}.comment-native.ql-container{border:0}.comment-native .ql-editor img{max-width:100%}'; style.textContent += "@font-face{font-family:'Roboto';src:url('assets/assets/fonts/Roboto-Regular.ttf');font-weight:400;font-style:normal;font-display:swap;}@font-face{font-family:'Roboto';src:url('assets/assets/fonts/Roboto-Bold.ttf');font-weight:700;font-style:normal;font-display:swap;}@font-face{font-family:'Lato';src:url('assets/assets/fonts/Lato-Regular.ttf');font-weight:400;font-style:normal;font-display:swap;}@font-face{font-family:'Lato';src:url('assets/assets/fonts/Lato-Bold.ttf');font-weight:700;font-style:normal;font-display:swap;}@font-face{font-family:'Lato';src:url('assets/assets/fonts/Lato-Italic.ttf');font-weight:400;font-style:italic;font-display:swap;}@font-face{font-family:'Lato';src:url('assets/assets/fonts/Lato-BoldItalic.ttf');font-weight:700;font-style:italic;font-display:swap;}@font-face{font-family:'Noto Serif';src:url('assets/assets/fonts/NotoSerif.ttf');font-weight:400;font-style:normal;font-display:swap;}@font-face{font-family:'Noto Serif';src:url('assets/assets/fonts/NotoSerif.ttf');font-weight:700;font-style:normal;font-display:swap;}@font-face{font-family:'Noto Serif';src:url('assets/assets/fonts/NotoSerif-Italic.ttf');font-weight:400;font-style:italic;font-display:swap;}@font-face{font-family:'Roboto Mono';src:url('assets/assets/fonts/RobotoMono.ttf');font-weight:400;font-style:normal;font-display:swap;}@font-face{font-family:'Roboto Mono';src:url('assets/assets/fonts/RobotoMono.ttf');font-weight:700;font-style:normal;font-display:swap;}@font-face{font-family:'Roboto Mono';src:url('assets/assets/fonts/RobotoMono-Italic.ttf');font-weight:400;font-style:italic;font-display:swap;}"; document.head.append(style); }
    root.lang = 'pt-BR'; root.spellcheck = true; root.setAttribute('autocorrect', 'on');
    root.setAttribute('autocapitalize', 'sentences'); root.setAttribute('role', 'textbox');
    root.setAttribute('aria-label', 'Descri\u00e7\u00e3o do coment\u00e1rio'); root.setAttribute('aria-multiline', 'true');
    root.style.fontFamily = 'Roboto, sans-serif'; root.style.fontSize = '16px';
    let updating = false, disposed = false;
    function publishSelection() { const r = editor.getSelection(); if (r && !disposed) selected(r.index, r.index + r.length); }
    const textHandler = () => { if (!updating && !disposed) { const r = editor.getSelection() || { index: 0, length: 0 }; changed(JSON.stringify(outgoing(editor.getContents())), r.index, r.index + r.length); queueMicrotask(() => { if (!disposed) publishSelection(); }); } };
    const selectionHandler = r => { if (!updating && !disposed && r) selected(r.index, r.index + r.length); };
    editor.on('text-change', textHandler); editor.on('selection-change', selectionHandler);
    const paste = event => {
      event.preventDefault(); event.stopImmediatePropagation();
      if (!editor.isEnabled()) return;
      const r = editor.getSelection(true) || { index: editor.getLength() - 1, length: 0 };
      const text = (event.clipboardData?.getData('text/plain') || '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
      if (text) {
        editor.updateContents(new Delta().retain(r.index).delete(r.length).insert(text, editor.getFormat(r.index, 0)), 'user');
        editor.setSelection(r.index + text.length, 0, 'silent'); publishSelection(); return;
      }
      const image = [...(event.clipboardData?.files || [])].find(f => /^image\//.test(f.type) && f.size <= 10 * 1024 * 1024);
      if (image) { const reader = new FileReader(); reader.onload = () => { if (disposed || !editor.isEnabled()) return; editor.updateContents(new Delta().retain(r.index).delete(r.length).insert({image:reader.result}), 'user'); editor.setSelection(r.index + 1, 0, 'silent'); publishSelection(); }; reader.readAsDataURL(image); }
    };
    const keys = event => {
      if (event.key === 'Tab' && !event.ctrlKey && !event.metaKey && !event.altKey) {
        event.preventDefault(); event.stopImmediatePropagation();
        const range = editor.getSelection(true);
        if (range && editor.isEnabled()) tab(range, null, event.shiftKey);
      }
    };
    root.addEventListener('keydown', keys, true);
    root.addEventListener('paste', paste, true);
    const handle = {
      update(json, start, end, formats, readOnly) {
        if (disposed) return;
        updating = true;
        try {
          const next = new Delta(incoming(JSON.parse(json)).ops); const diff = editor.getContents().diff(next);
          if (diff.ops.length) editor.updateContents(diff, 'api');
          editor.enable(!readOnly);
          const a = Math.max(0, Math.min(start, editor.getLength() - 1)), b = Math.max(a, Math.min(end, editor.getLength() - 1));
          // Keep the DOM range for toolbar changes without stealing focus from other fields.
          editor.setSelection(a, b - a, 'silent');
          if (a === b) {
            const active = incoming([{insert:'x',attributes:JSON.parse(formats)}]).ops[0].attributes || {};
            for (const key of ['bold','italic','underline','strike','font','size','color','background']) {
              editor.format(key, active[key] ?? false, 'silent');
            }
          }
        } finally { updating = false; }
      },
      focus() { if (!disposed) editor.focus({preventScroll:true}); },
      destroy() { disposed = true; root.removeEventListener('paste', paste, true); root.removeEventListener('keydown', keys, true); editor.off('text-change', textHandler); editor.off('selection-change', selectionHandler); editor.disable(); editor.scroll?.observer?.disconnect?.(); host.replaceChildren(); },
      editor
    };
    updating = true; editor.setContents(incoming(JSON.parse(initial)), 'silent'); editor.history.clear(); updating = false;
    return handle;
  }
  window.gerenciadorNativeComment = { create, update:(h,...args)=>h.update(...args), focus:h=>h.focus(), destroy:h=>h.destroy() };
})();
