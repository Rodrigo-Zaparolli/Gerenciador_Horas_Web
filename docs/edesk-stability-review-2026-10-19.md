# Revisão conjunta dos envios — 19/10/2026

## Problema confirmado e corrigido

A nova conferência de horas substituiu a conferência antiga, mas deixou de
encaminhar `retryUncertain` para a integração. O histórico local continuava
bloqueando os registros de uma tentativa sem confirmação. A confirmação manual
agora encaminha essa autorização tanto pela integração HTTP quanto pela extensão.
O histórico continua excluindo do novo envio os intervalos já confirmados.

O teste de regressão cobre um lote com uma hora confirmada, uma pendente e uma
incerta: somente as duas últimas chegam ao processo, com verificação de cadastro
anterior habilitada. A conferência mostra solicitação e trabalho por registro.

## Verificação reproduzível

Executar `scripts/check_edesk_regression.ps1` na raiz. Os registros ficam em
`build/edesk-regression-*.txt`. Uma falha interrompe a bateria e identifica seu log.

Cobertura incluída:

- Validação das requisições, autenticação, bloqueio de operação simultânea,
  falha antes de cadastrar, confirmação insuficiente e histórico por usuário.
- Seleção, edição e exclusão das horas; encaminhamento da autorização de retomada.
- Primeira hora com carregamento tardio, Ajax, controles ocultos e nova aba.
- Horas seguintes quando o E-Desk retorna à solicitação ou trabalho, fecha uma
  página, perde o formulário ou expira a sessão.
- Modelos, conteúdo do comentário, salvamento e confirmação parcial: comentário
  publicado com porcentagem pendente não deve ser publicado novamente.
- Porcentagem isolada sem abrir comentário, escolha do trabalho e verificação
  após salvar; navegador testa retorno à solicitação e recuperação de página fechada.

## Limites e aceite real pendente

Resultados desta revisão: 72 testes Python e 49 testes Flutter passaram.
As verificações isoladas de navegador também passaram separadamente: 16 casos
de seleção do trabalho, 12 de primeira hora, 12 lotes de três horas e retorno
ao trabalho para salvar/verificar a porcentagem.

O usuário confirmou que o app utiliza a integração de outro computador. Portanto,
a ausência de serviço local não é a causa da falha relatada. É necessário conferir
o endereço configurado e a versão do processo remoto antes do aceite real.

Os testes usam registros e páginas isolados. Não representam publicação na conta
real do E-Desk. Nenhuma hora, comentário ou porcentagem real foi enviada por esta
revisão. Não declarar o fluxo definitivamente validado apenas com esses testes.

Antes do aceite, verificar a versão da integração no computador que efetivamente
executa os envios e registrar os resultados reais de:

1. Um lote com pelo menos duas horas, sem intervenção para abrir o trabalho.
2. Comentário sem porcentagem, conferindo conteúdo e salvamento no app.
3. Comentário com porcentagem: comentário na solicitação; porcentagem no trabalho.
4. Porcentagem isolada, conferindo valor após reabrir o trabalho.
5. Recuperação de uma tentativa já falhada, sem repetir intervalo confirmado.

Usar registros legítimos definidos pelo usuário. Não criar publicações fictícias
nem reenviar registros confirmados para testar. A leitura local inicial não
encontrou serviço ouvindo em `127.0.0.1:8765`; isso não diagnostica o computador
remoto ou outra configuração de conexão.
