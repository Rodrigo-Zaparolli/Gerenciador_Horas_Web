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
