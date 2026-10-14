class ChecklistFormat {
  final String id;
  final String name;
  final List<Map<String, dynamic>> items;

  ChecklistFormat({
    required this.id,
    required this.name,
    required this.items,
  });

  factory ChecklistFormat.fromJson(Map<String, dynamic> json, [String? docId]) {
    var rawItems = json['items'] ?? [];
    List<Map<String, dynamic>> parsedItems = [];

    if (rawItems is List) {
      for (var item in rawItems) {
        if (item is Map) {
          parsedItems.add({
            'order': item['order']?.toString() ?? '',
            'name': item['name']?.toString() ?? '',
            'completed': item['completed'] == true,
          });
        }
      }
    }

    return ChecklistFormat(
      // Prioriza o ID que está dentro do JSON, se não houver, usa o ID do documento do Firestore
      id: json['id']?.toString() ?? docId ?? '',
      name: json['name']?.toString() ?? '',
      items: parsedItems,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'items': items,
    };
  }
}
