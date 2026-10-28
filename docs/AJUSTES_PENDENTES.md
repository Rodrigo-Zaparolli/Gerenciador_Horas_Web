# Controle de publicação dos ajustes

Por instrução do usuário em 23/10/2026, reunir os próximos ajustes e publicar somente no horário que ele definir. Não executar deploy nem enviar as alterações para publicação automaticamente.

Exceção autorizada em 23/10/2026: o usuário pediu “esse pode publicar” para o seletor de percentuais e o filtro de pendentes descritos abaixo. A autorização vale para este ajuste; os próximos continuam aguardando autorização ou horário definido.

## Publicado em 23/10/2026 — modal de percentuais do Checklist-Processo

- Seleção de 0%, 25%, 50%, 75% e 100% com o símbolo visível em cada opção.
- Opção Somente pendentes, ocultando tarefas concluídas em 100%.
- O filtro considera os ajustes do modal e preserva os valores das tarefas que ficam ocultas.
- Cancelar descarta o rascunho; Aplicar ajustes devolve os valores ao editor. Salvar na planilha continua sendo a gravação explícita no Excel.
- Valores anteriores fora das opções usuais continuam preservados sem arredondamento silencioso.

As notas desse ajuste acompanharam a publicação. As notas atuais descrevem a correção v46 abaixo.

Validação: 27 testes passaram (modal, editor da planilha e prévia); análise dos três arquivos alterados sem problemas. Publicação autorizada pelo usuário, compilada e conferida no site. Release web: `6d8b0b21fdba4f859675a6343791d43c`. A integração local permanece na v45. Os próximos ajustes continuam sujeitos à autorização ou ao horário definido pelo usuário.

## Publicado em 23/10/2026 — recuperação de vínculos antigos (v46)

Diagnóstico do outro PC: banco principal e recuperação com os mesmos 57 registros, chave local presente, integração v45 ativa. Consulta somente de leitura na conta identificada encontrou quatro projetos ativos com referências antigas contendo só o nome. Não houve alteração remota de dados.

A recuperação consulta somente caminhos previamente autorizados para o mesmo UID e tipo, com o número exato do projeto em uma pasta do caminho e o nome esperado do recurso. Precisa haver um único caminho possível. Referências com caminho completo não são redirecionadas. Não associa apenas pelo nome Documentos, não usa prefixos parciais de IDs e não concede acesso a caminhos novos. O resultado é persistido como referência assinada com caminho completo e migrado no projeto pelo fluxo transacional já existente.

O cliente e a ponte local passam o ID do projeto na abertura, leitura e edição. Vínculos antigos exigem a capacidade da integração v46; vínculos completos continuam compatíveis. A ponte recebe URL versionada para evitar cache antigo que omita o ID.

Autorização específica recebida: “Publicar esta correção agora”. Os ajustes seguintes continuam aguardando autorização ou horário definido.

Validação: 39 testes Python, 16 testes Flutter, contrato da ponte JavaScript, análise sem problemas, pacote completo validado e build web concluído. Release web `3c4c94822ba141609e723c52424b833c` publicada e conferida publicamente, incluindo os downloads leve e completo v46. Histórico reduzido às duas publicações mais recentes. A validação no PC real do usuário ainda depende da aplicação da atualização local.

## Publicado em 23/10/2026 - lote completo v47

Autorizacao expressa do usuario: "pode publicar todos os ajustes". Todos os ajustes preparados nesta sessao foram reunidos nesta publicacao. Alteracoes futuras continuam aguardando autorizacao ou horario definido.

- Inicializadores verificam a capacidade real do processo ativo antes de anunciar sucesso, preservando os vinculos anteriores.
- Modal de tarefas mostra no topo o percentual da etapa calculado pelo Excel. O seletor de cada bloco aplica 0%, 25%, 50%, 75% ou 100% as tarefas editaveis, inclusive ocultas pelo filtro. Edicao individual e cancelamento preservados; a tabela Status Projeto continua mostrando apenas etapas.
- Importacao por ID valida Trabalhos e a tabela de etapas sem aguardar a aba Comentarios.
- Editor oferece Implantacao - Linha do Tempo para datas dos eventos e Todas as guias pelo menu Guias da planilha. A consulta geral navega por paginas de 25 linhas e 8 colunas; permite textos, numeros e datas, revalidando pagina, valores anteriores, revisao e protecoes no backend. Formulas e celulas protegidas permanecem bloqueadas. Gravacao usa copia temporaria, conferencia, preservacao do pacote e backup.
- Espelho mostra a causa real de erros de aba/arquivo/Excel. Quando Professional Checklist-Processo nao existe e Maker Checklist-Processo existe, usa a guia Maker para a referencia antiga, mantendo o intervalo. Uma guia Professional existente sempre tem prioridade.
- Contatos de clientes cadastrados por conta no Firebase: empresa, nome, telefone e e-mail. O botao junto das tarjas permite cadastrar, editar, excluir, pesquisar e inserir no cursor, preservando texto e imagens. Formulario mantido em falha de conexao e identificador estavel para nova tentativa.
- Recursos piloto permanecem restritos as contas ja autorizadas. Nenhuma regra de acesso foi ampliada.

