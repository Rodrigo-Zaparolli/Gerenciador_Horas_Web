import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../domain/models/dashboard_models.dart';
import '../../../domain/models/monthly_hours.dart';
import 'grafico_horas_widget.dart';

class MonthlyHoursChart extends StatefulWidget {
  const MonthlyHoursChart(
      {super.key,
      required this.logs,
      required this.points,
      required this.formatHours,
      this.onDayTap});
  final List<TimeLog> logs;
  final List<DailyHoursPoint> points;
  final String Function(double) formatHours;
  final ValueChanged<DateTime>? onDayTap;
  @override
  State<MonthlyHoursChart> createState() => _MonthlyHoursChartState();
}

class _MonthlyHoursChartState extends State<MonthlyHoursChart> {
  String? subscriptionKey;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? goalsStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? preferencesStream;
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final now = DateTime.now();
    Widget chart(MonthlyHours? monthly) => GraficoHorasWidget(
        points: widget.points,
        formatHours: widget.formatHours,
        onDayTap: widget.onDayTap,
        monthly: monthly,
        monthlyWorked: MonthlyHours.workedInMonth(now, widget.logs));
    if (uid == null) return chart(null);
    final user = FirebaseFirestore.instance.collection('users').doc(uid);
    final key = '$uid/${now.year}';
    if (subscriptionKey != key) {
      subscriptionKey = key;
      goalsStream =
          user.collection('metrics').doc('yearly_${now.year}').snapshots();
      preferencesStream =
          user.collection('metrics_preferences').doc('config').snapshots();
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        key: ValueKey(key),
        stream: goalsStream,
        builder: (context, goals) =>
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                key: ValueKey(uid),
                stream: preferencesStream,
                builder: (context, preferences) => chart(goals.hasError ||
                        preferences.hasError ||
                        !goals.hasData ||
                        !preferences.hasData
                    ? null
                    : MonthlyHours.calculate(
                        now,
                        widget.logs,
                        goals.data!.data() ?? {},
                        preferences.data!.data() ?? {}))));
  }
}
