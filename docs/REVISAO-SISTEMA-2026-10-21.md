# Revisão do sistema — 21/10/2026

Revisão do aplicativo web, integração local, empacotamento e regras de acesso aos dados. A revisão combina análise estática de todos os fontes da aplicação com testes automatizados e verificações em navegador. Não representa uma garantia de ausência de falhas em todos os ambientes.

## Correções

- **Movimentação interrompida:** uma tentativa que falhava antes de remover um destino vazio podia impedir uma nova conferência. Agora é preparado um novo plano, sem mover durante a conferência. Destinos com arquivos continuam bloqueados.
- **Pasta inteira:** a recuperação de uma tentativa anterior que selecionava apenas `Documentos` podia devolver esse plano mesmo após selecionar a pasta principal. Agora a nova seleção é respeitada e o plano anterior é invalidado. Também foi corrigida a busca da tentativa correspondente quando houve destinos diferentes.
- **Comentários:** proteção contra exclusões simultâneas e contra atualização de controles depois de fechar o modal durante a exclusão.
- **Painel:** retirada uma consulta ao Firestore que carregava uma foto de perfil sem utilização pela tela. A foto exibida pelo cabeçalho continua com seu carregamento próprio.
- **Distribuição:** atualizado o pacote de abertura local, que estava atrasado em relação aos fontes. Seu verificador também foi atualizado para o protocolo e a identidade autenticada atuais. A limpeza da extração temporária tolera bloqueios breves de arquivos pelo Windows.

## Limpeza

Removidos dez arquivos sem importações, exports, parts ou importações condicionais no aplicativo, testes e fixtures:

```
lib/tema/tema_app.dart
lib/data/repositories/edesk_repository.dart
lib/domain/models/service_type_model.dart
lib/domain/models/time_log_model.dart
lib/features/checklist_formats/dialogs/checklist_model_dialog.dart
lib/features/projects/dialogs/checklist_project_dialog.dart
lib/features/projects/screens/work_hour.dart
lib/features/projects/widgets/browser_folder_dialog.dart
lib/features/projects/widgets/project_controls_panel.dart
lib/shared/widgets/about_dialog_widget.dart
```

Também foram removidas 35 funções sem uso e uma imagem gerada de depuração, `edesk_bot/debug/excel_preview.png`. A pasta de depuração passou a ser ignorada pelo Git. Foi retirada uma pasta vazia na raiz.

Removidos 43 arquivos `.pyc` gerados nos diretórios de fontes e testes (759.647 bytes). Eles são recriados automaticamente quando necessários. O cache do runtime, os registros da integração e os arquivos de compilação úteis para diagnóstico foram preservados.

Aplicadas correções mecânicas de blocos condicionais, imports, anotações, variáveis redundantes e mensagens de diagnóstico. Os diagnósticos de elementos sem uso e expressões regulares foram reativados no analisador. As exceções documentadas para doubles do Firestore ficam somente nos dois arquivos de teste que os implementam.

Cópias locais dos fontes removidos e anteriores à limpeza estão em `build/full-audit-removed-sources`, `build/full-audit-before-declarations` e `build/full-audit-before-cascade`. Essas cópias não são publicadas. Os manifests da limpeza ficam em `build/full-audit-*.json`.

Foram preservados bancos de vínculos, credenciais, sessões do navegador, pastas e planilhas reais, runtimes, arquivos de plataforma e downloads históricos com URLs já distribuídas. O projeto executável separado não foi alterado.

## Validações