Validacao concluida: 177 testes Python, 45 testes Flutter, analise dos sete arquivos Dart sem problemas, contrato da ponte aprovado e pacote completo extraido validado (runtime, APIs protegidas, horas, comentario/percentual, importacao e selecao de trabalhos em simulacoes).

Excel real: gravacao em planilha sintetica aprovada para texto, data e celula numerica nova, mantendo formula e criando backup. Captura PNG aprovada para guia Maker usando a referencia Professional antiga, sem alterar o arquivo. Nao foi feito envio real ao E-Desk nem cadastro real de contatos durante os testes. O uso no outro PC depende da atualizacao local v47.

Site publicado e conferido publicamente: release `4a26950d4ca14834b5eb65a74af256a2`, Hosting `a17ce755b3a4fa1f`. Pacote leve `atualizacao-integracao-completa-47.zip` com integridade conferida; pacote completo `integracao-edesk-completa-windows-v47.zip` disponivel. Notas incluidas no modal de atualizacao. Historico mantido nas duas publicacoes mais recentes.

## Publicado em 26/10/2026 - recursos liberados a todos os usuarios autenticados (v48)

Solicitacao expressa: "liberar sistema para todos". Removida a lista de e-mails piloto do app e da integracao. Editor e guias da planilha, acompanhamento de plugins, contatos, conferencia e importacao agora exigem uma conta autenticada, sem limitar a Rodrigo/Maiquel. Login, verificacao de token, isolamento por UID no Firestore e autorizacoes de arquivos por usuario permanecem obrigatorios. O destino sugerido especifico de Rodrigo continua somente para ele; outros usuarios configuram seu proprio destino. Nao foi removida a autorizacao de pareamento de computadores centrais.

Validacao: 177 testes Python e 26 testes Flutter aprovados, incluindo conta comum, bloqueio sem login, arquivos e operacoes de outra conta e troca de identidade durante importacao. Analise sem problemas; pacote completo extraido aprovado. Nenhum envio real ao E-Desk foi realizado pelos testes.

Publicacao web conferida: `9a25aa2639c94c6dae94e1ffa6196318`, Hosting `e1fd79a066104166`. Downloads v48 leve/completo conferidos. Integracao `all-users-48` necessaria nos computadores dos usuarios para os recursos nativos; vinculos anteriores preservados. Historico com as duas publicacoes mais recentes. Proximas alteracoes continuam sujeitas a autorizacao de publicacao.

## Publicado em 26/10/2026 - fechamento do modal de tarefas

Removida a espera de pauseAndWait da saida do modal. Fechar/cancelar e Aplicar ajustes encerram a rota imediatamente, invalidam a previa e aceitam somente o primeiro comando de saida. Isso evita que varios cliques pendentes fechem rotas adicionais quando o Excel responde. Requisicoes do editor sao serializadas com verificacao de identidade no despacho; respostas de um modal encerrado nao alteram o rascunho. Validacao: 33 testes aprovados, incluindo previa pendente, repeticao de comandos, aplicacao/cancelamento, tela principal preservada, resposta tardia e ausencia de consultas simultaneas ao Excel. Analise sem problemas. Ajuste somente no site, usando integracao v48. Autorizacao especifica recebida: "Publicar a correcao agora". Publicacao conferida no site: release 34e58f1cbe354564954538cf2c854be7, Hosting 169bcbdd0d826a33. A integracao permanece na v48; nao e necessario baixar novamente o CMD. Historico mantido nas duas publicacoes mais recentes.

## Publicado em 26/10/2026 - abertura imediata da etapa pendente

A abertura da etapa ainda aguardava pauseAndWait da previa principal, deixando o usuario sem acesso enquanto o Excel calculava. Adicionado pause sincrono ao controlador e removida a espera da navegacao de entrada. Consultas ao Excel continuam serializadas. Cada modal tem uma validade local para descartar consultas na fila se ja foi fechado, e uma guarda impede abertura duplicada por cliques rapidos. A saida imediata e o descarte de respostas tardias permanecem. Validacao: 34 testes aprovados, incluindo abertura, edicao, aplicacao, fechamento e reabertura com a primeira consulta Excel bloqueada, sem chamadas simultaneas ou consultas obsoletas executadas. Analise sem problemas. Ajuste somente no site; integracao v48 mantida. Autorizacao especifica recebida: "Publicar a correcao agora". Site publicado e conferido: release 9a7a78636f48446eb134cdf84f24eadb, Hosting 94ea8d22c6d31697. Integracao CMD v48 mantida.

