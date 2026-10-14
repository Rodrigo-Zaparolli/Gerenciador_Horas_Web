# Utilizar no navegador

O aplicativo mantém Flutter e o Firebase configurado em `lib/firebase_options.dart`.
Não é necessário instalar o aplicativo Windows para acessar o site.

## Abrir a versão pronta neste computador

Na pasta do projeto, execute:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start_web.ps1
```

Abra `http://localhost:8080`. O servidor serve somente `build/web`, sem expor o
restante do projeto. Use `-Port 8081` para trocar a porta e Ctrl+C para encerrar.
Para recompilar antes de abrir, acrescente `-Build`. O script usa o Python incluído
no projeto, quando disponível, ou o Python instalado na máquina.

Para desenvolver com recarga automática:

```bash
flutter run -d chrome
```

## Recursos

| Recurso | Comportamento na web |
| --- | --- |
| Login, cadastro e recuperação de senha | Firebase Authentication |
| Projetos, tarefas, horas, métricas, orientações e comentários | Dados do usuário no Firestore |
| Cronômetro | Continua ao trocar de seção; recupera a sessão ao atualizar a mesma aba |
| Importar modelos e checklists | Seleciona arquivos JSON pelo navegador |
| Exportar modelos e checklists | Baixa arquivos JSON pelo navegador |
| PDF e impressão | Usa o diálogo do navegador |
| Imagens e foto de perfil | Seleção de arquivo; colagem depende da permissão do navegador |
| Arquivos e pastas | Links HTTP/HTTPS compartilhados ou anexos no Storage configurado |
| Prévia Excel nos comentários | Seleção local XLSX, sem Python; também lê anexos do Storage habilitado |
| E-Desk | Abre em nova aba; automações usam o serviço local ou um servidor remoto configurado |

A prévia XLSX desenha os valores das células, sem executar macros ou recalcular
fórmulas e sem reproduzir toda a formatação do Excel desktop. Limites: arquivo de
25 MB, intervalo de 40 linhas, 20 colunas e 600 células. O arquivo selecionado para
a prévia fica apenas na memória do modal; a imagem inserida é salva no comentário.
Use o nome da aba no intervalo, por exemplo `Dados!A1:D10`.

O cronômetro usa horários reais para contabilizar períodos em que a aba fica em
segundo plano. Sua recuperação usa `sessionStorage`, separado por usuário, e
depende de o navegador permitir armazenamento. Finalize ou pause antes de fechar
a aba ou sair da conta. A recuperação não sincroniza cronômetros entre dispositivos.

Caminhos de projetos antigos, como `C:\Projetos\...`, são preservados enquanto
o campo não for alterado. O navegador não pode abri-los; substitua por um link
compartilhado ou selecione um anexo. Limpar o campo remove a referência ao salvar.

## Publicar os arquivos estáticos

```bash
flutter build web --release --no-web-resources-cdn
firebase deploy --only hosting --project gerenciador-horas
```

O pacote é gerado em `build/web`. A configuração `firebase.json` atende a navegação
pelo `index.html` e permite revalidar os arquivos após novas publicações. O renderizador
é servido junto com o site usando `--no-web-resources-cdn`.

Endereço do projeto: https://gerenciador-horas.web.app. Em 08/10/2026, a consulta
somente de leitura confirmou `billingEnabled: false`. A publicação usa apenas
Hosting, sem habilitar faturamento, Storage ou servidor na nuvem. As cotas
gratuitas continuam sujeitas aos limites do Firebase.

A publicação não é feita pelo script local. Confirme que o domínio utilizado está
autorizado no Firebase Authentication e que as regras atuais do Firestore permitem
ao usuário acessar seus documentos em `users/{uid}`. O login e as alterações reais
nos dados precisam ser validados com uma conta do projeto.

## Ativar anexos persistentes

Configure um bucket Firebase Storage e suas permissões antes de habilitar a opção.
O código não ativa serviços ou faturamento automaticamente.

```bash
firebase deploy --only storage --project gerenciador-horas
flutter build web --release --no-web-resources-cdn --dart-define=PROJECT_STORAGE_ENABLED=true
```

As regras em `storage.rules` restringem os anexos ao usuário proprietário, aos
formatos permitidos e ao limite de 25 MB. Com a opção ativa, os formulários enviam
arquivos e vinculam pastas de anexos; a pasta permite listar, enviar e baixar arquivos.
Sem a opção, os campos aceitam links externos compartilhados e a prévia Excel
continua disponível por seleção local.

## Integração E-Desk neste computador, sem servidor pago

No modal de edição, marque uma ou várias fases nas caixas de seleção. No botão
`Enviar fases ao E-Desk`, escolha `Enviar todas as fases` ou `Enviar selecionadas`.
Cada opção mostra a quantidade enviada; o envio selecionado fica indisponível
quando nenhuma fase estiver marcada. A seleção vale somente enquanto o modal
estiver aberto e não muda os dados das etapas.

O site utiliza por padrão `http://127.0.0.1:8765` para executar horas, comentários
e fases no mesmo computador em que o navegador está aberto. A integração exige
internet para acessar o E-Desk e validar o login Firebase. Não exige credenciais
administrativas do Firebase, túnel público ou habilitação de faturamento.

