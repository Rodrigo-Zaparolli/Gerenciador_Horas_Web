# Importação pelo ID com etapas do cadastro

## Modal unificado conforme a prévia aprovada

A consulta pelo ID e a conferência permanecem na mesma rota e no mesmo modal. A tela apresenta Novo trabalho, acesso ao cadastro manual e três seções numeradas: Consultar solicitação, Conferir dados do projeto e Vincular etapas do trabalho. O rodapé mantém o total previsto e a confirmação de cadastro. Os campos usam os temas do aplicativo; telas estreitas possuem rolagem vertical e horizontal explícitas. As datas podem ser digitadas ou escolhidas no calendário.

Alterar o ID após uma consulta desabilita o cadastro até que a nova solicitação seja consultada. A busca não grava projetos. O botão Cadastrar no app continua usando o armazenamento transacional existente e informa a conclusão. Fechar o modal não cadastra os dados. A aba Cadastro manual fecha a importação e abre o formulário manual já existente. O acesso às contas piloto continua preservado.

Verificações: 20 testes de importação, etapas e armazenamento; fluxo completo em uma única rota, temas claro/escuro e larguras de 390/1400 pixels. A validação da integração local e do envio de horas da v43 não é alterada por essa mudança web.

A conferência de importação por ID carrega os modelos completos de `WorkFormat`, os mesmos utilizados em Novo trabalho. Os nomes das etapas usam `workStepName` nos dois formulários. Selecionar um tipo monta suas etapas; não cria etapas a partir da posição das linhas retornadas pelo E-Desk.

Uma associação automática exige nome normalizado único nos dois lados. Na ausência de correspondência ou em caso de ambiguidade, o usuário escolhe um trabalho realmente consultado. Uma identidade não pode ser escolhida em duas etapas. Horas e datas vêm da consulta quando identificadas e podem ser conferidas; campos não identificados permanecem vazios. A confirmação valida as associações, HH:mm e datas antes de gravar. Trabalhos consultados sem associação não são importados automaticamente.

O cadastro continua transacional pelo `ReceivedWorkStore`: preserva metadados e etapas existentes, adiciona apenas identidades novas e mantém o controle de duplicidade. A consulta não escreve no E-Desk e fechar a conferência não cadastra no app. O piloto mantém a autorização já existente.

## Verificação local de 22/10/2026

- 16 testes Flutter de importação, cadastro e armazenamento passaram, incluindo tela de 390 px, IDs fora de sequência e associação manual.
- Análise Dart dos três arquivos alterados e do novo teste: sem ocorrências.
- 30 testes Python de horas e histórico passaram.
- Navegador isolado: 16 cenários de abertura fria/quente do trabalho e retroativo, inclusive painel visível com tabela oculta; cinco cenários de conferência de horas, ausência comprovada, paginação e listagem ilegível.

## Pendência de validação das horas

O usuário informou que a integração, ainda anterior à v41, chega ao retroativo e fecha sem cadastrar, após a revisão dos envios. O fluxo local reproduz esse comportamento quando a leitura prévia não consegue reconhecer uma listagem completa: não clica em Salvar para evitar duplicidade. Isso é uma hipótese compatível, ainda não uma causa confirmada no computador do usuário.

O código em revisão identifica essa recusa no retorno e preserva HTML/captura local antes da limpeza. A correção da aba Trabalhos também foi aplicada ao fluxo compartilhado de horas. Não foi desabilitada a conferência contra duplicidade. Foi solicitado um print do retroativo com a tabela de horas para confirmar e corrigir a leitura real. Os testes não acessaram o E-Desk real. Estas alterações ainda não foram empacotadas ou publicadas; a versão pública permanece v41.

### Vídeo 123456.mp4

Analisados 16 quadros do arquivo de 25,706667 segundos, em `build/hours-video-123456`. Ao final, o app mostra “Conferindo as horas cadastradas no retroativo”, 0 de 3 confirmadas; os campos do retroativo continuam vazios. O vídeo termina antes do fechamento ou mensagem de falha. A porção visível mostra o formulário e o histórico descritivo, sem os cabeçalhos da grade de horas. Os rótulos do formulário são “Hora de Início” e “Hora de Término”. Incluídas essas variantes semânticas no leitor da grade e testadas em um sexto cenário de navegador isolado, com registro preexistente preservado e somente os dois ausentes enviados. Isso não comprova quais cabeçalhos a grade real utiliza. Falta o print da listagem e seus cabeçalhos para confirmar a leitura no ambiente real.

### Vídeo aaa.mp4 e correção v42

O novo vídeo de 70,976 segundos revelou a tabela Timesheet. Os quadros originais de 27–30 segundos, em `build/hours-video-aaa`, mostram Atendente, Início, Término, Tempo, Motivo de Pausa, Tipo e comando Excluir. Início e Término contêm a data na própria célula; não existe a coluna Data exigida pelo leitor anterior. A revisão bloqueava o envio ao não reconhecer essa estrutura. O Tipo aparece como T; o formulário está em “Registrar somente um tempo trabalhado”.

O leitor aceita agora esse esquema combinado, além do esquema anterior com data separada. Datas e horas precisam ser válidas nas duas células; linhas incompletas não provam ausência. Botões de ação nas linhas não são tratados como campos de edição nem clicados. O tipo T é reconhecido como tempo trabalhado. A data final participa da comparação, evitando confirmar um intervalo de outro dia. A conferência e o limite de uma repetição apenas para ausência comprovada continuam ativos.

Cinco novos cenários de navegador reproduzem o Timesheet: registro preexistente, salvamento que precisa de repetição, paginação, grade vazia e linha incompleta. Todos passaram; o botão Excluir nunca é acionado. Total: 11 cenários de conferência. Também passaram 31 testes Python e 34 testes Flutter. A integração anuncia `hoursTimesheet`; o cliente exige essa capacidade antes de enviar, com orientação para atualizar para v42. A validação não efetuou envios no E-Desk real.

### HTML real do trabalho sem apontamentos — v43

O arquivo fornecido pelo usuário revelou um caso diferente: o E-Desk não renderiza o Timesheet quando ainda não há apontamentos. Não existe nem cabeçalho vazio. O layout original contém uma tabela externa de três linhas: solicitação e formulário; dados do trabalho e histórico; célula vazia reservada ao Timesheet. Início, término e histórico estão vazios.

O leitor reconhece esse estado somente na página/formulário TrabalhoRetroativo, com todos os controles e painéis esperados visíveis, a estrutura original completa, os dois campos de início/término existentes e vazios, histórico vazio e a célula reservada sem conteúdo ou elementos. Apenas a ausência de uma tabela ou um descritivo vazio não autoriza o envio. A leitura foi verificada diretamente no HTML fornecido, em navegador isolado com scripts e conexões externas bloqueados. O arquivo real e seus dados não fazem parte do repositório.

A seleção original do trabalho também permite associar Ordem e referência exibida diferentes, desde que a solicitação, a linha selecionada, o campo Ordem único e a identidade interna sejam confirmados. Ordem isolada não é suficiente. Diagnósticos de tabela passam a ser preservados por conta fora da pasta temporária do envio, com texto visível limitado e sem senhas, campos ocultos ou URLs de sessão.
