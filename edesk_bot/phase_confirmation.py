"""Verify phase values from a fresh page; never infer success from a click."""
import unicodedata

def phase_key(value):
    return ''.join(c for c in unicodedata.normalize('NFKD', str(value)).lower()
                   if c.isalnum())

def mismatched_phases(expected, actual):
    errors = []
    for phase in expected:
        if not phase.get('dataInicial') and not phase.get('dataFinal'):
            continue
        matches = [row for row in actual if phase_key(row['nome']) == phase_key(phase['nome'])]
        if len(matches) != 1:
            errors.append(f"Não foi possível reler a fase {phase['nome']} com segurança.")
            continue
        for field in ('dataInicial', 'dataFinal'):
            if phase.get(field) and matches[0].get(field, '').strip() != phase[field].strip():
                errors.append(f"A data {field} da fase {phase['nome']} não foi persistida.")
    return errors

async def read_phase_rows(page):
    view = page.locator('#cph1_rpvFasePro')
    names = view.locator("span[id*='lblGFasNome']")
    starts = view.locator("input[id*='txtGFasDtIniAj']")
    ends = view.locator("input[id*='txtGFasDtTerAju']")
    rows = []
    count = await names.count()
    if count != await starts.count() or count != await ends.count():
        raise ValueError('A estrutura das fases mudou; não foi possível confirmar o salvamento.')
    for i in range(count):
        rows.append({'nome': (await names.nth(i).inner_text()).strip(),
                     'dataInicial': await starts.nth(i).input_value(),
                     'dataFinal': await ends.nth(i).input_value()})
    return rows

async def close_new_duplicate_requests(context, selected, original_pages):
    for candidate in list(context.pages):
        if candidate == selected or candidate in original_pages or candidate.is_closed():
            continue
        if '/Portal/Solicitacao.aspx' in candidate.url and candidate.url == selected.url:
            await candidate.close()
