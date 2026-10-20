# Liberação dos novos ajustes

Conta designada pelo usuário: **rodrigozaparolli79@gmail.com**.

O novo menu de ações do projeto e o editor das abas Informações de entrada e
Checklist-Processo estão implementados inicialmente apenas para essa
conta autenticada. Manter a interface e os fluxos existentes para as demais
contas. Não liberar a todos sem nova orientação do usuário.

Usar `PilotFeatureAccess.allows` para verificar a conta ao apresentar e ao abrir
os novos recursos. A troca de conta deve retirar o acesso imediatamente; não
persistir um booleano global de liberação nem decidir pela máquina ou navegador.

Para futuras operações de gravação na planilha, verificar a mesma conta no
serviço usando as informações do token Firebase validado. Nunca aceitar um
e-mail informado no corpo da requisição como autorização. Continuar exigindo
autorização do vínculo de arquivo para o UID da conta.

O serviço exige token da conta designada com identidade validada pelo Firebase e autorização
prévia do arquivo para o UID. A interface é liberada pela conta autenticada;
o serviço faz uma segunda validação independente antes de acessar a planilha.

Uso: Planilha → Editar no sistema. Requer Microsoft Excel instalado e integração
spreadsheet-dates-22 neste computador. Somente XLSX e XLSM de até 25 MB com as
abas e cabeçalhos esperados. Alterações ainda não salvas exigem confirmação
antes de descartar. Falha ou resposta incerta exige recarregar para conferir.

O serviço calcula em cópia com macros desativadas e preserva o pacote original,
incorporando apenas células editadas e caches calculados. Fórmulas, VBA,
imagens e controles não são substituídos pelos componentes regravados pelo
Excel. Backup anterior à troca fica em .gerenciador-backups ao lado do original.
Um arquivo aberto no Excel deve ser fechado antes de confirmar a gravação.

As macros dos botões da planilha não são executadas automaticamente. Alterar
produtos não executa Atualizar Planilha de Implantação; usar esse botão no Excel
quando necessário. O arquivo enviado para análise não foi modificado pelos testes.

Desde spreadsheet-dates-22, a leitura aceita datas como números do Excel,
texto brasileiro ou ISO. Instruções do modelo são exibidas como texto sem
alterar as células automaticamente nem impedir a abertura da planilha.

## Cópia da planilha no sistema e colaboradores

O editor salva os campos mapeados, tarefas, revisão e nome do arquivo em
`users/{uid}/projects/{project}/spreadsheet/snapshot`, com referência original,
versão do esquema e data de sincronização. O conteúdo é JSON em um campo sem
consultas internas, limitado a 850 KB. Referência diferente invalida a cópia.
Na reabertura, utiliza a cópia; não inicia Excel nem pede integração local.
Recarregar do Excel busca alterações externas. Ao salvar, a integração continua
conferindo a revisão do arquivo antes de gravar. Apenas a resposta confirmada
substitui a cópia salva. Edições pendentes continuam locais e exigem confirmação
para descarte. Falha no Firebase após gravação confirmada não repete a gravação
no Excel; a ação Salvar cópia no sistema tenta apenas a persistência da cópia.

O cadastro de colaboradores fica em `users/{uid}/company_contacts`, separado
dos projetos e das contas de acesso ao app. Permite nome, e-mail, busca,
edição e exclusão, sem cadastrar automaticamente os contatos do cliente.
Na planilha, selecionar um nome de contato preenche o e-mail pareado.
Quando o e-mail é calculado, exibe a prévia do cadastro sem enviar uma escrita
na célula da fórmula. Ao salvar, confere o resultado calculado pelo Excel e
avisa se o cadastro interno de consultores da planilha produzir outro e-mail;
mostra e persiste o valor real retornado pelo Excel. A fórmula é preservada.
Nos três modelos de e-mail, o cadastro permite seleção nos
campos Para/Cc e sugestões nos nomes dos contatos. Não adiciona destinatários
automaticamente nem permite repetir um endereço entre Para e Cc.
O botão + de cada campo também lista os colaboradores cadastrados e insere
nome e e-mail juntos; Adicionar todos continua selecionando somente os
contatos disponíveis do projeto, sem incluir todo o cadastro da companhia.
Ambos os recursos permanecem restritos à conta piloto, com dados sob o UID
e as regras existentes do Firestore. Não alteram a integração local v22.

## Movimentação de pastas de projetos finalizados (v23)

Ao salvar um projeto que passa para TRAB_FIM, o app abre uma conferência
opcional. Também disponível em Projetos Finalizados → Visualizar. Selecionar
o diretório pai de destino uma vez; a preferência fica no UID. O app apresenta
origem/destino e exige confirmação. Não inicia a movimentação ao abrir o modal.
Uma planilha dentro da pasta acompanha o movimento, preservando seu caminho
relativo; uma planilha fora dela permanece no mesmo local.

A integração project-archive-23 aceita somente referências autorizadas para
o UID autenticado da conta piloto. O plano e o registro durável ficam no SQLite
estável da integração. Não aceita caminhos arbitrários no commit. Usa rename
na mesma unidade/disco, recusa colisão, destino dentro da origem, raízes,
pastas de sistema/integração e junções/links dentro da árvore. Não há cópia
com exclusão entre unidades nesta versão. A árvore é conferida antes/depois;
o lock do editor impede corrida com leituras/gravações feitas pelo app.

Uma operação confirmada retorna os mesmos vínculos ao repetir o commit;
interrupção após rename é recuperada pelo registro moving. O app atualiza
pasta/planilha, referência da cópia salva e histórico do movimento em transação
no Firestore. Recusa sobrescrever vínculos editados por outra tela. Se só a
atualização no Firebase falhar, o botão Atualizar vínculos repete apenas essa
etapa. Nenhum arquivo real de cliente foi usado nas movimentações de teste.

## Destino individual no perfil (v24)

Por solicitação explícita, a configuração do destino é acessível a todas as
contas autenticadas em Perfil → Pasta de projetos finalizados. Isso não amplia
a liberação piloto do movimento. Cada conta mantém sua preferência em
users/{uid}/configuracoes/project_archive. O caminho fornecido pelo proprietário
é sugerido somente para sua conta e apenas quando não há preferência salva:
C:\Users\rodrigo.zaparolli\OneDrive - Cyncly\Documentos\Projetos Finalizados.
É preciso salvar para persistir a sugestão. Preferências já existentes vencem
o valor sugerido; cada usuário pode alterar seu próprio caminho.

É possível digitar o caminho sem integração. Isso não autoriza acesso local;
Selecionar pasta no Windows concede a autorização nativa existente, e alterar
o texto invalida o vínculo selecionado. O modal de movimentação lê a mesma
preferência. Alterar o destino não move arquivos, nem muda projetos anteriores.

A v24 aceita apenas os marcadores de armazenamento IO_REPARSE_TAG_CLOUD[0-F]
do OneDrive entre os reparse points; symlinks, junções e tags desconhecidas
continuam recusados. Subpastas inacessíveis interrompem a conferência.
O manifesto v2 ignora metadados de diretórios, mantendo caminhos e metadados
dos arquivos. Operações antigas sem versão usam o manifesto v1 ao recuperar.
Testes simulam os marcadores Cloud Files; não houve validação de sincronização
no OneDrive do usuário nem movimentação de uma pasta real de cliente.
