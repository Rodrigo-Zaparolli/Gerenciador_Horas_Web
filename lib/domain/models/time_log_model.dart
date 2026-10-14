import 'package:cloud_firestore/cloud_firestore.dart';

class TimeLogModel {
  final String id;
  final double hours;
  final String description;
  final DateTime createdAt;

  TimeLogModel({
    required this.id,
    required this.hours,
    required this.description,
    required this.createdAt,
  });

  factory TimeLogModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TimeLogModel(
      id: doc.id,
      hours: (data['hours'] ?? 0.0).toDouble(),
      description: data['description'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hours': hours,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
