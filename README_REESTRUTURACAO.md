# Reestruturação do Gerenciador de Horas

Esta versão reorganiza o projeto por responsabilidade e mantém as telas existentes.

## Estrutura principal

- `lib/app/`: inicialização do aplicativo e navegação principal.
- `lib/core/`: configurações centrais, como tema.
- `lib/domain/models/`: modelos de domínio e estado compartilhado.
- `lib/data/services/`: serviços de acesso a dados.
- `lib/shared/widgets/`: widgets compartilhados entre telas.
- `lib/features/dashboard/`: dashboard e seus componentes visuais.
- `lib/features/projects/`: diálogos, widgets e telas relacionadas a projetos.
- `lib/features/work_formats/`: cadastro/modelos de trabalho.
- `lib/features/metrics/`: métricas.
- `lib/features/completed_projects/`: projetos finalizados.
- `lib/features/orientations/`: orientações.
- `lib/features/tasks/`: tarefas executadas.

## Principal refatoração

O antigo `dashboard_screen.dart` tinha mais de 3.500 linhas. A montagem visual do dashboard foi separada em:
- ControleProjetosWidget
- ProgressoProjetoWidget
- GraficoHorasWidget
- TabelaProjetosWidget
- CentralAlertasWidget

O estado e as regras de negócio continuam no DashboardScreen para reduzir o risco de alterar o comportamento existente.

## Observação

O ambiente desta execução não possui Flutter/Dart SDK, então não foi possível executar `flutter analyze` ou `flutter test`. A estrutura foi validada por inspeção dos imports e balanceamento sintático básico.