## Publicado em 26/10/2026 - tabela e tarefas lado a lado no Checklist

Em largura util a partir de 1100 px, Status Projeto ocupa a esquerda e a lista de tarefas/filtros uma lateral de 300 px a direita. Removido o limite vertical proporcional que cortava a tabela. Colunas e barras de progresso compactas; lista lateral com rolagem independente. Em largura menor, rolagem vertical do conjunto mantem tabela, filtros e tarefas acessiveis. Altura geral do modal e rodape preservados. Validacao: 36 testes aprovados, incluindo seis linhas e todas as colunas visiveis em notebook 1366x600, temas claro e escuro, rolagem em 390x844 e regressao dos modais de etapas. Ajuste somente web, integracao v48 inalterada. Autorizacao especifica recebida: "Publicar o layout agora". Publicacao conferida no site: release 4008904c79cb4d52b0d8455d388ca36a, Hosting c0a4e84769c6595e. Integracao CMD v48 mantida; historico nas duas publicacoes mais recentes.

## Publicado em 26/10/2026 - Treinamento Catalog na guia Cronogramas (v49)

Arquivo fornecido analisado somente para leitura: guia real Cronogramas, cabecalhos na linha 5, datas B, horarios C:F, total calculado G, status/percentual H, trabalho I, notas J e percentuais calculados K:M. O tipo Treinamento Catalog (inclusive com Consultoria e acentos) passa a usar a guia Cronogramas no leitor geral, sem executar snapshot/validacao do modelo Enterprise. O carregamento da preferencia ocorre com modal visivel e fechavel. Preferencia de guia por UID/projeto em spreadsheet/view-settings; seletor visivel no leitor e opcao Escolher guia no editor do modelo. A preferencia e gravada apos leitura bem-sucedida e sem bloquear a interface.

Leitor geral passa a tratar horarios HH:mm e percentuais de 0 a 100, mantendo valores Excel fracionarios. Cabecalhos de ListObjects, formulas, resultados de matrizes/spill e celulas protegidas nao podem ser editados. A guia Cronogramas exige contrato worksheetTypesVersion=2 para impedir salvamento incorreto por integracao antiga. Fechar durante leituras e permitido; gravacao ainda bloqueia fechamento ate a confirmacao.

Validacao inicial: 26 testes Flutter e 21 testes Python aprovados; analise sem problemas. Em copia local do arquivo enviado, Excel real gravou data, inicio/fim e percentual com backup, conferindo macros e preservacao do arquivo original por SHA256. Cabecalhos protegidos e dados editaveis conferidos no Excel real. Nenhum dado de usuario foi gravado no Firebase pelos testes.

Publicacao autorizada expressamente pelo usuario: "publicar". Integracao v49 preparada, pacotes leve/completo gerados e conferidos. Validacao final: 178 testes Python, 44 testes Flutter, analise sem problemas e pacote completo extraido aprovado. Site compilado e conferido publicamente: release 9f7f6d7b603840cc95d3f6375fae16be, Hosting 86bd1c23c8862557. Downloads atualizacao-integracao-completa-49.zip e integracao-edesk-completa-windows-v49.zip disponiveis; integridade do pacote leve conferida. Historico nas duas publicacoes mais recentes. Recursos anteriores e isolamento por conta preservados. O outro PC precisa atualizar/reiniciar a integracao e recarregar o site.

## Publicado em 26/10/2026 - downloads da integracao no modal de atualizacao

Modal Nova versao disponivel passa a mostrar Integracao E-Desk vN com botoes de atualizacao leve e instalacao completa. O build gera os links e a versao em web-release.json automaticamente a partir do inicializador e do pacote leve real, validando a existencia dos arquivos. O verificador de release confere tambem os links do manifest e sua igualdade no site publico. O cliente aceita somente links relativos da pasta downloads, ZIP e versao correspondente; manifests antigos sem esse objeto continuam funcionando.

Download nao fecha o modal nem dispara reload do app. Falhas mostram mensagem local com possibilidade de tentar novamente. A integracao permanece na v49. Clientes com codigo antigo precisam atualizar o app uma vez para receber a interface nova; os proximos avisos usarao os botoes automaticamente. Sem instalacao ou execucao automatica de ZIP/CMD.

