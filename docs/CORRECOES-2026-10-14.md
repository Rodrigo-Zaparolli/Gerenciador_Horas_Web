# Correções da revisão — 14/10/2026

Os quatro problemas funcionais documentados em `REVISAO-SISTEMA-2026-10-13.md` foram corrigidos.

- **Busca de Tarefas:** `TimeLog.dateFormatted` agora fornece uma String `dd/MM/yyyy`. A extensão redundante foi removida. Pesquisas por data e por texto inexistente não chamam métodos em `null`.
- **Prévia de comentário:** o HTML usa uma superfície de documento branca, com texto padrão escuro. As cores explícitas, fontes, imagens e estilos do conteúdo são preservados, independentemente do tema do app.
- **Intervalos:** o editor exige início e término válidos em 24 horas, término após início e duração positiva. A preparação de horas para o E-Desk também deixou de converter intervalos invertidos em uma jornada de quase 24 horas. Horários futuros continuam permitidos; horários digitados são normalizados para `HH:MM`.
- **Salvamento:** o novo `TaskLogEditDialog` envia uma cópia do apontamento. O registro original não é alterado antes da confirmação do armazenamento. Enquanto salva, campos, botão Salvar, Cancelar e fechamento por voltar ficam bloqueados. Falhas preservam o formulário, permitem tentar novamente e mostram orientação de recuperação. Após 30 segundos sem confirmação, o formulário é liberado e pede conferência do registro; o prazo não cancela uma gravação que já esteja em andamento no Firebase.

Também foram reforçadas as verificações de `mounted` nos fluxos assíncronos de dashboard, tabela, cadastro de projeto e tarefas. A análise final não apontou uso de contexto após espera assíncrona sem a proteção apropriada.

## Validação

- Suíte completa: **279 testes Flutter passaram**, com um teste reservado ao navegador, já validado na revisão anterior.
- Após normalizar também entradas como `8:00` para `08:00` e adicionar limite de espera, os **7 testes específicos** do editor e da prévia passaram novamente.
- Testes novos cobrem data formatada, busca sem correspondência, rejeição de horário invertido/igual, cópia do registro, falha de armazenamento, bloqueio de clique repetido, preservação das alterações, nova tentativa e contraste da prévia no tema escuro.
- O teste de colagem deixou de depender de uma espera fixa de 150 ms e aguarda a conclusão do processamento com limite de tempo.
- Análise estática: **zero erros**, zero avisos de contexto assíncrono; os apontamentos totais caíram de **882 para 226**. Restam **28 avisos** e **198 informações** de manutenção, incluindo variáveis não utilizadas, classes fictícias dos testes e estilo. Não foram ocultados indiscriminadamente.
- Nenhum envio real ao E-Desk, e-mail ou alteração em registros do usuário foi realizado pelos testes.

## Backup e dependências

A limpeza automática inicialmente alcançou a cópia histórica dentro de `build`. Seus **22 arquivos atingidos foram restaurados da cópia original** em `D:/APP/Gerenciador_Web/bkp/10.10/gerenciador_horas`, com comparação de bytes/hash; os outros **92 arquivos** já eram idênticos. A análise agora exclui `build`, `python` e `.venv`.

Uma dependência de diagnóstico adicionada automaticamente foi retirada; `package_config` foi mantido na versão original 3.0.0. A revisão não instala novas funcionalidades de produção nem exige atualização do pacote de integração local.

Evidências em `build/all-errors-verified-tests.txt`, `build/all-errors-final-regression.txt`, `build/all-errors-verified-analysis.txt` e `build/all-errors-web-release.txt`.

## Publicação

Publicado somente no Firebase Hosting. Versão `e464dbf05bc84018b13d1b04e2247021`; manifesto, JavaScript e carregador públicos conferidos. Login/cadastro abriram em desktop e celular sem erros JavaScript. Evidências adicionais: `build/all-errors-timeout-tests.txt`, `build/all-errors-public-release.txt` e `build/all-errors-public-browser.txt`.
