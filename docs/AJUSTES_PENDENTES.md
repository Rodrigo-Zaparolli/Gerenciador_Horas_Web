# Controle de publicação dos ajustes

Por instrução do usuário em 23/10/2026, reunir os próximos ajustes e publicar somente no horário que ele definir. Não executar deploy nem enviar as alterações para publicação automaticamente.

Exceção autorizada em 23/10/2026: o usuário pediu “esse pode publicar” para o seletor de percentuais e o filtro de pendentes descritos abaixo. A autorização vale para este ajuste; os próximos continuam aguardando autorização ou horário definido.

## Publicado em 23/10/2026 — modal de percentuais do Checklist-Processo

- Seleção de 0%, 25%, 50%, 75% e 100% com o símbolo visível em cada opção.
- Opção Somente pendentes, ocultando tarefas concluídas em 100%.
- O filtro considera os ajustes do modal e preserva os valores das tarefas que ficam ocultas.
- Cancelar descarta o rascunho; Aplicar ajustes devolve os valores ao editor. Salvar na planilha continua sendo a gravação explícita no Excel.
- Valores anteriores fora das opções usuais continuam preservados sem arredondamento silencioso.

As notas em `release-notes.json` descrevem esse ajuste autorizado para publicação.

Validação: 27 testes passaram (modal, editor da planilha e prévia); análise dos três arquivos alterados sem problemas. Publicação autorizada pelo usuário, compilada e conferida no site. Release web: `6d8b0b21fdba4f859675a6343791d43c`. A integração local permanece na v45. Os próximos ajustes continuam sujeitos à autorização ou ao horário definido pelo usuário.
