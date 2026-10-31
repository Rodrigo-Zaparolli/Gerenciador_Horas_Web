"""Safe, actionable local file diagnostics shared by both HTTP servers."""
import logging
import uuid


def file_failure(error, action=''):
    if isinstance(error, PermissionError):
        return {'message': str(error), 'errorCode': 'file_permission'}, 403
    if isinstance(error, FileNotFoundError):
        return {'message': 'O arquivo ou pasta mudou de lugar. Confira o caminho do original no editor.',
                'errorCode': 'file_missing'}, 400
    if isinstance(error, ValueError):
        message = str(error)
        code = getattr(error, 'code', None) or (
            'excel_busy' if 'aguarde a leitura ou grava' in message.lower() else 'invalid_request')
        return {'message': message, 'errorCode': code}, 400
    diagnostic = uuid.uuid4().hex[:12]
    # Never log raw exceptions, paths, request bodies or credentials.
    logging.getLogger(__name__).error('local_operation_failed id=%s type=%s',
                                     diagnostic, type(error).__name__)
    excel = action.startswith('excel-editor-') or action == 'preview'
    message = ('A operacao na planilha falhou. Confira se o Excel responde e tente novamente. '
               'Nao altere o vinculo apenas por esta mensagem.' if excel else
               'Nao foi possivel executar a operacao no arquivo. Confira as permissoes no Windows.')
    return {'message': f'{message} Diagnostico: {diagnostic}.',
            'errorCode': 'excel_operation_failed' if excel else 'local_operation_failed',
            'diagnosticId': diagnostic}, 500
