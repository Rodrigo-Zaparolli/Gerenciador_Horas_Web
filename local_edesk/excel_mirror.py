import re
import threading
from edesk_bot.excel_preview import interpretar_referencia, renderizar_intervalo_excel

render_lock = threading.Lock()


def render(path, reference):
    sheet, address = interpretar_referencia(reference)
    def index(value):
        match = re.fullmatch(r'([A-Z]+)([1-9]\d*)', value)
        if not match:
            raise ValueError('Intervalo inválido. Use Aba!A1:L8.')
        column = 0
        for letter in match[1]:
            column = column * 26 + ord(letter) - 64
        row = int(match[2])
        if column > 16384 or row > 1048576:
            raise ValueError('Intervalo fora dos limites do Excel.')
        return row, column
    first, last = [index(cell) for cell in address.split(':')]
    rows, columns = last[0] - first[0] + 1, last[1] - first[1] + 1
    if rows <= 0 or columns <= 0 or rows > 40 or columns > 20 or rows * columns > 600:
        raise ValueError('Escolha um intervalo de até 40 linhas, 20 colunas e 600 células.')
    if path.suffix.lower() not in {'.xlsx', '.xlsm', '.xls'}:
        raise ValueError('Vincule uma planilha Excel ao trabalho.')
    if not render_lock.acquire(blocking=False):
        raise ValueError('Aguarde a prévia do Excel em andamento.')
    try:
        image, actual_sheet = renderizar_intervalo_excel(path, sheet, address)
        return {'imagemBase64': image, 'sheet': actual_sheet, 'renderer': 'excel'}
    except RuntimeError as error:
        raise ValueError(str(error)) from error
    except Exception as error:
        raise ValueError('Não foi possível espelhar a planilha. Confirme que o Microsoft Excel está instalado e que a aba e o intervalo existem no arquivo vinculado.') from error
    finally:
        render_lock.release()
