import 'package:flutter/material.dart';
import '../../../domain/models/project_model.dart';

Future<TaskModel?> chooseCommentPercentageWork(
    BuildContext context, List<TaskModel> tasks) {
  final eligible = tasks
      .where((task) => task.edeskIdTrabalho?.trim().isNotEmpty ?? false)
      .toList();
  if (eligible.length <= 1) return Future.value(eligible.firstOrNull);
  return showDialog<TaskModel>(
      context: context,
      builder: (context) => SimpleDialog(
            title: const Text('Em qual trabalho cadastrar a porcentagem?'),
            children: [
              for (final task in eligible)
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, task),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                            '${task.stage} · Trabalho ${task.edeskIdTrabalho}'))),
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar')),
            ],
          ));
}
