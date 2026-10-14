# Melhorias de uso e manutenção

## Envios

O menu do perfil contém Histórico de envios ao E-Desk. Operações novas guardam
tipo, solicitações, quantidade de horas e resultado; senhas e conteúdos não são
copiados. Metadados sincronizados ficam em `users/{uid}/edesk_operations` e entram
no backup. A tela consulta até 200 operações recentes e também a cópia local.
O histórico anterior de proteção contra reenvios continua independente e intacto.
Resultados pendentes ou incertos exigem conferência no E-Desk; a tela não reenvia.

## Recuperação

Textos de e-mails e comentários são recuperáveis por conta/projeto/modelo no mesmo
dispositivo durante 30 dias. Comentários preservam formatação, percentual e vínculo
com um comentário salvo quando houver. Imagens e anexos devem ser selecionados
novamente; não são copiados para o armazenamento local. Recuperar não envia nem
reinicia o prazo de atualização de 14 dias. A cópia local não substitui o botão
Salvar na conta e não entra no backup. Um rascunho de e-mail mais recente na conta
tem preferência sobre uma cópia local mais antiga.

## Filtros e horas

Dashboard guarda serviço, datas, agrupamento, prioridade e seleção de ativos por
conta/dispositivo. Tarefas guarda o filtro e o período. Limpar filtros restaura os
padrões. Duração explícita em minutos tem prioridade, seguida de duração formatada,
horas decimais e, por último, intervalo válido de horários. Valores inválidos não
viram horas e pausas não são inferidas pela janela de início/fim.

Tarefas usa consultas de data para Hoje, Esta semana e Período, preservando no
cache as horas fora da janela. Sair da tela ou escolher Todas restaura consultas
completas. A primeira leitura é completa para detectar formatos antigos; projetos
com datas legadas mantêm consultas completas. Retornos ao dashboard mantêm
assinaturas inalteradas. Falha ao consultar projetos finalizados conserva os IDs
conhecidos em vez de apagar suas horas do cache. O diagnóstico
`lastSubscriptionChanges` registra quantas consultas precisaram ser recriadas.
Não foi feito benchmark contra a conta real do usuário.

## Limpeza da pasta

Removidos: compilação Windows, temporários Git `tmp_obj_*` identificados como lixo,
cache Windows e dependências temporárias de revisão de vídeo. Histórico Git válido,
Python, ambientes usados pela integração, perfis de sessão e backups são preservados.
Instaladores idênticos/antigos foram substituídos por redirecionamentos para os
pacotes atuais, preservando links anteriores. Não são mais incluídos em futuros
versionamentos os runtimes locais, perfis privados e ZIPs gerados.

Regras novas foram separadas em módulos de duração, período, recuperação, estado
local, mensagens de recuperação e histórico, para reduzir a concentração de regras
nas telas grandes. A decomposição futura dos demais componentes deve ser gradual.

## Histórico com sincronização pendente e atualização web

Novos registros de operações ficam também em uma fila local por conta. A fila
é sincronizada ao entrar no app e a cada 30 segundos enquanto ele estiver aberto.
Falhas conservam a fila para a próxima tentativa ou reabertura. A sincronização
grava somente metadados em `users/<uid>/edesk_operations`; nunca chama as rotas de
envio de horas, comentários ou fases. Transações impedem que uma escrita atrasada
substitua uma confirmação. A tela de histórico mostra a quantidade pendente.
Limpar os dados do navegador elimina as cópias locais ainda não sincronizadas.

Para compilar futuras publicações, usar `scripts/build_web_release.ps1`. O script
gera um identificador único incorporado ao aplicativo e grava o mesmo valor em
`build/web/web-release.json` após a compilação bem-sucedida. Publicar os dois na
mesma versão de Hosting. O manifesto é gerado após a criação do service worker
para permanecer fora do cache offline; o loader também usa uma URL com consulta
para evitar que o worker antigo devolva um bootstrap desatualizado.

O app consulta o manifesto a cada cinco minutos, enquanto o usuário está conectado.
Não mostra o aviso durante um envio nem enquanto outro modal estiver aberto;
revalida essas condições depois da consulta. Atualizar exige um clique do usuário.
“Depois” silencia aquela versão até reabrir o app. Textos recuperáveis continuam no
armazenamento local; anexos precisam ser selecionados novamente e alterações de
outros formulários devem ser salvas antes da atualização. Não há recarga automática.

## Dados da planilha nos e-mails

Na importação da aba Informações de entrada, “Início do projeto pela Consultoria”
preenche Data de recebimento e “Encerramento do projeto” preenche Data de finalização.
Datas nativas do Excel são exibidas como DD/MM/AAAA. “Materiais da Implantação” e
“Sistema do cliente” preenchem o link dos materiais e a liberação no Portal.
Produtos adquiridos recebe o print da proposta, colado com Ctrl+V no campo ou
selecionado como imagem PNG/JPG. Não importa a lista de produtos marcados Sim.
O print é normalizado para PNG, limitado a 512 KB e salvo no próprio rascunho do
projeto, com recuperação local e inclusão no backup dos rascunhos salvos.
O arquivo .eml usa multipart/related com Content-ID para mostrar a imagem no corpo,
na posição indicada por [Print dos produtos adquiridos]; anexos comuns continuam
separados. Copiar texto não copia a imagem; usar Gerar rascunho para Outlook.
Campos vazios ou espaços
reservados do modelo (#...#) não substituem valores já preenchidos no e-mail;
fragmentos legítimos de URL, como #arquivos, são preservados.
Os destinatários continuam sujeitos à revisão e o fluxo de gerar/salvar não envia e-mails.

No encerramento interno, o campo Resumo da implantação também é incluído na mensagem,
mesmo quando o modelo salvo não contém {resumo} ou o corpo foi editado manualmente.
Quando a seção não existe, ela entra antes da assinatura; edições do campo atualizam
o resumo inserido sem duplicar a seção nem alterar o restante da mensagem.
