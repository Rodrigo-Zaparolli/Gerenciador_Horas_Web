# Novo layout do Desempenho mensal

A alteração fica dentro do card **Desempenho mensal**, em Métricas. O cabeçalho anual, a configuração de jornada e a tabela de planejamento foram preservados. A comparação automática com a cópia anterior confirmou que apenas `_buildChartCard` e seu import foram alterados na tela existente.

O card permite selecionar os meses do ano da tela, mostra quatro indicadores mensais, colunas diárias com horas cobradas e demais categorias, detalhes ao passar o mouse/toque, progresso da meta e comparação de horas cobradas com o mês anterior. A média diária considera somente dias com horas trabalhadas. Meses vazios e ausência de meta/base de comparação têm mensagens próprias. As cores personalizadas do gráfico continuam sendo utilizadas.

Os cálculos usam os apontamentos reais e os minutos de duração, preservando pausas e a classificação de tipos antigos. “Demais horas” inclui todas as categorias diferentes de cobradas. A comparação de janeiro considera dezembro do ano anterior, se seus apontamentos estiverem disponíveis.

Validação: 29 testes passaram, incluindo cálculos mensais, classificação antiga e layout nos 11 temas a 360 e 1440 pixels. O componente foi capturado e inspecionado com dados ilustrativos, sem ler ou gravar projetos reais.

## Volta ao layout anterior

A cópia anterior está em `build/backup-desempenho-mensal-20261014/metrics_screen.dart`. Para voltar apenas o card, restaure esse arquivo em `lib/features/metrics/metrics_screen.dart`, compile com `scripts/build_web_release.ps1`, valide e publique somente no Hosting. Isso não restaura dados do Firebase nem altera Orientações ou outras funcionalidades.

O histórico Git também preserva a versão anterior à mudança. A cópia local de segurança não é enviada ao repositório, pois `build` é excluído do Git.

Visão anual compacta: 12 meses com horas cobradas e metas individuais, na coluna da direita sob a meta resumida. Clicar no mês atualiza o detalhe diário. A altura do conjunto foi preservada; nos tamanhos menores, a coluna compacta substitui a antiga meta, sem acrescentar um painel abaixo dela. Backup anterior: build/backup-monthly-before-annual.dart.
