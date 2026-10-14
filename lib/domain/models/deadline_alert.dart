import 'project_model.dart';

class DeadlineAlert {
  static List<DeadlineAlert> collect(
      List<ProjectModel> projects, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);

    final List<DeadlineAlert> alertItems = [];

    for (var project in projects) {
      if (project.subTasks != null && project.subTasks!.isNotEmpty) {
        for (var task in project.subTasks!) {
          // Se o status for TRAB_FIM, ignora este item.
          if (task.status == 'TRAB_FIM') {
            continue;
          }

          final planEnd = task.planEnd ?? task.startDate;

          final normalizedEnd =
              DateTime(planEnd.year, planEnd.month, planEnd.day);

          final differenceDays = normalizedEnd.difference(today).inDays;

          // Exibe atrasados ou os que vencem nos próximos 5 dias.
          if (differenceDays <= 5) {
            alertItems.add(
              DeadlineAlert(
                id: project.id,
                id2: task.subId,
                client: project.client,
                serviceType: project.serviceType,
                stage: task.stage,
                planStart: task.planStart ?? task.startDate,
                planEnd: planEnd,
                status: task.status,
                differenceDays: differenceDays,
              ),
            );
          }
        }
      } else {
        // Se o projeto principal estiver concluído, ignora.
        if (project.status == 'TRAB_FIM') {
          continue;
        }

        final planEnd = project.startDate;

        final normalizedEnd =
            DateTime(planEnd.year, planEnd.month, planEnd.day);

        final differenceDays = normalizedEnd.difference(today).inDays;

        if (differenceDays <= 5) {
          alertItems.add(
            DeadlineAlert(
              id: project.id,
              id2: project.id2,
              client: project.client,
              serviceType: project.serviceType,
              stage: project.stage,
              planStart: project.startDate,
              planEnd: planEnd,
              status: project.status,
              differenceDays: differenceDays,
            ),
          );
        }
      }
    }

    // Mais atrasados primeiro.
    alertItems.sort(
      (a, b) => a.differenceDays.compareTo(b.differenceDays),
    );

    return alertItems;
  }

  final String id;
  final String id2;
  final String client;
  final String serviceType;
  final String stage;
  final DateTime planStart;
  final DateTime planEnd;
  final String status;
  final int differenceDays;

  DeadlineAlert({
    required this.id,
    required this.id2,
    required this.client,
    required this.serviceType,
    required this.stage,
    required this.planStart,
    required this.planEnd,
    required this.status,
    required this.differenceDays,
  });
}