Abra `Iniciar integração E-Desk.cmd` na pasta do projeto. O serviço fica em
segundo plano até ser encerrado ou até desligar o computador. Após reiniciar o
Windows, abra o atalho novamente. Para encerrar, use `Parar integração E-Desk.cmd`.
O serviço atende somente neste computador. Outro computador Windows precisa de
sua própria instalação. O celular pode acessar o app, mas não usa esta integração.

No Chrome, permita o acesso à rede local quando o site solicitar. Se negar,
altere essa permissão nas configurações do site. O app continua exigindo seu
login e as credenciais E-Desk configuradas na interface. Uma operação é executada
por vez. Não repita um envio sem conferir o resultado no E-Desk se houver timeout.

A integração local abre uma janela visível do Chromium para acompanhar o envio.
Se o login automático não concluir, faça o login nessa janela para a automação
continuar. Ela fecha ao terminar. A versão em servidor remoto continua sem janela.

Os componentes já foram instalados neste computador. Em outra instalação:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install_edesk_local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start_edesk_local.ps1
```

Registros do serviço: `build/edesk-local`. As solicitações, credenciais e perfis
da automação são temporários e removidos após cada execução. Os testes do
serviço usam dados simulados e não registram horas ou alterações reais.

## Utilizar servidor remoto de automações E-Desk

Disponibilize o servidor de `cloud_run/main.py`, com os scripts Python, Playwright
e validação de tokens do mesmo projeto Firebase. Há um `Dockerfile` para preparar
o serviço. O navegador envia o token Firebase e as credenciais E-Desk informadas
para essa execução ao servidor configurado.

```bash
flutter build web --release --no-web-resources-cdn --dart-define=EDESK_API_URL=https://seu-servidor.example.com
```

É possível combinar `EDESK_API_URL` e `PROJECT_STORAGE_ENABLED` na mesma compilação.
No script local, use `-Build -Storage -EdeskApiUrl https://seu-servidor.example.com`.
O servidor deve permitir a origem do site em `EDESK_API_ORIGINS`. URLs remotas devem
usar HTTPS; HTTP só é aceito em localhost e 127.0.0.1 para desenvolvimento.
Sem uma URL remota, as automações usam o serviço local em `127.0.0.1:8765`.

## Conferência, andamento e proteção contra duplicidade

O ícone de corrente no cabeçalho indica a conexão com a integração local.
Clique nele para verificar novamente ou consultar as instruções de inicialização.
Antes de enviar horas, fases ou comentários, o app mostra os dados para confirmação.
Durante a execução, exibe a abertura do E-Desk, o login e o envio conforme os eventos
da automação, sem estimar percentuais de conclusão.

Cada intervalo de horas fica identificado por conta, solicitação, trabalho, data,
início, fim e tipo. Alterar o comentário não permite reenviar uma hora já confirmada.
O histórico fica em `.edesk-local/history.sqlite3`, fora da pasta de compilação,
e permanece após reiniciar o serviço. Horas repetidas na mesma seleção são recusadas.

Uma resposta HTTP 200 não confirma, sozinha, a persistência. A confirmação automática
exige uma nova linha correspondente na tabela de tempos do E-Desk. Se essa tabela
não estiver disponível, a hora fica pendente de conferência. Na próxima revisão,
abra o E-Desk e marque as horas já registradas, individualmente ou em conjunto.
Autorize nova tentativa somente para as horas incertas que verificou não terem sido
registradas. Horas confirmadas são ignoradas; as ainda não tentadas continuam disponíveis.

O histórico cobre os envios feitos a partir desta atualização neste computador.
Lançamentos anteriores podem ser marcados como já registrados na revisão.
Ao mudar de computador, restaure um backup que inclua esse histórico.

## Backup e restauração

No menu do perfil, selecione **Backup e restauração**. O arquivo JSON inclui projetos
ativos e concluídos, horas, comentários, modelos, métricas, orientações e configurações.
Datas e tipos do Firestore são preservados. Senhas, tokens e credenciais são excluídos.
Anexos externos são referências: guarde também os arquivos originais.

Para incluir o histórico local de envios, mantenha a integração E-Desk ativa durante
a exportação. Se estiver desligada, o backup dos dados da conta continua disponível
e o app informa que o histórico local não foi incluído.

A restauração valida o arquivo inteiro e a conta antes de alterar dados. A interface
mostra a quantidade de registros e pede confirmação; exporta os dados atuais antes
de restaurar. Registros com os mesmos IDs são atualizados e outros registros são
preservados. Em falha parcial, informa o progresso e permite repetir com os mesmos
IDs. Recarregue o aplicativo após a conclusão. Para restaurar um arquivo com histórico
E-Desk, a integração precisa estar ativa e sem envio em andamento.

## Testes

```bash
flutter test --no-pub
flutter test --no-pub --platform chrome test/web_features_test.dart test/widget_test.dart test/edesk_web_client_test.dart
```

Os testes verificam login em janela estreita, prévia XLSX sem Firebase, validação de
links, recuperação do cronômetro e requisições ao servidor E-Desk com transporte simulado.
Não enviam comentários, horas ou alterações a contas E-Desk reais.
