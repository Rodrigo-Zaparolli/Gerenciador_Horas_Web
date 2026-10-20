"""Build the small professional-checklist-25 update for an existing full installation."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
FILES = (
    'edesk_bot/edesk_horas.py',
    'edesk_bot/work_selection.py',
    'edesk_bot/edesk_comentario.py',
    'edesk_bot/edesk_percentual.py',
    'edesk_bot/comment_percentage.py',
    'scripts/stop_edesk_local.ps1',
    'cloud_run/main.py',
    'local_edesk/local_files.py',
    'local_edesk/files_server.py',
    'local_edesk/excel_editor.py',
    'local_edesk/project_archive.py',
    'scripts/start_full_integration.ps1',
)
README = '''ATUALIZAÇÃO professional-checklist-25 — instalação completa já existente

Este arquivo não é uma instalação nova. Use a pasta que já contém
Iniciar integração E-Desk.cmd, python e os demais arquivos da integração.

1. Aguarde qualquer envio terminar.
2. Execute Parar integração E-Desk.cmd na instalação existente.
3. Extraia TODO o conteúdo deste ZIP nessa mesma pasta, substituindo
   os arquivos. Mantenha as subpastas edesk_bot, cloud_run e scripts.
   Não apague .edesk-local, python nem outros arquivos existentes.
4. Execute Iniciar integração E-Desk.cmd e atualize o app com Ctrl + F5.

Novidade v25: Enterprise usa Checklist-Processo; Professional utiliza
Maker CheckList-Processo. Identifica a tabela de cada modelo, incluindo as
primeiras tarefas Maker. Preserva backups e macros.

Novidade v24: configuração individual da pasta padrão no menu do perfil.
A leitura da árvore agora distingue marcadores Cloud Files do OneDrive de
links/junções e recusa subpastas que não puderem ser conferidas. Mantém os
registros de movimentação anteriores e a confirmação antes de mover.

Novidade v23: movimentação conferida da pasta de projetos finalizados, na
mesma unidade/disco, com atualização dos vínculos da pasta e da planilha.
Possui recuperação após interrupção; não move novamente uma operação já
concluída. A ação é confirmada no app e exclusiva para a conta piloto.

Correção v22: abre planilhas com datas armazenadas como texto ou instruções
do modelo sem o erro could not convert string to float. Não altera esses
valores automaticamente. Inclui o ajuste de exibição do envelope no site.

Inclui a correção v21: a integração usa a mesma regra de conta da interface, sem exigir
a marcação adicional email_verified. O token Firebase continua sendo validado,
e contas diferentes de rodrigozaparolli79@gmail.com continuam bloqueadas.

Inclui a versão v20: editor piloto das abas Informações de entrada e Checklist-Processo.
Restrito à conta autenticada rodrigozaparolli79@gmail.com, com identidade validada pelo Firebase.
Exige Microsoft Excel instalado. Grava apenas campos permitidos, cria backup
e bloqueia alterações baseadas numa leitura antiga. Preserva o VBA original.
Não executa macros de atualização do modelo automaticamente.

Inclui a correção v19: a janela do comentário pode fechar após a resposta de Salvar.
O processo reconhece esse fechamento, não repete o comentário e continua
para a solicitação, o trabalho escolhido e a porcentagem, verificando o valor.

Inclui a correção v18: aguarda a tela inicial e o Ajax terminarem antes de selecionar
o trabalho da primeira hora. Ignora controles ocultos/desabilitados e usa
o clique normal no controle disponível. Não repete o salvamento de horas.

Inclui a correção v17: reconhece o botão Salvar real do trabalho, confirma o valor
após reabrir e devolve confirmações separadas do comentário e da porcentagem.
O app informa quando somente a porcentagem ficou pendente, sem pedir para
repetir um comentário já publicado. Inclui Enviar só %, sem publicar comentário.

Inclui a correção dos vínculos: recuperar pastas e planilhas já autorizadas pelo
caminho completo, sem confundir projetos com pastas de mesmo nome.
Vínculos antigos são atualizados com o caminho completo ao abrir pelo app.
Os vínculos ficam no perfil do Windows e não na pasta extraída.

Inclui a correção anterior das horas: se o E-Desk voltar à solicitação,
o trabalho e o retroativo são reabertos antes do próximo apontamento.
A ação Salvar de uma hora anterior não é repetida.
'''


def main():
    target = ROOT / 'web/downloads/atualizacao-planilha-professional-25.zip'
    target.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(target, 'w', ZIP_DEFLATED) as archive:
        for name in FILES:
            archive.write(ROOT / name, name)
        archive.writestr('LEIA-ME-ATUALIZACAO.txt', README.encode('utf-8-sig'))
    with ZipFile(target) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist()) == {*FILES, 'LEIA-ME-ATUALIZACAO.txt'}
        for name in FILES:
            assert archive.read(name) == (ROOT / name).read_bytes()
    print(f'{target.name}: {target.stat().st_size} bytes; all source files verified')


if __name__ == '__main__':
    main()
