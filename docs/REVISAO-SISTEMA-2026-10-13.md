# Revisão do sistema — 13/10/2026

**Atualização de 14/10/2026:** os quatro problemas funcionais abaixo foram corrigidos. Veja [correções e validação](CORRECOES-2026-10-14.md). O texto seguinte preserva o resultado original da revisão.

Foi executada toda a suíte automatizada disponível, complementada por testes no Chrome, testes de integração isolados e revisão do código. A revisão encontrou problemas funcionais que os testes existentes ainda não detectavam. Os problemas abaixo permanecem pendentes de correção; esta etapa não publicou alterações no app.

Não é uma certificação de 100% dos cenários reais. Não foram utilizados dados de projetos do usuário, credenciais reais, envios reais ao E-Desk ou gravações no Firebase de produção.

## Resultados

| Verificação | Resultado e alcance |
| --- | --- |
| Suíte Flutter completa | 275 testes passaram; 1 teste exclusivo de navegador foi inicialmente ignorado na execução nativa |
| Flutter no Chrome | 9 testes passaram: imagem/colagem, formato de horário, links, recuperação de cronômetro, prévia XLSX e abertura web do E-Desk; inclui o teste ignorado acima |
| Integração Python | 45 testes passaram, com respostas e salvamentos simulados |
| Núcleo da extensão | 7 testes JavaScript passaram |
| Extensão carregada no navegador | Horas, preservação/deduplicação, isolamento, fases selecionadas, comentários, preparação sem salvar, falha de salvamento, interrupção do runner e restrição de origem passaram em páginas fictícias |
| Site público | Login, abertura de cadastro e retorno ao login passaram em 1440×900 e 390×844, sem erros JavaScript; não foi criada conta real |
| Temas no site público | Os 11 temas atuais passaram em desktop e celular, com persistência após recarregar; troca inicial também preservou o texto digitado |
| Arquivos pelo navegador | Seleção/criação de pasta, seleção/leitura de arquivo, persistência, cancelamento, isolamento e rejeição de caminhos inválidos passaram em armazenamento isolado |
| Excel instalado | Duas planilhas sintéticas foram espelhadas, preservando os arquivos originais e a cor do cabeçalho |
| Pacote Windows completo | Runtime extraído, browser, serviço, capacidade Excel e rejeição de chamadas sem autenticação passaram; pacote não contém credenciais, perfis nem dados do usuário |
| Site → integração local | Health respondeu; horas/status/histórico/arquivos sem autenticação foram rejeitados com 401, sem iniciar envios |
| Publicação atual | Manifesto, aplicação compilada e carregador público correspondem à versão local |
| Análise estática Dart | 0 erros, 78 avisos e 804 apontamentos informativos; total de 882 |

A suíte Flutter inclui cálculos de horas, dashboard/cards, projetos finalizados, PDF, backup/restauração, modelos e importação de e-mail, destinatários Para/Cc, assinatura/imagens/links, recuperação de rascunhos, histórico E-Desk e atualização do site durante operações.

## Problemas prioritários

### 1. Busca de Tarefas pode lançar exceção — alta

`TimeLog.dateFormatted` retorna `null` em `lib/domain/models/dashboard_models.dart:37`. A busca em `lib/features/tasks/tarefas_executadas_screen.dart:247` chama `.contains(query)` nesse valor quando os demais campos não correspondem. A extensão de formatação no fim da tela não substitui um membro existente da classe.

Uma reprodução isolada confirmou `NoSuchMethodError` ao consultar `13/10/2026`. O problema também pode aparecer com uma busca sem resultados nos outros campos.

Correção sugerida: definir um getter `String` real com `dd/MM/yyyy` no modelo, retirar a extensão redundante e testar a busca da tela por data e por texto inexistente.

### 2. Prévia do comentário perde legibilidade no tema escuro — alta

A prévia respeita a cor explícita do HTML enviado, por exemplo `#111827`, mas é apresentada dentro de um Card escuro. Uma reprodução com `AppTheme.dark` mediu contraste de aproximadamente **1,108:1**. Isso torna o texto difícil de ler, embora os testes de existência dos widgets passem.

