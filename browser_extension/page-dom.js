// Self contained: serialized by chrome.scripting into the E-Desk page.
export async function edeskDom(action, args = {}) {
  try {
    const visible = element => !!element && !!element.getClientRects().length && getComputedStyle(element).visibility !== 'hidden';
    const one = selector => {
      const elements = [...document.querySelectorAll(selector)].filter(visible);
      if (elements.length !== 1) throw Error('Campo ausente ou ambíguo: ' + selector);
      return elements[0];
    };
    const fill = (selector, value, change = false) => {
      const element = one(selector);
      if (element.disabled || element.readOnly) throw Error('Campo bloqueado: ' + selector);
      if (element.tagName === 'SELECT' && ![...element.options].some(option => option.value === value)) throw Error('Opção não disponível no E-Desk.');
      element.value = value;
      element.dispatchEvent(new Event('input', {bubbles: true}));
      if (change) element.dispatchEvent(new Event('change', {bubbles: true}));
      return element.value;
    };
    const norm = value => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
    const phaseKey = value => {
      const key = norm(value).replace(/^promob\s*-?\s*/, '').replace(/-/g, ' ').replace(/\s+/g, ' ');
      return ['gerencia do projeto', 'gerenciamento do projeto', 'gerenciamento de projeto'].includes(key) ? 'gerenciamento de projetos' : key;
    };
    const countHours = hour => {
      const table = document.querySelector('[id*="gvwTempos"]');
      if (!table) throw Error('Tabela de horas não encontrada. Não é seguro enviar.');
      return [...table.querySelectorAll('tr')].filter(row => {
        const values = [...row.querySelectorAll('td')].map(cell => cell.innerText.trim());
        return [hour.data, hour.inicio, hour.fim].every(value => values.includes(value));
      }).length;
    };
    const click = async (element, double = false) => {
      const urls = [];
      const original = window.open;
      window.open = (url, ...rest) => {
        if (url) urls.push(new URL(url, location.href).href);
        return null;
      };
      try {
        if (double) element.dispatchEvent(new MouseEvent('dblclick', {bubbles: true, cancelable: true, view: window}));
        else element.click();
        await new Promise(resolve => setTimeout(resolve, 800));
      } finally { window.open = original; }
      return {urls};
    };
    if (action === 'inspect') return {
      documentToken: window.__gerenciadorEdeskDocumentToken ??= crypto.randomUUID(),
      url: location.href, ready: document.readyState === 'complete',
      ajax: !!window.Sys?.WebForms?.PageRequestManager?.getInstance()?.get_isInAsyncPostBack(),
      grid: visible(document.querySelector('#cph1_txtSol')),
      work: visible(document.querySelector('#cph1_BtCom')),
      phases: visible(document.querySelector('#cph1_rpvFasePro')),
      comment: visible(document.querySelector('#popC_ddlTipCom')),
      hours: visible(document.querySelector('#cph1_txtDatTem')),
      text: document.body?.innerText ?? ''
    };
    if (action === 'search') {
      fill('#cph1_txtSol', args.id);
      return await click(one('#cph1_btnLocSol'));
    }
    if (action === 'open-request') {
      const table = one('#ctl00_cph1_hgrSol_ctl00');
      const rows = [...table.querySelectorAll('tr.rgRow,tr.rgAltRow')].filter(row => [...row.querySelectorAll('td')].some(cell => cell.innerText.trim() === args.id));
      if (rows.length !== 1) throw Error('Solicitação ausente ou ambígua. Abra a solicitação correta no E-Desk.');
      return await click(rows[0], true);
    }
    if (action === 'tab') {
      const tabName = value => norm(value).replace(/\s*\(\s*\d+\s*\)\s*$/, '').trim();
      const candidates = [...document.querySelectorAll('li.rtsLI')].filter(element => visible(element) && [...element.querySelectorAll('.rtsTxt')].some(text => tabName(text.innerText) === norm(args.name)));
      if (candidates.length !== 1) throw Error('Aba não localizada: ' + args.name);
      return await click(candidates[0]);
    }
    if (action === 'open-work') {
      const matches = [...document.querySelectorAll('#cph1_gvwTra td[onclick*="btnSelTra"]')].filter(element => visible(element) && element.innerText.trim() === args.id);
      const rows = [...new Set(matches.map(element => element.closest('tr')))];
      if (rows.length !== 1 || !rows[0]) throw Error('Trabalho não localizado pelo número exato.');
      return await click(matches[0]);
    }
    if (action === 'hour-read') return {count: countHours(args.hour), previous: one('#cph1_txtRea').value};
    if (action === 'hour-type') {
      fill('#cph1_ddlTipReg', args.tipo, true);
      return {};
    }
    if (action === 'hour-fill') {
      if (countHours(args.hour) !== args.count) throw Error('A tabela mudou. Confira o E-Desk.');
      const previous = args.previous, current = one('#cph1_txtRea').value;
      if (previous && current && !current.startsWith(previous)) throw Error('O comentário mudou. Envio interrompido para preservar o histórico.');
      const existing = current || previous;
      const description = args.description.replace(new RegExp('^' + args.hour.data.replace(/\//g, '\\/') + '\\s*:\\s*-?\\s*'), '').trim();
      if (!description) throw Error('Descritivo vazio.');
      const comment = existing + (existing && !/[\r\n]$/.test(existing) ? '\n' : '') + args.hour.data + ': - ' + description;
      fill('#cph1_txtDatTem', args.hour.data);
      fill('#cph1_txtHorIni', args.hour.inicio);
      fill('#cph1_txtHorFin', args.hour.fim);
      if (one('#cph1_ddlTipReg').value !== args.tipo) throw Error('Tipo de hora alterado inesperadamente.');
      fill('#cph1_txtRea', comment);
      return {comment};
    }
    if (action === 'save-hour') return await click(one('#cph1_BtAtu'));
    if (action === 'hour-check') return {count: countHours(args.hour), comment: one('#cph1_txtRea').value};
    if (action === 'confirm-long-hour') {
      const dialog = [...document.querySelectorAll('.rwWindow,[role="dialog"]')].find(element => visible(element) && /apontamento de tempo maior que 4 horas/i.test(element.innerText));
      const button = dialog && [...dialog.querySelectorAll('button,input,a')].find(element => visible(element) && /^sim$/i.test((element.innerText || element.value || element.title || '').trim()));
      if (button) await click(button);
      return {};
    }
    if (action === 'phases') {
      const view = one('#cph1_rpvFasePro');
      const names = [...view.querySelectorAll('span[id*="lblGFasNome"]')];
      const starts = [...view.querySelectorAll('input[id*="txtGFasDtIniAj"]')];
      const ends = [...view.querySelectorAll('input[id*="txtGFasDtTerAju"]')];
      if (names.length !== starts.length || names.length !== ends.length) throw Error('Estrutura das fases diferente da esperada.');
      const matches = args.phases.map(phase => {
        const indexes = names.map((name, index) => phaseKey(name.innerText) === phaseKey(phase.nome) ? index : -1).filter(index => index >= 0);
        if (indexes.length !== 1) throw Error('Fase ausente ou ambígua: ' + phase.nome);
        const index = indexes[0];
        if (starts[index].disabled || starts[index].readOnly || ends[index].disabled || ends[index].readOnly) throw Error('Fase bloqueada.');
        return {phase, index};
      });
      if (new Set(matches.map(match => match.index)).size !== matches.length) throw Error('Fases repetidas.');
      if (args.fill) for (const {phase, index} of matches) {
        fill('#' + CSS.escape(starts[index].id), phase.dataInicial);
        fill('#' + CSS.escape(ends[index].id), phase.dataFinal);
      }
      return {values: matches.map(({index}) => [starts[index].value, ends[index].value])};
    }
    if (action === 'save-phases') {
      const buttons = [...one('#cph1_rpvFasePro').querySelectorAll('input,button,a')].filter(element => visible(element) && norm(element.innerText || element.value || element.title) === 'salvar');
      if (buttons.length !== 1) throw Error('Botão Salvar das fases ausente ou ambíguo.');
      return await click(buttons[0]);
    }
    if (action === 'open-comment') return await click(one('#cph1_BtCom'));
    if (action === 'comment-type') {fill('#popC_ddlTipCom', args.tipo, true); return {};}
    if (action === 'comment-fill') {
      const template = document.createElement('template');
      if (args.text.startsWith('[[EDESK_HTML]]')) template.innerHTML = args.text.slice(14);
      else {
        const paragraph = document.createElement('div'); paragraph.textContent = args.text;
        template.content.append(paragraph);
      }
      const allowed = new Set(['DIV','P','BR','SPAN','B','STRONG','I','EM','U','S','UL','OL','LI','TABLE','TBODY','THEAD','TR','TD','TH','IMG','H1','H2','H3','BLOCKQUOTE']);
      for (const element of [...template.content.querySelectorAll('*')]) {
        if (!allowed.has(element.tagName)) throw Error('Formato do comentário não permitido: ' + element.tagName);
        for (const attribute of [...element.attributes]) {
          if (!['style','src','alt','width','height','colspan','rowspan'].includes(attribute.name)) element.removeAttribute(attribute.name);
        }
        if (element.tagName === 'IMG' && !/^data:image\/(png|jpeg|gif|webp);base64,[a-z0-9+/=\s]+$/i.test(element.getAttribute('src') ?? '')) throw Error('Imagem não permitida.');
        if (element.hasAttribute('style')) {
          const safeStyles = ['color','background-color','font-size','font-family','font-weight','font-style','text-decoration','text-align','white-space','border','border-collapse','padding','width','max-width','height'];
          const style = safeStyles.map(property => [property, element.style.getPropertyValue(property)]).filter(([,value]) => value && !/url\s*\(|expression|@import/i.test(value)).map(([property,value]) => property + ':' + value).join(';');
          element.setAttribute('style', style);
        }
      }
      if (args.image && !template.content.querySelector('img')) {
        if (!/^[a-z0-9+/=\s]+$/i.test(args.image)) throw Error('Imagem inválida.');
        const image = document.createElement('img'); image.src = 'data:image/png;base64,' + args.image; template.content.append(image);
      }
      const editor = window.$find?.('ctl00_popC_rdeCom');
      if (!editor || typeof editor.set_html !== 'function') throw Error('Editor Telerik não disponível.');
      editor.set_html(template.innerHTML);
      const hidden = document.querySelector('#ctl00_popC_rdeCom_ClientState');
      if (hidden) editor.saveContent?.();
      return {text: template.content.textContent.trim(), hasImage: !!template.content.querySelector('img')};
    }
    if (action === 'save-comment') return await click(one('#popC_BtAtu'));
    if (action === 'comment-evidence') {
      const text = args.text.replace(/\s+/g, ' ').trim();
      if (!text) return {count: 0};
      // Never treat an open editor, input or textarea as a saved comment.
      const copy = document.body.cloneNode(true);
      for (const element of copy.querySelectorAll('textarea,input,iframe,script,style,[contenteditable],#ctl00_popC_rdeCom')) element.remove();
      const rendered = copy.textContent.replace(/\s+/g, ' ').trim();
      return {count: rendered.split(text).length - 1};
    }
    throw Error('Comando desconhecido.');
  } catch (error) { return {error: error.message}; }
}
