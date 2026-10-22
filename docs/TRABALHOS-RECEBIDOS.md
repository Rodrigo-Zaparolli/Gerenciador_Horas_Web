# Trabalhos recebidos — piloto E-Desk → app

Disponível para `rodrigozaparolli79@gmail.com` e `maiquel.elste@cyncly.com`. A API valida a identidade pelo token Firebase. A importação usa exclusivamente o espaço do usuário autenticado no Firestore. Não altera trabalhos no E-Desk.

Em Projetos, clique **Trabalhos recebidos → Buscar na Minha Grid**. A integração v38 precisa estar iniciada. Esta versão busca mediante clique; não monitora o E-Desk em segundo plano nem recebe eventos com o computador desligado.

A origem é a Minha Grid do login E-Desk configurado. O usuário confirmou que essa grade contém somente seus registros. O leitor exige cabeçalhos reconhecidos, preserva solicitação e número real do trabalho e percorre a paginação reconhecida. Inicia pela primeira página. Limites, referências conflitantes ou estruturas desconhecidas geram uma busca parcial explícita. Não presume que o primeiro número de qualquer linha seja a solicitação.

**Conferir e cadastrar** consulta os detalhes. Quando a grade informa números de trabalho, consulta esses números; quando informa apenas a solicitação, apresenta as etapas retornadas dessa solicitação para seleção do usuário. Cliente, tipo e líder são preenchidos quando identificados. Para projetos novos, o tipo deve corresponder a um cadastro de tipos de trabalho do app. Nomes, líder e horas não identificados devem ser informados antes da confirmação. Horas previstas usam HH:mm. Os números das etapas não são gerados pela posição de uma lista.

O status das etapas novas é Inicial, conforme informado na revisão. A data de recebimento vem explicitamente no formulário; datas previstas só são importadas quando reconhecidas e válidas. Os campos do trabalho podem ser conferidos antes de **Cadastrar no app**.

Para um projeto novo, cria o cadastro com as etapas selecionadas e a soma das horas previstas. Para um projeto existente, apenas acrescenta etapas ainda ausentes, recalculando a estimativa; preserva cliente, tipo, líder, horas realizadas, caminhos, checklist e tarefas anteriores. Etapas existentes ficam desmarcadas e bloqueadas na revisão.

## Importar pelo ID

Ao lado de **Novo trabalho**, o botão **Importar do E-Desk pelo ID** abre um campo de solicitação. Aceita somente números e consulta diretamente os trabalhos daquela solicitação pelo leitor de conferência; não depende da leitura prévia da Minha Grid. O acesso ainda usa a sessão e as permissões E-Desk do usuário.

A busca não grava projetos. Ela abre a mesma revisão de etapas, cliente, tipo, líder, datas e horas. Campos que o E-Desk não retornar ficam para preenchimento manual; nenhum nome ou número de etapa é inventado. Lista vazia, solicitação diferente e falhas não oferecem cadastro. Fechar ou cancelar não grava; somente **Cadastrar no app** confirma a importação.

Usa a integração existente (v39 para Maiquel). Mantém transações, preservação de projetos existentes, bloqueio de finalizados e controle de duplicidade. Ao fechar a janela, o painel recarrega os projetos do usuário. A leitura completa dos campos na estrutura real do E-Desk continua dependendo da validação no PC da integração.

## Duplicidade e falhas

A gravação é uma transação: lê o projeto ativo, o finalizado, possíveis documentos legados e marcadores por solicitação/trabalho antes de escrever. Uma nova tentativa após perda de confirmação não duplica etapas. Projetos finalizados devem ser reabertos manualmente. Troca de usuário interrompe a operação. Não sobrescreve metadados existentes e não salva uma parte das etapas quando algum campo obrigatório é inválido.

Testes em banco em memória exercitam perda de confirmação após commit, repetição, acréscimo sem sobrescrita, finalização concorrente e troca de usuário. Os testes Playwright usam páginas isoladas; a validação da estrutura real da Minha Grid e dos rótulos de campos ainda depende do teste no computador da integração. Nenhum projeto real é criado pelos testes.

## Reversão

O ponto anterior é o commit `f745766` (piloto de conferência). A implementação de recebidos fica em commit separado e pode ser revertida. Isso retira a funcionalidade, mas preserva projetos que o usuário já confirmou no app. Os marcadores ficam em `users/{uid}/edesk_received`, sem senhas ou dados de sessão. Não há migração destrutiva ou mudança de regras do Firestore.