Validacao: 16 testes aprovados incluindo v49, versoes futuras, links invalidos, falha/repeticao, tela pequena, bloqueio de aviso durante envios e reload apenas por acao explicita. Analise sem problemas. Autorizacao especifica recebida: "Publicar agora". Site publicado e conferido: release 69b65380be4741c5982b153d205c95aa, Hosting 358d5211436de9e2. Downloads leve e completo v49 conferidos publicamente. Integracao nativa mantida na v49, sem nova atualizacao CMD por este ajuste. Historico mantido nas duas publicacoes mais recentes. Proximos ajustes exigem autorizacao de publicacao.

## Publicado em 27/10/2026 - tabela do Cronograma (v50)

Usuario aprovou a previa, autorizou implementar e depois autorizou publicar: "pode publicar". Guia Cronogramas usa tabela com Data, Manha inicio/fim, Tarde inicio/fim, Total, Status e Trabalho/Descricao. Demais guias preservadas. Status selecionavel por encontro: 0, 25, 50, 75, 100, Programado e Cancelado, preservando valores existentes como 99. Datas exibidas com ano completo e dia da semana; formulas e protecoes bloqueadas. Previa agrupa por trabalho e pondera Status pela duracao dos encontros. Cancelados nao contribuem; horarios inconsistentes suspendem a previa do trabalho. Salva nas celulas originais com revisao e antes/depois conferidos, sem substituir formulas ou macros.

Leitura nativa reconhece a tabela real e carrega todas as linhas (ate 2000); nao calcula progresso sobre uma pagina parcial. Sem modelo reconhecido, leitor generico anterior permanece. Integracao catalog-table-50 preparada com pacotes leve/completo, preservando banco e chave dos vinculos. Requer atualizar a integracao para a nova tabela.

Validacao: 9 testes Flutter (incluindo edicao em 390 e 1366 px, calculo ponderado, cancelamento, salvamento exato e regressao das guias); 28 testes Python; analise sem problemas. Excel real em copia da planilha Rimo confirmou leitura integral, percentual -> Programado -> percentual, gravacao e backup, formulas e VBA preservados e original sem alteracao. Nenhum envio real ao E-Desk ou gravacao de dados no Firebase. Compilacao e pacotes v50 publicados e conferidos publicamente.

Conferencia adicional encontrou caches antigos nos filhos de formulas de matriz dinamica. A preservacao do pacote agora atualiza tambem os valores calculados dentro das areas de matriz originais, sem alterar formulas, referencias ou celulas externas. Regressao sintetica e Excel real confirmaram H33 = 0,3333333333333333 apos H17 = 0,5. Pacotes v50 refeitos e integridade/conteudo conferidos. Site publicado e conferido: release 07101a4fb4fd4358ad59a617a916d646, Hosting c703c329d8d4430b. Downloads leve e completo v50 conferidos. Integracao deve ser atualizada/reiniciada no PC para usar a nova tabela; Ctrl+F5 no site. Historico mantido nas duas publicacoes mais recentes. Proximos ajustes exigem autorizacao de publicacao.

## Publicado em 27/10/2026 - iniciar integracao sem abrir Conectar E-Desk (v51)

Removida a abertura automatica de integracao-completa.html do inicializador completo. Inicializacao do servico, validacao da integracao e ativacao do inicio automatico preservadas; parametro Background mantido para compatibilidade. Instrucoes do pacote completo atualizadas para acesso manual ao app. Verificacao de sintaxe PowerShell sem executar o inicializador. Publicado com os pacotes v51 apos autorizacao especifica.

## Em investigacao, nao publicado - Cronograma permanece no formato antigo - 27/10/2026

Usuario confirmou integracao v50 instalada e reiniciada. Site publico conferido no release 07101a4fb4fd4358ad59a617a916d646. Causa do caso real ainda nao comprovada: aguardando identificar a guia/projeto e imagem da tela. Corrigido independentemente o retorno silencioso ao leitor generico quando Cronogramas nao e reconhecido: agora bloqueia edicao e explica o problema, sem enviar alteracoes. 11 testes Flutter aprovados, incluindo reconhecimento ausente/falso, campos bloqueados, abertura correta, horarios, percentuais e salvamento exato. Nao publicado. Este bloqueio melhora o diagnostico; nao comprova a solucao da falha no PC do usuario.

## Publicado em 27/10/2026 - modal do projeto conforme previa aprovada (v51)

Print do usuario confirmou divergencia visual: Todas as guias vazio, em vez do modal Planilha do projeto. Cronograma passa a usar cabecalho compartilhado do projeto, identificacao do cliente, guias superiores, rodape fixo e tabela estendida a largura disponivel. Leitura do Cronograma inicia antes da listagem de guias; cabecalho e guia ativa permanecem visiveis durante o carregamento. Outros nomes de guias ficam no menu Escolher guia. Descarte confirmado antes de trocar/fechar, gravacao impede fechar, conta conferida antes/depois das chamadas. Integracao v50 compativel com a apresentacao nova; v51 incorpora tambem o pedido anterior de iniciar sem abrir Conectar E-Desk. Pacotes e compilacao publicados apos autorizacao especifica.

