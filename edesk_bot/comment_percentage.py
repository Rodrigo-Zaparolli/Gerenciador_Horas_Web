"""Update only the work's %Realizado, standalone or after a saved comment."""
from decimal import Decimal, InvalidOperation
from urllib.parse import parse_qs


def parse_percentage(value):
    if value is None or isinstance(value, str) and not value.strip():
        return None
    if isinstance(value, bool):
        raise ValueError('Informe um percentual entre 0 e 100.')
    try:
        number = Decimal(str(value).strip().replace(',', '.'))
    except InvalidOperation:
        raise ValueError('Informe um percentual entre 0 e 100.') from None
    if not number.is_finite() or not 0 <= number <= 100:
        raise ValueError('Informe um percentual entre 0 e 100.')
    if number != number.quantize(Decimal('0.01')):
        raise ValueError('Use no máximo duas casas decimais no percentual.')
    return number


FIND_FIELD = r"""() => {
  const visible = e => e && e.getClientRects().length && getComputedStyle(e).visibility !== 'hidden';
  const norm = s => s.replace(/\s+/g, '').toLowerCase().replace(/:$/, '');
  const candidates = new Set();
  for (const label of document.querySelectorAll('label,td,span')) {
    if (!visible(label) || norm(label.textContent) !== '%realizado') continue;
    const linked = label.getAttribute('for');
    if (linked) candidates.add(document.getElementById(linked));
    const cell = label.closest('td');
    if (cell?.nextElementSibling) {
      for (const input of cell.nextElementSibling.querySelectorAll('input')) candidates.add(input);
    }
    if (label.parentElement && !['BODY','HTML','TR','TABLE'].includes(label.parentElement.tagName)) {
      for (const input of label.parentElement.querySelectorAll('input')) candidates.add(input);
    }
  }
  const inputs = [...candidates].filter(e => visible(e) && e.tagName === 'INPUT' && e.type !== 'hidden');
  if (inputs.length !== 1 || inputs[0].disabled || inputs[0].readOnly) throw Error('Campo %Realizado ausente, bloqueado ou ambiguo.');
  inputs[0].setAttribute('data-gerenciador-percentual', 'realizado');
  return inputs[0].value;
}"""


def percentage_field(page):
    page.evaluate(FIND_FIELD)
    return page.locator('[data-gerenciador-percentual="realizado"]')


def save_button(page):
    button = page.locator('#cph1_BtAtu')
    if button.count() != 1:
        button = page.get_by_role('button', name='Salvar', exact=True)
    if button.count() != 1 or not button.is_visible() or not button.is_enabled():
        raise RuntimeError('Botão Salvar do trabalho ausente, bloqueado ou ambíguo.')
    return button


def check_target(page, solicitation, work):
    from edesk_horas import validar_tela_trabalho
    if not validar_tela_trabalho(page, solicitation, work):
        raise RuntimeError('A tela aberta não corresponde ao trabalho do percentual.')


def preflight_percentage(page, solicitation, work):
    check_target(page, solicitation, work)
    percentage_field(page)
    save_button(page)


def save_work_percentage(page, solicitation, work, value):
    target = parse_percentage(value)
    if target is None:
        return
    preflight_percentage(page, solicitation, work)
    work_url = page.url
    field = percentage_field(page)
    field.fill(format(target, '.2f').replace('.', ','))
    field.press('Tab')

    def is_save_response(response):
        request = response.request
        if request.method != 'POST':
            return False
        data = parse_qs(request.post_data or '', keep_blank_values=True)
        return any('BtAtu' in key for key in data) or any(
            'BtAtu' in value for value in data.get('__EVENTTARGET', []))

    with page.expect_response(is_save_response, timeout=30000) as pending:
        save_button(page).click(timeout=15000)
    response = pending.value
    if not response.ok or '|error|' in response.text().lower():
        raise RuntimeError('O E-Desk recusou o salvamento do percentual.')
    page.wait_for_timeout(1000)
    # Navigate with GET: reloading a POST response can submit Salvar again.
    page.goto(work_url, wait_until='domcontentloaded', timeout=30000)
    check_target(page, solicitation, work)
    field = percentage_field(page)
    if parse_percentage(field.input_value()) != target:
        raise RuntimeError('O percentual não foi confirmado após recarregar o trabalho.')


def save_comment_then_percentage(save_comment, save_percentage):
    save_comment()
    try:
        save_percentage()
    except Exception as error:
        raise RuntimeError(
            'EDESK_PERCENTAGE_PENDING: O comentário recebeu resposta de salvamento, '
            'mas o percentual não foi confirmado. Confira o E-Desk antes de reenviar.'
        ) from error


def update_percentage_after_comment(page, context, request_url, solicitation, work, value):
    """Return to the request, explicitly select Works and save only the percentage."""
    if parse_percentage(value) is None:
        return
    from edesk_horas import abrir_trabalho_na_solicitacao, eh_solicitacao
    if not eh_solicitacao(request_url):
        raise RuntimeError('URL da solicita\u00e7\u00e3o inv\u00e1lida para atualizar o percentual.')
    if page.is_closed():
        page = context.new_page()
    page.goto(request_url, wait_until='domcontentloaded', timeout=30000)
    page.bring_to_front()
    work_page = abrir_trabalho_na_solicitacao(page, context, solicitation, work)
    if work_page is None:
        raise RuntimeError('O trabalho do percentual n\u00e3o foi localizado na solicita\u00e7\u00e3o.')
    save_work_percentage(work_page, solicitation, work, value)
