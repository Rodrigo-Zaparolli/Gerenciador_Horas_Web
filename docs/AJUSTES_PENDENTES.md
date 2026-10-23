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
