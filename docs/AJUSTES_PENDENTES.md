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