Validacao final do modal: 34 testes aprovados (incluindo captura da interface implementada, carregamento com cabecalho/abas visiveis, abertura direta sem aguardar listagem, recuperacao de leitura, Status/salvamento em 390/1366 px e regressao Enterprise/Professional). Analise sem problemas; web compilada e verificada localmente. Pacotes v51 integro/conteudo conferidos, sem abertura automatica do navegador. Preview real com dados ilustrativos em build/cronograma-modal-corrigido.png. Release preparada 9043d0631ebb4aa1ac1743523b2054e5, sem publicacao.

Publicacao autorizada expressamente: "pode publicar". Site e downloads leve/completo v51 publicados e conferidos: release 9043d0631ebb4aa1ac1743523b2054e5, Hosting 26eb870fa0fed38b. Historico mantido nas duas publicacoes mais recentes. O modal requer recarregar o site; e compativel com v50. O inicio sem abrir Conectar E-Desk requer extrair e reiniciar a v51. Proximos ajustes dependem de autorizacao de publicacao.

## Preparado, nao publicado - nova tentativa de aviso adiado - 27/10/2026

Site publico v51 conferido. O aviso compara a release web instalada com a publicada; nao aparece se o site ja recarregou para a release atual, mesmo que a integracao local precise atualizar. Identificada tambem espera de cinco minutos quando a resposta da consulta chegava durante envio ou outro modal. Corrigido para tentar novamente no proximo intervalo seguro de 30 segundos, inclusive apos falha de rede. Mantido bloqueio durante envios/modais, mesma versao e escolha Depois. Sem recarregamento automatico. 16 testes aprovados e analise sem problemas. Sem build/deploy novo; usuario pode obter a v51 pelos downloads ja publicados.

## Publicado em 27/10/2026 - salvamento dos vinculos no editor do dashboard

Print do projeto Mesaro 2262248 mostrou excelLink ainda apontando para Orquinare. Causa confirmada no codigo do modal da tabela: salvarProjeto era chamado sem ProjectReferenceChanges; a transacao corretamente protegia os caminhos antigos como se nao tivessem sido editados. O formulario de cadastro principal ja enviava esse metadado, mas esse outro editor nao.

Adicionado ProjectLinkEdit: captura os caminhos exibidos ao abrir, edita uma copia completa do projeto e chama saveProject com mudancas explicitas dos vinculos. O modelo da listagem recebe o resultado somente apos confirmacao da gravacao. Alteracoes simultaneas continuam bloqueadas; salvamentos de status/tarefas nao restauram caminhos antigos. Botao de salvar protegido contra repeticao e fechar/cancelar bloqueados durante gravacao. Nenhuma planilha de outro projeto e escolhida automaticamente, nem vinculo real alterado no Firebase durante os testes.

Validacao: 37 testes aprovados, incluindo o proprio modal da tabela, selecao Mesaro sobre referencia antiga Orquinare, gravacao, reabertura, isolamento entre projetos, remocao explicita e conflito concorrente; inclui regressao de recuperacao/atualizacao de vinculos e o aviso de atualizacao adiado. Analise sem problemas. Ajuste apenas web, integracao v51 mantida. O usuario precisara selecionar uma vez o caminho correto que nao chegou a ser persistido antes. Compilacao concluida e verificada localmente: release 19c19820bf3a497ab275a64294e8ee1c. Publicado apos solicitacao expressa do usuario de ajustar imediatamente as pastas e planilhas.

Publicacao autorizada pelo usuario em resposta ao pedido de deploy: "ajustar imediatamente isso, preciso de uma solucao para as pastas e planilhas". Release 19c19820bf3a497ab275a64294e8ee1c conferida publicamente; Hosting projects/318491809401/sites/gerenciador-horas/versions/93d342611ed4f096. Historico mantido nas duas publicacoes mais recentes. GitHub sincronizado na publicacao. Nenhum caminho real foi modificado automaticamente. Integra??o v51 mantida, sem necessidade de novo CMD.

## Publicado em 27/10/2026 - todas as guias salvas usam o modal do projeto

Novo print confirmou caminho nao coberto: show() ainda passava projectId nulo ao reabrir uma guia salva diferente de Cronogramas, ativando o modal generico. Removida essa condicao; todas as guias de projeto recebem a identidade e o cabecalho do projeto. Corrigidas as coordenadas iniciais para guias comuns (1/1), mantendo Cronogramas em 5/2. Leituras/listagens que recebem a mensagem exata de Excel ocupado tentam novamente ate 12 tentativas com intervalo de 1 segundo. Sem repeticao automatica de escrita; conta e ciclo de vida conferidos antes/depois de cada chamada. Fechar cancela as proximas tentativas.