Referências: `lib/features/edesk/edesk_comment_preview.dart` e `lib/data/services/edesk_integration.dart:373`.

Correção sugerida: usar uma superfície de documento que mantenha legível o HTML, preservando as cores e o conteúdo enviados; testar contraste e imagens nos temas claros e escuros.

### 3. Intervalos invertidos e iguais são aceitos pelo editor — alta

`_calcularMinutos`, em `lib/features/tasks/tarefas_executadas_screen.dart:1730`, soma 24 horas quando o término é anterior ao início. Assim, **13:30 → 12:30 resulta em 23:00**. Início e término iguais resultam em zero e não há validação no botão Salvar.

É uma constatação da regra de código, não uma alteração de horas reais. Trabalho durante a madrugada pode ser válido, mas a virada de dia precisa ser explícita para distinguir esse caso de um erro de digitação.

Correção sugerida: validar intervalo positivo e pedir indicação explícita de término no dia seguinte quando houver suporte a trabalho noturno.

### 4. Editor altera o registro antes de confirmar salvamento — alta

O botão Salvar altera o próprio `TimeLog` utilizado pela tela antes de aguardar `updateFirebaseLog` (`lib/features/tasks/tarefas_executadas_screen.dart:2015`). Se o salvamento falhar, os dados em memória já foram alterados, sem restauração. O diálogo também não bloqueia novos cliques em Salvar nem Cancelar durante a operação.

É um risco confirmado pela sequência do código; não foi provocada uma falha em dados de produção.

Correção sugerida: salvar uma cópia do registro, substituir o original apenas após sucesso e bloquear ações enquanto salva. Validar sucesso, falha, clique repetido e fechamento durante a operação com armazenamento fictício.

## Manutenção e lacunas

- 568 apontamentos são usos de APIs depreciadas; não equivalem a falhas em execução.
- Há 29 apontamentos de uso de `BuildContext` após espera assíncrona. Revisar os fluxos de salvar, excluir e abrir diálogos para evitar ações em telas já fechadas.
- Imports/variáveis não utilizados e checagens de nulidade redundantes devem ser limpos gradualmente; evitar uma mudança ampla de estilo junto das correções funcionais.
- As regras locais de Firestore/Storage foram lidas, mas esta revisão não certifica que correspondem às regras implantadas nem substitui testes com emuladores e contas de teste.
- Cadastro/login efetivos, edição/restauração com Firebase real, serviços remotos e variações reais de páginas do E-Desk continuam exigindo ambiente ou contas de teste próprios. Os testes simulados não garantem ausência de mudanças no portal externo.
- O comportamento do Outlook após abrir um `.eml` depende da instalação e associação de arquivos em cada PC. A geração é coberta pelos testes, mas não foi enviado e-mail real.
- Acesso às pastas e Excel em outros computadores depende das permissões do navegador, caminhos disponíveis e integração instalada quando houver abertura nativa.

## Ambiente de testes

O teste antigo de aparência ainda procurava “Claro suave”. `scripts/check_web_appearance.py` foi atualizado para os 11 temas atuais e executado novamente com sucesso.

O servidor Chrome do Flutter retornou 404 ao servir os recursos locais CanvasKit. Os testes web foram concluídos usando os recursos existentes de `build/web/canvaskit` no navegador isolado do teste. O site publicado não apresentou essa falha de carregamento. O Excel precisou ser validado fora da sessão restrita, com documentos sintéticos, e passou.

## Evidências locais

Logs em `build/system-audit-*`: `flutter-tests.txt`, `chrome-tests.txt`, `python-tests.txt`, `extension-tests.txt`, `extension-browser.txt`, `browser.txt`, `appearance-current.txt`, `files.txt`, `work-selection.txt`, `package.txt`, `loopback.txt`, `excel.txt`, `analysis.txt`, `findings.txt` e `release.txt`.

As duas reproduções diagnósticas em `build/system_audit_findings_test.dart` confirmam os defeitos atuais; não são testes de regressão aprovando uma implementação correta.

Versão pública verificada: `b8351e681e7d4b2c97fb03b03cc0dbda`.
