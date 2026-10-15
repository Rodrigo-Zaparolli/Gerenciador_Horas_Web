"""Resolve one original work-selection control, without guessing a postback ID."""

CONTROL = '[onclick*="btnSelTra"],a[href*="btnSelTra"]'


def resolve_work_selection(table, work_id):
    result = table.evaluate(r'''(table, args) => {
      const norm = text => String(text || '').normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();
      const rows = [...table.querySelectorAll('tr')].filter(row => row.closest('table') === table);
      const headers = rows.find(row => row.querySelector('th'));
      const labels = headers ? [...headers.children].map(cell => norm(cell.innerText)) : [];
      const idColumn = labels.findIndex(text => /^(?:id|n[º°o.]?|numero)(?: (?:do )?trabalho)?$/.test(text));
      const matches = [];
      for (const row of rows) {
        const controls = [...row.querySelectorAll(args.selector)];
        if (!controls.length) continue;
        const cells = [...row.children].filter(cell => cell.tagName === 'TD');
        if (!cells.length) continue;
        const exact = controls.filter(control => norm(control.innerText || control.value) === args.id);
        let match = idColumn < 0 && exact.length > 0;
        if (idColumn >= 0 || !match) {
          // A number can be plain text while the original selection link is in
          // a separate cell. Prefer the labeled ID column; otherwise only the
          // first numeric cell, never a duration/weight elsewhere in the row.
          const idCell = idColumn >= 0 ? cells[idColumn] : cells.find(cell => /^\d+$/.test(norm(cell.innerText)));
          match = !!idCell && norm(idCell.innerText) === args.id;
        }
        if (match) matches.push({row: [...table.querySelectorAll('tr')].indexOf(row),
          control: controls.indexOf(exact[0] || controls[0])});
      }
      return matches;
    }''', {'selector': CONTROL, 'id': str(work_id).strip()})
    if len(result) > 1:
        raise RuntimeError('Mais de um trabalho possui o número solicitado. Confira a solicitação antes de enviar.')
    if not result:
        return None
    match = result[0]
    return table.locator('tr').nth(match['row']).locator(CONTROL).nth(match['control'])