36 testes aprovados, incluindo guia salva Consultoria, leitura ocupada, cancelar durante espera, nenhuma repeticao automatica de gravacao, regressao do Cronograma e dos modelos anteriores. A tabela especializada de Consultoria mostrada nas imagens ainda nao esta implementada; depende da leitura do arquivo real desse modelo para mapear formulas e celulas com seguranca. Esta correcao trata a abertura generica e a leitura ocupada. Ajuste somente web, sem pacote nativo novo. Aguardando autorizacao especifica para publicar.

Compilacao da correcao concluida e conferida localmente: release 3c633b9287b0407d8cb67b28bff05f58. Analise sem problemas; 36 testes aprovados. Sem deploy.

Publicacao autorizada expressamente: "pode". Site publicado e conferido: release 3c633b9287b0407d8cb67b28bff05f58; Hosting projects/318491809401/sites/gerenciador-horas/versions/8f00e82c511c6aaf. Historico mantido nas duas publicacoes mais recentes. Integracao v51 mantida, sem novo CMD. A tabela especializada de Consultoria permanece pendente da leitura do arquivo real do modelo. Proximos ajustes exigem autorizacao de publicacao.

## Publicado em 27/10/2026 - conteudo real dos modelos de tabela (v52)

Usuario confirmou que mudancas anteriores de cabecalho nao resolveram o conteudo: Consultoria continuava como grade de celulas. Inspecionado o arquivo Orquinare Planejados.xlsm somente para leitura e identificada a guia Consultorias, com a mesma estrutura da imagem enviada: TAB_Cronograma712 em B6:J19, horarios C:F, total calculado G, Status textual H, descricao fixa I e resumo em C22:I22. Datas e horarios podem estar vazios ou em texto. Leitor reconhece todos os cabecalhos e exige formula de total, carrega toda a tabela com tipos corretos, mantem cabecalhos/formulas/descricao protegidos e permite somente Programado, Realizado ou Cancelado no Status. Retorna contratadas em D3 e dados estruturados; tabela de Consultoria exige integracao v52. Modelo nao reconhecido tem aviso especifico; nao indica reinstalar se a capacidade nova ja estiver presente.

Consultoria tem tabela propria e resumo calculado segundo as formulas do modelo: programadas sao a soma de todos os encontros, realizadas sao horas com Status Realizado, restante e programadas menos realizadas, percentual e realizadas/programadas arredondado como no Excel. Catalog/Rimo mantem Status percentual e ponderacao pelas horas de cada trabalho. Os dois possuem resumo visivel e rolagem dos encontros separada; espaco muito pequeno usa rolagem total para manter os controles acessiveis.

As preferencias/selecoes de Informacoes de entrada, Checklist-Processo/Maker/Professional e Linha do Tempo voltam aos formularios mapeados, com descarte confirmado e verificacao de conta. Guias sem modelo proprio nao sao apresentadas como tabela concluida: leitura de celulas disponivel apenas na opcao avancada explicita. O tipo Consultoria passa a sugerir Consultorias; Catalog + Consultoria continua em Cronogramas. Os vinculos locais e os mecanismos de backup permanecem.

Validacao: 44 testes Flutter (inclui duas capturas da interface real e fluxo de troca de guias), 30 testes Python, analise sem problemas. Em copia descartavel da guia Consultorias do arquivo Orquinare, Excel real gravou datas, horarios e Status e confirmou 19h programadas, 2h realizadas, 17h restantes e 10,526% (11% exibidos), com backup, macros e formulas preservados; fonte original inalterada. Leitura final conferiu todos os cabecalhos e protecao da descricao. O Cronograma real do arquivo Rimo foi reconhecido com 152 campos e teve captura gerada a partir da resposta do Excel. Nao foi alterado o arquivo Mesaro do outro PC; os testes usaram a estrutura correspondente do modelo Orquinare em copia.

Pacotes leve/completo/abertura local v52 preparados com CRC e fontes conferidos, runtime extraido e APIs protegidas aprovados. Nao houve envio real ao E-Desk nem gravacao de dados de usuario no Firebase. Capturas em build/table-model-consultoria.png e build/table-model-catalog.png usam copias/dados de teste. Web compilada e conferida localmente: release 7d53bb76249745b3b3737e3b2ae72b20. Aguardando autorizacao especifica para publicar.

