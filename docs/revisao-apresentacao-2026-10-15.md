# Revisão para apresentação — 15/10/2026

Revisão das alterações recentes do Gerenciador de Horas Web. Os testes usam
dados de exemplo e ambientes isolados; não publicam comentários, fases ou horas
reais, não criam usuários e não modificam os projetos de produção.

## Correções realizadas

- Incluído `edesk_bot/work_selection.py` no Dockerfile e na lista de arquivos
  permitidos no contexto Docker. A falta desse módulo impedia importar o robô
  de horas no pacote para servidor. O pacote completo para Windows já o incluía.
- A exclusão na conferência de horas agora tem limite de espera de 30 segundos.
  Se a resposta não chegar, o modal pode ser fechado, mantém o registro visível
  e bloqueia o envio daquela conferência. A mensagem orienta fechar e conferir
  os registros novamente, pois a operação no servidor ainda pode concluir.
  Uma resposta tardia não desbloqueia o envio com dados antigos.

## Validações concluídas

| Área | Evidência |
| --- | --- |
| Suíte Flutter completa | 420 testes aprovados; 5 casos exclusivos do navegador não executados na VM |
| Integração Python | 62 testes aprovados após corrigir o empacotamento |
| Conferência de horas | 5 testes aprovados, incluindo edição, seleção, exclusão com falha, espera sem confirmação e tela de 390 px |
| Abertura pública | Login, navegação ao cadastro e retorno ao login aprovados em 1440 × 900 e 390 × 844, sem erros JavaScript |
| Aparência pública | 11 temas em desktop e tela pequena; preferência preservada após recarregar, formulário preservado durante troca de tema |
| Pastas e arquivos no navegador | Seleção, criação, leitura, persistência, cancelamento e isolamento por usuário/navegador com arquivos temporários |
| Horas E-Desk | 16 cenários simulados de layout, carregamento e navegação; ID exato, rejeição de ambiguidade e formulário retroativo obrigatório |
| Comentários E-Desk | Fluxo simulado de retorno à solicitação, trabalho exato, um salvamento da porcentagem e verificação após recarregar |
| Pacote Windows | ZIP extraído: importações, navegador, botões de comentário, serviço local, identificação work-selection-13 e APIs protegidas |
| Colagem no Chrome | Adaptadores Dart reais compilados para JavaScript: texto entregue uma vez, imagens direcionadas ao editor ativo, limite de tamanho, perda de foco e descarte após fechamento |
| Análise estática | Sem erros de análise em `lib`; permanecem avisos e recomendações de manutenção. O componente final de conferência passou sem apontamentos |

A suíte Flutter inclui casos de métricas mensais, planejamento, contraste,
resumo de projetos finalizados, PDF, recuperação de rascunhos, backup,
destinatários e modelos de e-mail, assinatura, planilha e confirmação de envio.
Não substitui testar cada combinação com dados de produção.

Os cinco testes Flutter exclusivos da plataforma web não concluíram no runner
Chrome: a compilação ficou sem progresso e foi interrompida. A verificação
alternativa dos adaptadores de colagem foi aprovada no Chromium com eventos
sintéticos. Ela não equivale a validar a área de transferência física ou a
interação completa dos cinco widgets no PC da apresentação.

Para repetir a verificação alternativa:

```powershell
dart compile js scripts/clipboard_adapter_fixture.dart -O2 -o build/clipboard_adapter_fixture.js
./python/python.exe scripts/check_clipboard_browser.py
```

Os registros técnicos desta execução ficam em `build/presentation-*.txt`.
As capturas do site estão em `build/presentation-browser` e
`build/presentation-appearance`. Esses arquivos temporários não são enviados
ao GitHub nem incluídos na distribuição da integração.

## Limites e conferência no computador da apresentação

Não houve acesso ao outro computador nem login real no E-Desk, Outlook ou
Firebase com a conta do usuário. Portanto, não foi confirmado um cadastro real
de horas, fases ou comentário no E-Desk, a abertura do Excel/Outlook instalado
naquele PC, nem o salvamento com permissões e rede daquele ambiente.

Antes da apresentação, nesse computador:

1. Atualizar o site e entrar com a conta que será usada.
2. Se a demonstração incluir E-Desk ou arquivos locais, verificar a conexão em
   `/integracao-completa.html`; o serviço deve estar na versão work-selection-13.
3. Abrir um projeto conhecido, sua pasta e sua planilha.
4. Abrir a conferência das horas e revisar a seleção. Cancelar evita envio real;
   editar ou excluir salva a alteração no app e deve ser feito apenas em um
   registro apropriado para demonstração.
5. Abrir os modelos de e-mail e conferir os destinatários e a prévia.
6. Se for demonstrar publicação real no E-Desk, usar um registro de teste
   autorizado e conferir o resultado diretamente no E-Desk antes de repetir.

A correção da conferência é do app web e não exige baixar novamente a
integração. O ajuste Docker prepara o pacote para servidor; não implica deploy
de um serviço central ou alteração das regras de dados.
