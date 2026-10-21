"""Build the small hours-reconciliation-36 update for an existing full installation."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
FILES = (
    'edesk_bot/edesk_horas.py',
    'edesk_bot/hour_receipt.py',
    'local_edesk/journal.py',
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
    'local_edesk/backup_policy.py',
    'scripts/start_full_integration.ps1',
)
README = '''ATUALIZAÇÃO hours-reconciliation-36 — instalação completa já existente

Este arquivo não é uma instalação nova. Use a pasta que já contém
Iniciar integração E-Desk.cmd, python e os demais arquivos da integração.

1. Aguarde qualquer envio terminar.
2. Execute Parar integração E-Desk.cmd na instalação existente.
3. Extraia TODO o conteúdo deste ZIP nessa mesma pasta, substituindo
   os arquivos. Mantenha as subpastas edesk_bot, cloud_run e scripts.
   Não apague .edesk-local, python nem outros arquivos existentes.
4. Execute Iniciar integração E-Desk.cmd e atualize o app com Ctrl + F5.

Novidade v36: confere as horas na tabela do retroativo depois de recarregar.
Ignora horas existentes e tenta novamente, uma unica vez, somente ausencias
comprovadas apos um salvamento concluido ou uma tentativa sem POST.
Se a resposta do POST ficar incerta, nao repete automaticamente.
Retorna sucesso quando todas as horas selecionadas estiverem confirmadas.
Preserva o historico sem acrescentar novamente a descricao na nova tentativa.

Correção v35: recupera uma tentativa de movimentação interrompida quando
o destino ainda está vazio. Ao selecionar a pasta inteira em vez de Documentos,
prepara um novo plano para conferência. Nunca sobrescreve destino com arquivos
nem move automaticamente ao conferir. Preserva os ajustes de abas da v34.

Novidade v34: lista os nomes de abas existentes no Excel e permite que
o editor utilize as abas de entrada e checklist escolhidas por projeto.
Valida a estrutura, a revisao e as celulas permitidas antes de gravar.
A configuracao nao renomeia abas nem executa macros. Mantem os backups
e a previa com as abas selecionadas. Use o botao Abas no editor web.

Correcao v33: reimporta novas autorizacoes de instalacoes anteriores, mesmo
quando a migracao inicial ja havia ocorrido. Guarda copia local dos vinculos
autorizados, fora da pasta extraida, e recupera quando o banco principal
precisa ser recriado. Preserva os vinculos por usuario e pelo caminho exato.
Nao autoriza caminhos novos apenas pelo texto enviado pelo navegador.

Novidade v32: confere arquivos, subpastas, tamanhos e identidade da pasta.
Mostra a quantidade e exemplos de arquivos antes de confirmar. Bloqueia
pasta vazia e nao confirma sucesso se a origem continuar existindo.
Permite substituir somente a pasta de mesmo nome comprovadamente vazia no
destino, mediante conferencia e confirmacao. Nunca copia o projeto.

Novidade v31: mantem os 5 backups mais recentes de cada planilha apos salvar.
Depois de mover e conferir a pasta finalizada, exclui os backups automaticos
dentro dela. Preserva arquivos nao reconhecidos e avisa se a limpeza falhar.
Mantem uma pagina independente antes de salvar comentario com porcentagem,
para continuar ao trabalho mesmo quando o E-Desk fecha as janelas anteriores.
Verifica a porcentagem apos recarregar; nunca repete o comentario.

Correcao v30: Autorizar vinculos neste PC recupera registros antigos que
apontavam para outro caminho, mediante selecao do caminho exato. A conferencia
identifica pasta vinculada, pasta inteira, destino ou planilha com conflito.
Nao altera outros vinculos/usuarios e nao move antes da confirmacao.

Correcao v29: repassa a identidade validada do Firebase para a previa do
checklist, corrigindo a recusa da propria conta autorizada. A restricao a
conta piloto permanece ativa; nao aceita identidade informada pelo cliente.

Novidade v28: previa da porcentagem no checklist, calculada pelo Excel em
copia temporaria com as alteracoes pendentes, sem salvar no original.
Enterprise usa Dados!AG5:AL11; Maker usa sua propria aba calculada.
A previa nao envia ao E-Desk nem salva a copia no sistema.

Novidade v27: permite mover a pasta principal imediatamente acima de Documentos,
mantendo o vinculo da subpasta e da planilha dentro do novo local. Exige selecao
e autorizacao da pasta principal, conferencia e confirmacao no app. Recusa
pastas gerais e preserva a recuperacao das movimentacoes anteriores.

Novidade v26: permite autorizar os vinculos neste PC diretamente na janela
de movimentacao. Solicita os caminhos exatos ausentes; nao abre arquivos
nem move a pasta antes da conferencia e confirmacao.

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
    target = ROOT / 'web/downloads/atualizacao-conferencia-horas-36.zip'
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