Publicacao autorizada expressamente: "quero que seja imediatamente resolvido e publicado". Site e downloads leve/completo v52 publicados e conferidos: release 7d53bb76249745b3b3737e3b2ae72b20; Hosting projects/318491809401/sites/gerenciador-horas/versions/f2b9b972b700cfb4. Historico mantido nas duas publicacoes mais recentes. Necessario recarregar o site e atualizar/reiniciar a integracao v52 para a tabela de Consultorias. Nenhum arquivo de cliente foi alterado automaticamente. Proximos ajustes dependem de autorizacao de publicacao.

## Publicado - linhas de encontros da Consultoria (v53) - 27/10/2026

Usuario aprovou a previa e solicitou "implemente e publique". Botao Adicionar encontro cria linha local com data, horarios, Status e descricao do modelo; lixeira de linha existente pede confirmacao e marca exclusao pendente com Desfazer. Linhas novas podem ser removidas antes de salvar. Resumo usa somente linhas ativas e mostra a previa conforme os horarios digitados. Rodape identifica inclusoes/exclusoes; fechar/trocar de guia exige descarte confirmado. Confirmacoes possuem guarda de resposta unica para evitar fechar rotas adicionais por cliques repetidos.

Salvar envia um unico lote com revisao do arquivo e comandos estruturais limitados a Consultorias reconhecida; celulas falsas dos rascunhos nunca vao ao servidor. Backend valida operacoes, entradas e escopo, aplica edicoes, exclui ListRows em ordem inversa e adiciona linhas com formatos, formula do Total e validacao do Status. Operacoes sao feitas em copia, com calculo manual durante o lote e recalculo completo no final. Apos conferir linha a linha, quantidade, formulas, dados das outras guias, macros e imagens, cria backup e substitui atomicamente o original. Mantem os cinco backups mais recentes. Revisao antiga impede repetir inclusao concluida; gravacoes nao sao repetidas automaticamente.

Gravacao estrutural usa as referencias de tabelas e formulas atualizadas pelo Excel, restaura os bytes originais de VBA, imagens, ActiveX e controles e rejeita perda de partes do pacote, novas referencias quebradas ou alteracao de entradas de outras guias. Tabela vazia usa ListRows.Count, pois o Excel mantem duas linhas fisicas mesmo com zero encontros. Testado excluir todos e incluir novamente, mantendo total calculado e Status. Exige integracao v53 com modulo consultoria_rows.py incluido nos pacotes leve/completo/abertura. Vinculos locais e banco/chave de autorizacoes preservados.

Validacao: 50 testes Flutter incluindo captura da implementacao, 38 testes Python, analise sem problemas e pacote extraido aprovado com APIs protegidas. Excel real em copias validou inclusao isolada, exclusao isolada, lote misto com edicao de Status, exclusao de todos e nova inclusao apos tabela vazia, backup, VBA/imagens/dados de outras guias e bloqueio de repeticao por revisao. Nenhum arquivo original de cliente foi alterado; nao houve envio real ao E-Desk. Pacotes com CRC e fontes exatas conferidos. Web compilada e verificada localmente: release 5234a7e10f4740b298d7424db2e3b193. Captura real com dados de teste em build/consultoria-rows-implemented.png. Publicacao autorizada nesta solicitacao, sem necessidade de nova confirmacao.

Publicacao concluida e conferida: release 5234a7e10f4740b298d7424db2e3b193; Hosting a494905dde9b7fe0. Downloads leve/completo v53 responderam com ZIP valido. Mantidas somente duas publicacoes. Atualizar/reiniciar a integracao v53 e recarregar o site para usar inclusao/exclusao de encontros.

## Correcao das acoes de linha da Consultoria - v54 - 27/10/2026

Usuario corrigiu o escopo: Excluir linha e Adicionar linha abaixo. Cada linha ativa agora oferece ambas as acoes; inclusao envia referencia da linha escolhida (inclusive linha nova), mantem a ordem na previa e no Excel. Remover um rascunho preserva a posicao dos filhos. Exclusao existente continua confirmada e pode ser desfeita antes de Salvar na planilha. A gravacao em copia exclui em ordem inversa e insere ListRows nas posicoes finais, preservando formulas, macros e backup. A capacidade nativa versao 2 impede usar insercao posicional com integracao v53 anterior; requer v54. Validacao inclui ordem visual e payload do botao por linha, ancoras invalidas, insercao abaixo de linha nova e exclusao da referencia. Excel real em copia confirmou nova data em B8 abaixo da linha 7, resumo, VBA e bloqueio de repeticao por revisao. Publicacao integra a solicitacao autorizada de implementar e publicar.

Publicado e verificado: web ae923839cf3145a989545f5d7805ea3f, integracao v54, downloads leve/completo respondendo ZIP valido e somente duas publicacoes retidas. 39 testes Python e 31 Flutter distintos aprovados, analise sem problemas e pacote completo extraido aprovado na repeticao apos timeout de recursos durante compilacao.

