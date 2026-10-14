# Alertas do dashboard

O pop-up abre quando o usuário entra ou volta ao dashboard e existem pendências.
O sino da Central de alertas permite consultar o aviso novamente. Fechar o aviso
não altera prazos, status, comentários ou registros de horas.

- Prazos: mesma lista da Central de alertas, incluindo atrasados, vencimento hoje
  e os próximos cinco dias. `DeadlineAlert.collect` concentra a regra existente.
- Comentários: mantém o prazo de 14 dias contado do último comentário enviado
  ao E-Desk; rascunhos e testes não reiniciam o prazo.
- Ações: ir à Central, abrir o comentário ou acessar Solicitações.

Um único modal reúne os avisos. A verificação descarta resultados de outra visita,
conta ou tela e evita sobrepor outro modal. Falha na leitura dos comentários não
impede mostrar os prazos; nesse caso, o aviso informa que a verificação foi parcial.
Não envia comentários nem horas automaticamente. Usa os três temas do aplicativo.

Validação: `test/dashboard_alerts_test.dart` e `test/project_update_test.dart`.
