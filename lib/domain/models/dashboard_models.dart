enum TimerState { stopped, running, paused }

class TimeLog {
  String id;
  final String targetId;
  DateTime
      date; // Corrigido para não ser final, permitindo atribuições e uso de setters
  String startTime;
  String endTime;
  String durationFormatted;
  int durationMinutes;
  bool isRegistered;
  String? projectName;
  String? taskName;
  String? typeHs;
  dynamic hours;
  String? description;
  String? projectId;

  TimeLog({
    required this.id,
    required this.targetId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.durationFormatted,
    this.durationMinutes = 0,
    required this.isRegistered,
    this.projectName,
    this.taskName,
    this.typeHs,
    this.hours,
    this.description,
    this.projectId,
  });

  String get dateFormatted => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  set setDurationMinutes(int minutes) {
    durationMinutes = minutes;
  }
}

class FilterOptions {
  DateTime? selectedDate;
  String? serviceType;
  String shift;

  FilterOptions({
    this.selectedDate,
    this.serviceType,
    this.shift = 'Todos',
  });

  bool get hasFilter =>
      selectedDate != null || serviceType != null || shift != 'Todos';

  void clear() {
    selectedDate = null;
    serviceType = null;
    shift = 'Todos';
  }
}