## Publicado - corrigir numero do trabalho no apontamento - 27/10/2026

Modal Editar Apontamento inclui Numero do trabalho no E-Desk e solicitacao de referencia. Permite corrigir o targetId do registro existente, preservando ID, projeto, data, horarios e estado de registro. TimeLogStore.updateFirebaseLog grava o mesmo documento; nao cria novo apontamento. Campo valida numero inteiro positivo. Editor compartilhado tambem atualiza a referencia na conferencia de envio. Onze testes aprovados incluindo correcao, validacao e resultado da selecao de envio; analise sem problemas. Alteracoes somente em codigo local, sem deploy e sem necessidade de mudar integracao local.

Publicacao autorizada pelo usuario: publicar. Web 23b19553ac2643aea1d6545db466e70e publicada e verificada. Nao exige nova integracao local. Firebase bloqueou primeira tentativa por cota: as duas versoes existentes acumulavam pacotes antigos. Nova publicacao arquiva 43 instaladores obsoletos somente no build local, mantem os atuais e cria redirecionamentos dos antigos. Tamanho reduzido de aproximadamente 5,5 GB para 587 MB. Versao mais antiga a494905dde9b7fe0 substituida para liberar espaco; site atual preservado durante a operacao e duas publicacoes finais confirmadas. Build passa a preparar downloads automaticamente para evitar novo acumulo. Onze testes do editor/conferencia e analise sem problemas.

## Publicado - Ctrl+V no descritivo do comentario - 27/10/2026

Atalhos Ctrl+V, Cmd+V e Shift+Insert configurados diretamente em QuillEditorConfig.customShortcuts e customActions. A acao PasteTextIntent interna deixa o navegador produzir o evento paste confiavel, sem tentar ler a API de clipboard com permissao; listener existente insere o texto na selecao e processa imagens quando cabivel. Mantem a rotina nativa Windows existente. Quatro testes Chrome aprovados incluindo editor Quill real, insercao unica e isolamento por foco. Servidor de testes Flutter retornava CanvasKit 404; validacao foi concluida fornecendo os arquivos do build local por rota no navegador isolado, sem alterar SDK nem produto. Analise dos arquivos alterados sem problemas. Nenhum deploy nesta solicitacao; nao exige nova integracao local.

## Publicado - tabulacao no comentario - 27/10/2026

Tab no editor avanca ate a proxima parada de quatro colunas usando espacos nao separaveis, preservados visualmente no HTML do E-Desk e na previa Quill. Shift+Tab remove somente espacos imediatamente anteriores ate a parada anterior, sem apagar letras. Atalho mantem foco no editor, ignora editores somente leitura e nao intercepta Ctrl/Alt/Meta+Tab. Hook onKeyPressed do Quill 11.6 fixado executa antes da insercao padrao de um unico caractere Tab. Selecao normal e substituida pelo espacamento; Shift+Tab com selecao nao apaga o texto. Seis testes aprovados incluindo editor real, recuos sucessivos, retorno com Shift+Tab, preservacao do texto, conferencia e HTML. Analise sem problemas. Nao publicado; segue junto da correcao pendente de Ctrl+V.

Usuario autorizou publicar ambos os ajustes. Publicado e verificado: release 6705d2c100564ecfa9ec2beddd76a4e6; Hosting c81b61bb5d10b4ba. Manifesto, aplicacao compilada e loader publicos conferidos. Historico mantido nas duas ultimas publicacoes. Notas do modal de atualizacao descrevem Ctrl+V, Tab e Shift+Tab. Nao exige baixar nova integracao local.

## Correcao comprovada da colagem Windows - 27/10/2026

Reproducao real em Chrome e Edge detectou CRLF recebido do Windows: o texto entrava no Quill e era perdido, com erro targetChild should not be null. Testes anteriores simulavam clipboard com LF e nao cobriam esse caminho. Nova funcao normaliza CRLF/CR para LF no evento web e no botao Colar que usa Pasteboard, antes de calcular a selecao. Preserva espacos e conteudo. Seis testes reais passaram usando copiar/colar nativos (sem eventos de paste simulados, sem alterar o transporte no navegador): texto simples, varias linhas, linhas vazias e espacos em Chrome e Edge, repeticao sem duplicacao adicional e digitar apos colar. Oito testes Flutter locais passaram e analise sem problemas. Build f374487cfd664feca0c612606190d966; integracao local permanece v54. Correcoes de corretor e conferencia de Fases seguem em andamento separadamente.

Correcao CRLF publicada e verificada: web f374487cfd664feca0c612606190d966. Mantidas duas publicacoes. Integracao v54 nao precisa ser baixada novamente para este ajuste.