| Verificação | Resultado |
| --- | --- |
| Análise de `lib`, `test` e fixtures Dart | Nenhum diagnóstico; código de saída 0 |
| Suíte Flutter completa | 536 testes passaram; os 5 específicos da web foram cobertos no Chrome |
| Integração Python | 129 testes passaram, incluindo 4 novos casos de recuperação da movimentação |
| JavaScript | 7 testes passaram |
| Colagem e imagens no Chrome | 10 testes passaram |
| Regressão após retirar os auxiliares antigos | 71 testes passaram; o caso específico de navegador foi coberto no Chrome |
| Regras Firestore locais e publicadas | 49 casos passaram em cada versão, sem modificar documentos |
| Integridade de fontes | Sintaxe Python, JavaScript, PowerShell e JSON; imports Dart existentes |
| Dependências Python instaladas | `pip check` sem conflitos |
| Horas em navegador simulado | Seleção exata do trabalho, abertura do retroativo e lotes sequenciais |
| Comentário e porcentagem simulados | Recuperação após fechar janelas, trabalho correto, gravação única e conferência após recarregar |
| Arquivos no navegador | Persistência, cancelamento, isolamento de contas e rejeição de caminhos indevidos |
| Planilha real em cópia descartável | Lista de abas, leitura, prévia e gravação; VBA preservado e hash do original inalterado |
| Pacotes extraídos | Integração completa v35 e abertura local: runtime, dependências e APIs protegidas |
| Compilação release | Build web concluído e manifesto conferido |
| Interface compilada | Login, cadastro e 11 temas em 1440×900 e 390×844; sem erros JavaScript, com preferência e texto preservados |

Os testes Chrome precisaram receber os arquivos CanvasKit do SDK local por uma rota temporária de teste: o servidor de testes do Flutter instalado usa um prefixo de caminho incompatível com Windows e retornava 404. Não houve alteração no SDK nem no código da aplicação para contornar isso. A versão release utiliza os recursos locais incluídos na compilação.

## Repetir a revisão

Na raiz do projeto:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_system.ps1
```

Para acrescentar os cenários Playwright isolados de horas, comentário, porcentagem e arquivos:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_system.ps1 -Browser
```

O comando registra o resultado e o código de saída de cada etapa em `build/system-check-DATA-HORA/results.json`, continua as outras verificações quando uma falha e retorna erro se alguma etapa não passar. Precisa do SDK Flutter, Node e do Python da integração. Não envia registros ao E-Desk real.

## Limite da validação

Os testes de envio usam páginas e respostas simuladas. A confirmação ponta a ponta no E-Desk real, com a conta do usuário e suas solicitações, continua dependendo de um teste no computador que executa a integração. A revisão não cadastrou horas, comentários, fases ou porcentagens reais nem movimentou uma pasta real de cliente.

Para receber as correções, é necessário atualizar e reiniciar a integração v36. As mudanças aparecem nas notas do modal de atualização do app.

## Complemento: conferência dos envios de horas (v36)

A integração recarrega o retroativo e procura cada registro por data, início, fim e tipo, dentro do trabalho validado. Não usa HTTP 200, campos preenchidos ou o texto do histórico como prova de cadastro. Percorre a paginação reconhecida; tabelas ambíguas, incompletas ou filtradas não comprovam ausência.

Após o envio, faz uma nova conferência de todas as horas selecionadas. Para uma hora comprovadamente ausente, faz outra leitura independente e permite uma única nova tentativa quando o POST anterior terminou ou não chegou a ser enviado. Um POST com resposta incerta não é repetido automaticamente. Horas já existentes são preservadas. A nova tentativa não acrescenta a mesma descrição novamente ao histórico.

Quando todas as horas têm comprovantes, a API retorna sucesso mesmo se a limpeza final do navegador falhar. O app usa essa confirmação para apresentar o modal de sucesso. Um progresso de 100% sem comprovantes continua sem confirmar o cadastro.

Validações adicionais: 142 testes Python e 26 testes Flutter do cliente E-Desk e modal de resultado. Cinco cenários Playwright usam a função real de salvamento em páginas isoladas: persistência normal, primeira gravação sem registro seguida de recuperação, fechamento da janela após salvar, tabela paginada e tabela ilegível. Asserções verificam os registros e a quantidade de POSTs para detectar duplicidade. Nenhum envio foi feito ao E-Desk real.

Os instaladores agora têm o número da versão no nome efetivo do arquivo, com redirecionamento dos links antigos e cache desabilitado para downloads.
