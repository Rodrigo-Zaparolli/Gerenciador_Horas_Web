class WorkFormat {
  final String id;
  final String name;
  final List<dynamic> steps;

  WorkFormat({
    required this.id,
    required this.name,
    this.steps = const [],
  });

  int get workCount => steps.length;

  factory WorkFormat.fromMap(Map<String, dynamic> map) {
    final dynamic rawSteps = map['steps'];

    List<dynamic> parsedSteps = [];

    if (rawSteps is List) {
      parsedSteps = rawSteps.map((step) {
        if (step is Map) {
          return Map<String, dynamic>.from(step);
        }

        return step.toString();
      }).toList();
    }

    return WorkFormat(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      steps: parsedSteps,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'steps': steps.map((step) {
        if (step is Map) {
          return Map<String, dynamic>.from(step);
        }

        return step.toString();
      }).toList(),
    };
  }
}
