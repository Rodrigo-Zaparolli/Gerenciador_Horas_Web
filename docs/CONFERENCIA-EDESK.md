# Conferência de trabalhos no E-Desk — piloto

Disponível somente para `rodrigozaparolli79@gmail.com`, com restrição na interface e na API, validada pelo token Firebase. Não há migração de dados ou gravação de resultados no Firestore.

Na tela Projetos, use **Conferir no E-Desk**. No menu de ações de um projeto, use **Conferir este projeto no E-Desk**. O modal permite todos os projetos ativos (exclui finalizados e pausados), seleção individual ou número de solicitação. Os vínculos utilizam o número editável do trabalho e a solicitação específica de cada etapa, quando informada.

A consulta é executada por solicitação, sequencialmente. O progresso identifica a solicitação atual. **Parar após esta solicitação** termina a consulta atual e mantém os resultados anteriores. Falhas de autenticação, integração indisponível ou outra operação em andamento interrompem a fila. Trocar de usuário fecha o modal. Resultados não são persistidos nem aplicados aos cadastros.

Os campos comparáveis são nome, situação reconhecida e datas previstas/ajustadas explicitamente identificadas. Valores ausentes, situações não reconhecidas ou datas inválidas nunca são marcados como iguais. O percentual é consultado, pois não existe uma porcentagem equivalente no modelo do trabalho. As horas são opcionais e somam a listagem integral do retroativo; não são comparadas com a estimativa de horas do projeto. A prévia diferencia **Divergência**, **Não consultado**, **Somente consulta** e revisão manual de situação/data.

Uma solicitação informada manualmente utiliza os vínculos do projeto se já existir na lista do app. Caso contrário, tenta identificar os trabalhos na tabela da solicitação e exibe os dados sem comparação. Paginação não reconhecida, campos ambíguos e trabalhos inacessíveis geram resultado parcial ou erro; não há suposição de que os dados estejam corretos.

É necessária a integração **v37**, com a capacidade `workAudit` no `/healthz`. O script de consulta não preenche campos do trabalho nem chama funções de salvamento. Uma proteção de rede bloqueia comandos de salvar/excluir conhecidos do WebForms. O login e a navegação podem utilizar POSTs de leitura. O mesmo bloqueio de concorrência dos envios protege o perfil do navegador.

## Validação e limite

Testes de comparação e de API cobrem vínculos editados, divergências, campos ausentes, bloqueio de envio, restrição por conta e capacidade ausente em versões anteriores. O cenário Playwright isolado exercita a abertura do trabalho correto, enumeração da solicitação, leitura dos campos, consulta do retroativo e tentativa de POST de salvamento bloqueada. Não realiza acessos ou gravações no E-Desk real. Os rótulos e estruturas reais ainda precisam ser validados no computador do usuário; campos desconhecidos são sinalizados no resultado.

## Reversão

O ponto anterior à implementação é o commit `a28185e`. A implementação fica em commit separado: para remover o recurso, reverta esse commit e publique novamente o app. Não há dados do usuário a desfazer. A integração v37 pode continuar instalada com os demais envios; sem o botão, a consulta não é acionada. O pacote leve v36 também permanece disponível para retorno à versão anterior, após parar a integração e preservar `.edesk-local` e os demais dados locais.
