# E-mails do projeto — Enterprise

Ação de envelope na linha principal da tabela de projetos. Três modelos baseados nos exemplos fornecidos: contato inicial, finalização ao cliente + ER e encerramento interno. Não envia e-mails e não requer registro Microsoft Entra.

Os rascunhos são privados por conta Firebase, projeto e modelo: users/{uid}/projects/{projectId}/email_drafts/{kind}. Modelos padrão personalizados ficam em users/{uid}/configuracoes/enterprise_email_{kind}. As regras atuais restringem acesso ao proprietário. Os textos de exemplo não incluem dados privados do cliente original.

O backup do app inclui os rascunhos e modelos padrão. A filtragem de campos de senha permanece igual à política existente; esses campos devem ser conferidos/importados novamente após restauração. Arquivos anexados não fazem parte do backup.

## Planilha

A seção CLIENTE também importa proprietário, responsável técnico e participantes adicionais com nome e e-mail válidos. Os contatos têm grupo Cliente/Cyncly editável. Marcadores e linhas vazias não viram destinatários; o e-mail de acesso ao Portal não é usado como contato. Dados comerciais reconhecidos preenchem razão social, nome fantasia e CNPJ. O bloco Equipe Cyncly do e-mail interno inclui somente contatos do grupo Cyncly.

Atualizar da planilha do projeto usa excelLink e o acesso de arquivos já existente, sem modificar o Excel. Para links online ou problemas de permissão, Selecionar planilha permite importar XLSX/XLSM pelo navegador. XLS antigo não é suportado. Aba Informações de entrada, seção CYNCLY até INFORMAÇÕES COMERCIAIS. Detecta cargo, nome e e-mail em colunas adjacentes, descarta marcadores #...# e exige confirmação antes de substituir dados. Campos rotulados reconhecidos também são importados. Na importação, contatos Cliente válidos vão para Para no Contato inicial; na Finalização, clientes vão para Para e Executivo de Relacionamento Cyncly vai para Cc; no Encerramento interno, contatos Cyncly válidos vão para Para. Escolhas salvas permanecem ao reabrir. Rascunhos antigos sem seleção recebem a configuração inicial do modelo. A geração exige revisão e não envia e-mails.

## Rascunho

Campos editáveis, assunto e mensagem editáveis. Regerar a partir dos campos substitui as edições manuais da prévia. Salvar neste projeto afeta apenas o modelo selecionado; trocar de modelo guarda alterações temporariamente nesta sessão. Antes de fechar, salvar cada modelo alterado.

Os anexos escolhidos ficam somente em memória, até 20 MB combinados, e não são salvos no Firestore. Trocar de modelo limpa os anexos; selecionar novamente antes de gerar. Nunca indicamos documentos como anexados sem selecionar os arquivos.

Gerar e-mail para Outlook baixa um .eml MIME com assunto UTF-8, corpo HTML e texto, Para/Cc deduplicados, anexos e X-Unsent: 1. Cada geração exige revisão. Abrir como mensagem editável depende da versão/configuração do Outlook; validar no computador do usuário. A geração e os bytes dos anexos têm testes automatizados, mas o envio real pelo Outlook não foi testado. Copiar texto é alternativa manual, sem transportar destinatários/anexos.

Os modelos mantêm a estrutura textual dos exemplos. A assinatura gráfica original do Outlook e a reprodução exata do HTML dos arquivos MSG não fazem parte desta primeira versão; a assinatura textual é editável.

A importação também reconhece nome resumido, ID do sistema, NS, versão/revisão, assinatura da proposta, dados de endereço, telefone secundário, CPF, acesso ao Portal e Prices. Os campos disponíveis e suas tags aparecem em Editar modelo. Cada modelo usa suas próprias tags; não acrescentamos todos os dados indiscriminadamente a todos os e-mails. Contatos preenchidos sem e-mail ficam fora dos destinatários até serem corrigidos.

Na confirmação da importação, Regerar assunto e mensagem conforme o modelo usa os dados atualizados e substitui edições manuais. Desmarcar conserva a mensagem personalizada. O print da proposta e o resumo da implantação continuam preservados quando a planilha não traz um novo resumo. Produtos marcados Sim/Não não substituem o print.


O botão Carregar dados no modelo fica no topo do modal. Ele atualiza assunto e mensagem com os campos atuais e o modelo selecionado, substituindo edições manuais na prévia. Não importa a planilha novamente nem envia o e-mail. Print e resumo são mantidos.

