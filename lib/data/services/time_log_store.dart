import 'package:gerenciador_horas/domain/models/history_period.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';

class TimeLogStore extends ChangeNotifier {
  TimeLogStore({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  List<TimeLog> _logs = [];

  List<TimeLog> get logs => List.unmodifiable(_logs);

  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _subscriptions = {};

  String? _subscriptionOwner;
  int _subscriptionGeneration = 0;
  Set<String> _activeProjectIds = {};
  final _querySignatures = <String, String>{};
  final _legacyDateProjects = <String>{};
  final _fullyLoadedProjects = <String>{};
  Set<String> _completedProjectIds = {};
  Timer? _scopeRefresh;
  HistoryPeriod? _historyPeriod;
  int lastSubscriptionChanges = 0;
  Object? loadError;
  bool _disposed = false;
  Future<void> setHistoryPeriod(DateTime? start, DateTime? end) async {
    final next = start != null && end != null ? HistoryPeriod(start, end) : null;
    if (next?.signature == _historyPeriod?.signature) return;
    _historyPeriod = next;
    await startListeningToProjects(_activeProjectIds.toList());
  }
  Future<void> retryListening() async {
    loadError = null;
    await stopListening();
    await startListeningToProjects(_activeProjectIds.toList());
  }

  String? get _userId => _auth.currentUser?.uid;

  /// Fresh server reads, independent of the history/search currently displayed.
  /// Any failed query aborts the preparation instead of sending a partial day.
  Future<List<TimeLog>> loadRegisteredDay(DateTime day) async {
    final uid = _userId;
    if (uid == null || _disposed) throw StateError('Entre novamente no app.');
    void checkOwner() {
      if (_disposed || uid != _userId) {
        throw StateError('A conta foi alterada. Prepare o envio novamente.');
      }
    }
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final user = _firestore.collection('users').doc(uid);
    final collections = await Future.wait([
      user.collection('projects').get(const GetOptions(source: Source.server)),
      user.collection('completed_projects').get(const GetOptions(source: Source.server)),
    ]).timeout(const Duration(seconds: 20));
    checkOwner();
    final ids = <String>{
      ...collections[0].docs.map((doc) => doc.id),
      ...collections[1].docs.map((doc) => (doc.data()['id']?.toString().trim().isNotEmpty ?? false)
          ? doc.data()['id'].toString().trim() : doc.id),
      if (_subscriptionOwner == uid) ..._activeProjectIds,
    }.toList()..sort();
    final result = <TimeLog>[];
    for (var offset = 0; offset < ids.length; offset += 6) {
      final batch = ids.skip(offset).take(6);
      final parts = await Future.wait(batch.map((id) async {
        Query<Map<String, dynamic>> query = user.collection('projects').doc(id).collection('time_logs');
        if (_subscriptionOwner == uid && _fullyLoadedProjects.contains(id) && !_legacyDateProjects.contains(id)) {
          query = query.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
              .where('date', isLessThan: Timestamp.fromDate(end));
        }
        final snapshot = await query.get(const GetOptions(source: Source.server));
        checkOwner();
        // A missing date must never silently become "today" for a send.
        return snapshot.docs.where((doc) => doc.data()['date'] is Timestamp || doc.data()['createdAt'] is Timestamp)
            .map((doc) => _timeLogFromDocument(id, doc))
            .where((log) => log.isRegistered && !log.date.isBefore(start) && log.date.isBefore(end)).toList();
      })).timeout(const Duration(seconds: 20));
      checkOwner();
      result.addAll(parts.expand((part) => part));
    }
    result.sort((a, b) => a.startTime.compareTo(b.startTime));
    return result;
  }

  // ============================================================
  // AUXILIAR: IDENTIFICA O ID DO PROJETO DE UM LOG
  // ============================================================

  String _getProjectIdFromLog(TimeLog log) {
    final targetId = log.targetId.trim();

    if (targetId.isEmpty) {
      return '';
    }

    return targetId.split('_').first.trim();
  }

  // ============================================================
  // AUXILIAR: CONVERTE "HH:MM" PARA MINUTOS
  // ============================================================

  int _timeToMinutes(String timeStr) {
    try {
      final parts = timeStr.trim().split(':');

      if (parts.length == 2) {
        final hours = int.tryParse(parts[0]) ?? 0;
        final minutes = int.tryParse(parts[1]) ?? 0;

        return (hours * 60) + minutes;
      }

      if (parts.length == 1) {
        final val = double.tryParse(
              parts[0].replaceAll(',', '.'),
            ) ??
            0.0;

        return (val * 60).round();
      }
    } catch (_) {}

    return 0;
  }

  // ============================================================
  // AUXILIAR: CONVERTE MINUTOS PARA "HH:MM"
  // ============================================================

  String _minutesToTime(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // AUXILIAR: CONVERTE DURAÇÃO "HH:MM" PARA HORAS DECIMAIS
  //
  // Exemplos:
  // 01:00 -> 1.0
  // 01:20 -> 1.333333
  // 01:30 -> 1.5
  // 02:30 -> 2.5
  // ============================================================

  double? _durationToHours(String duration) {
    final value = duration.trim();

    if (value.isEmpty) {
      return null;
    }

    try {
      final parts = value.split(':');

      if (parts.length == 2) {
        final hours = int.tryParse(parts[0].trim());
        final minutes = int.tryParse(parts[1].trim());

        if (hours != null && minutes != null) {
          return hours + (minutes / 60.0);
        }
      }

      final decimal = double.tryParse(
        value.replaceAll(',', '.'),
      );

      return decimal;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // AUXILIAR: OBTÉM HORAS DE FORMA SEGURA
  // ============================================================

  double? _resolveHours({
    required dynamic rawHours,
    required String durationFormatted,
  }) {
    // ------------------------------------------------------------
    // 1. Primeiro tenta o campo "hours"
    // ------------------------------------------------------------

    if (rawHours is num) {
      return rawHours.toDouble();
    }

    final rawHoursString = rawHours?.toString().trim() ?? '';

    if (rawHoursString.isNotEmpty) {
      final parsed = double.tryParse(
        rawHoursString.replaceAll(',', '.'),
      );

      if (parsed != null) {
        return parsed;
      }
    }

    // ------------------------------------------------------------
    // 2. Se "hours" não existe, usa durationFormatted
    // ------------------------------------------------------------

    final calculatedHours = _durationToHours(
      durationFormatted,
    );

    if (calculatedHours != null) {
      return calculatedHours;
    }

    return null;
  }

  // ============================================================
  // MÉTODOS DE METAS ANUAIS E MENSAIS
  // ============================================================

  Future<Map<String, dynamic>?> carregarMetasAnuais(int ano) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      return null;
    }

    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('metrics')
          .doc('yearly_$ano')
          .get();

      return doc.data();
    } catch (e) {
      debugPrint('Erro ao carregar metas anuais: $e');
      return null;
    }
  }

  Future<void> salvarMetaMensal(
    int ano,
    String mesIndex,
    String valor,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      return;
    }

    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('metrics')
          .doc('yearly_$ano');

      final docSnapshot = await docRef.get();

      final Map<String, dynamic> dadosAtuais = docSnapshot.data() ?? {};

      dadosAtuais[mesIndex] = valor;

      int totalMinutesSum = 0;

      final List<String> mesesValidos = [
        '0',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '10',
        '11',
        '12',
        'janeiro',
        'fevereiro',
        'março',
        'abril',
        'maio',
        'junho',
        'julho',
        'agosto',
        'setembro',
        'outubro',
        'novembro',
        'dezembro',
      ];

      dadosAtuais.forEach((key, val) {
        if (mesesValidos.contains(key.toLowerCase())) {
          final timeStr = val?.toString() ?? '00:00';

          totalMinutesSum += _timeToMinutes(timeStr);
        }
      });

      final String totalFormatado = _minutesToTime(totalMinutesSum);

      await docRef.set(
        {
          mesIndex: valor,
          'totalAnual': totalFormatado,
        },
        SetOptions(merge: true),
      );

      notifyListeners();
    } catch (e) {
      debugPrint(
        'Erro ao salvar meta mensal e atualizar total: $e',
      );
    }
  }

  Future<void> salvarMetasAnuaisCompleta(
    int ano,
    Map<String, dynamic> metasMensais,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Usuário não autenticado.');
    }

    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('metrics')
          .doc('yearly_$ano');

      int totalMinutesSum = 0;

      final List<String> mesesValidos = [
        '0',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '10',
        '11',
        '12',
        'janeiro',
        'fevereiro',
        'março',
        'abril',
        'maio',
        'junho',
        'julho',
        'agosto',
        'setembro',
        'outubro',
        'novembro',
        'dezembro',
      ];

      metasMensais.forEach((key, val) {
        if (mesesValidos.contains(key.toLowerCase())) {
          final timeStr = val?.toString() ?? '00:00';

          totalMinutesSum += _timeToMinutes(timeStr);
        }
      });

      final String totalFormatado = _minutesToTime(totalMinutesSum);

      final Map<String, dynamic> dadosCompletos = {
        ...metasMensais,
        'totalAnual': totalFormatado,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await docRef.set(
        dadosCompletos,
        SetOptions(merge: true),
      );

      notifyListeners();
    } catch (e) {
      debugPrint(
        'Erro ao salvar o conjunto completo de métricas anuais: $e',
      );

      rethrow;
    }
  }

  // ============================================================
  // CONVERTER DOCUMENTO FIRESTORE EM TIMELOG
  // ============================================================

  TimeLog _timeLogFromDocument(
    String projectId,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    DateTime date = DateTime.now();

    final dynamic dateValue = data['date'];
    if (dateValue is! Timestamp) _legacyDateProjects.add(projectId);
    final dynamic createdAt = data['createdAt'];

    if (dateValue is Timestamp) {
      date = dateValue.toDate();
    } else if (createdAt is Timestamp) {
      date = createdAt.toDate();
    }

    final String targetId = data['targetId']?.toString().trim() ?? projectId;

    final String durationFormatted =
        data['durationFormatted']?.toString().trim() ?? '';

    final String startTime = data['startTime']?.toString().trim() ?? '';

    final String endTime = data['endTime']?.toString().trim() ?? '';

    final String description = data['description']?.toString() ?? '';

    final bool isRegistered = data['isRegistered'] == true;

    // ==========================================================
    // CORREÇÃO PRINCIPAL
    //
    // Se "hours" estiver null, calcula através de
    // "durationFormatted".
    // ==========================================================

    final double? hours = _resolveHours(
      rawHours: data['hours'],
      durationFormatted: durationFormatted,
    );

    final log = TimeLog(
      id: doc.id,
      targetId: targetId.isNotEmpty ? targetId : projectId,
      hours: hours,
      description: description,
      isRegistered: isRegistered,
      date: date,
      startTime: startTime,
      endTime: endTime,
      durationFormatted: durationFormatted,
      projectName: data['projectName']?.toString(),
      taskName: data['taskName']?.toString(),
      typeHs: data['typeHs']?.toString(),
    );

    debugPrint(
      'TimeLogStore: TimeLog convertido | '
      'id=${log.id} | '
      'projectId=$projectId | '
      'targetId=${log.targetId} | '
      'hours=${log.hours} | '
      'duration=${log.durationFormatted} | '
      'start=${log.startTime} | '
      'end=${log.endTime} | '
      'registered=${log.isRegistered}',
    );

    return log;
  }

  // ============================================================
  // BUSCAR TAMBÉM OS PROJETOS FINALIZADOS
  // ============================================================

  Future<Set<String>> _getCompletedProjectIds() async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      return <String>{};
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('completed_projects')
          .get();
      if (userId != _userId) return {};

      _completedProjectIds = snapshot.docs
          .map((doc) {
            final data = doc.data();

            final String id = data['id']?.toString().trim() ?? '';

            if (id.isNotEmpty) {
              return id;
            }

            return doc.id.trim();
          })
          .where((id) => id.isNotEmpty)
          .toSet();
      return _completedProjectIds;
    } catch (e) {
      debugPrint(
        'TimeLogStore: erro ao buscar projetos finalizados: $e',
      );

      loadError = e;
      return _completedProjectIds;
    }
  }

  // ============================================================
  // INICIAR ESCUTA DOS LOGS DOS PROJETOS
  // ============================================================

  Future<void> startListeningToProjects(
    List<String> projectIds,
  ) async {
    if (_disposed) return;
    final generation = ++_subscriptionGeneration;
    final userId = _userId;
    if (_subscriptionOwner != userId) {
      await stopListening();
      _logs = [];
      _legacyDateProjects.clear();
      _fullyLoadedProjects.clear();
      _completedProjectIds = {};
      _subscriptionOwner = userId;
    }

    if (userId == null || userId.trim().isEmpty) {
      debugPrint(
        'TimeLogStore: usuário não autenticado.',
      );
      return;
    }

    final Set<String> ids =
        projectIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();

    _activeProjectIds = projectIds.toSet();
    final completedProjectIds = await _getCompletedProjectIds();

    if (_disposed || generation != _subscriptionGeneration || userId != _userId) return;
    _activeProjectIds = projectIds.toSet();
    ids.addAll(completedProjectIds);
    final desired = <String, String>{
      for (final id in ids) id: _legacyDateProjects.contains(id) || !_fullyLoadedProjects.contains(id) ? 'all' : _historyPeriod?.signature ?? 'all'
    };
    final changes = SubscriptionChanges(_querySignatures, desired);
    lastSubscriptionChanges = changes.add.length;
    for (final id in changes.remove) {
      final old = _subscriptions.remove(id);
      _querySignatures.remove(id);
      await old?.cancel();
      if (generation != _subscriptionGeneration) return;
    }
    _logs.removeWhere((log) => !ids.contains(_getProjectIdFromLog(log)));

    debugPrint(
      'TimeLogStore: iniciando escuta de '
      '${ids.length} projetos '
      '(${completedProjectIds.length} finalizados).',
    );

    for (final id in changes.add) {
      final period = _legacyDateProjects.contains(id) || !_fullyLoadedProjects.contains(id) ? null : _historyPeriod;
      Query<Map<String, dynamic>> query = _firestore.collection('users').doc(userId).collection('projects').doc(id).collection('time_logs');
      if (period != null) {
        query = query.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(period.start))
            .where('date', isLessThan: Timestamp.fromDate(period.endExclusive));
      }
      final signature = desired[id]!;
      _querySignatures[id] = signature;
      _subscriptions[id] = query.snapshots().listen((snapshot) {
        if (_disposed || _userId != userId || _querySignatures[id] != signature) return;
        _replaceProjectLogs(projectId: id, snapshot: snapshot, period: period);
        if (period == null) {
          _fullyLoadedProjects.add(id);
          if (_historyPeriod != null && !_legacyDateProjects.contains(id)) {
            _scopeRefresh?.cancel();
            _scopeRefresh = Timer(const Duration(milliseconds: 250), () {
              if (!_disposed) unawaited(startListeningToProjects(_activeProjectIds.toList()));
            });
          }
        }
      }, onError: (Object error) {
        if (_disposed || _userId != userId) return;
        loadError = error;
        notifyListeners();
      });
    }
    debugPrint('TimeLogStore: $lastSubscriptionChanges subscriptions refreshed, period=${_historyPeriod?.signature ?? "all"}');
  }

  // ============================================================
  // SUBSTITUIR OS LOGS DE UM PROJETO
  // ============================================================

  void _replaceProjectLogs({
    required String projectId,
    required QuerySnapshot<Map<String, dynamic>> snapshot,
    HistoryPeriod? period,
  }) {
    final otherLogs = _logs.where(
      (log) {
        final baseProjectId = _getProjectIdFromLog(log);

        return baseProjectId != projectId || (period != null && (!period.contains(log.date) || _legacyDateProjects.contains(projectId)));
      },
    ).toList();

    final projectLogs = snapshot.docs
        .map(
          (doc) => _timeLogFromDocument(
            projectId,
            doc,
          ),
        )
        .toList();

    projectLogs.sort(
      (a, b) => b.date.compareTo(a.date),
    );

    _logs = [
      ...otherLogs,
      ...projectLogs,
    ];

    _logs.sort(
      (a, b) => b.date.compareTo(a.date),
    );

    notifyListeners();
  }

  // ============================================================
  // CARREGAR LOGS DE UM PROJETO IMEDIATAMENTE
  // ============================================================

  Future<void> _loadProjectLogsIntoMemory(
    String projectId,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      return;
    }

    final id = projectId.trim();

    if (id.isEmpty) {
      return;
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('projects')
          .doc(id)
          .collection('time_logs')
          .get();

      final projectLogs = snapshot.docs
          .map(
            (doc) => _timeLogFromDocument(
              id,
              doc,
            ),
          )
          .toList();

      final otherLogs = _logs.where(
        (log) {
          return _getProjectIdFromLog(log) != id;
        },
      ).toList();

      _logs = [
        ...otherLogs,
        ...projectLogs,
      ];

      _logs.sort(
        (a, b) => b.date.compareTo(a.date),
      );

      notifyListeners();
    } catch (e) {
      debugPrint(
        'Erro ao carregar logs do projeto $id: $e',
      );
    }
  }

  // ============================================================
  // STREAM INDIVIDUAL DE UM PROJETO
  // ============================================================

  Stream<List<TimeLog>> streamProjectTimeLogs(
    String userId,
    String projectId,
  ) {
    final uid = userId.trim();
    final id = projectId.trim();

    if (uid.isEmpty || id.isEmpty) {
      debugPrint(
        'TimeLogStore: streamProjectTimeLogs recebeu '
        'userId ou projectId vazio.',
      );

      return Stream.value(<TimeLog>[]);
    }

    debugPrint(
      'TimeLogStore: iniciando stream de horas do projeto '
      '$id para usuário $uid.',
    );

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('projects')
        .doc(id)
        .collection('time_logs')
        .snapshots()
        .map(
      (snapshot) {
        debugPrint(
          'TimeLogStore: projeto $id recebeu '
          '${snapshot.docs.length} time_logs.',
        );

        final logs = snapshot.docs
            .map(
              (doc) => _timeLogFromDocument(
                id,
                doc,
              ),
            )
            .toList();

        logs.sort(
          (a, b) => b.date.compareTo(a.date),
        );

        debugPrint(
          'TimeLogStore: LISTA FINAL do projeto '
          '$id = ${logs.length} logs.',
        );

        for (final log in logs) {
          debugPrint(
            'TimeLogStore: '
            'lista -> '
            'id=${log.id} | '
            'hours=${log.hours} | '
            'duration=${log.durationFormatted} | '
            'registered=${log.isRegistered}',
          );
        }

        return logs;
      },
    );
  }

  // ============================================================
  // SALVAR NOVO LOG
  // ============================================================

  Future<String> addFirebaseLog(
    String projectId,
    TimeLog log,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Usuário não autenticado.');
    }

    final id = projectId.trim();

    if (id.isEmpty) {
      throw Exception('ID do projeto inválido.');
    }

    final String logId = log.id.trim().isNotEmpty
        ? log.id.trim()
        : DateTime.now().microsecondsSinceEpoch.toString();

    final double? resolvedHours = log.hours ??
        _durationToHours(
          log.durationFormatted,
        );

    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('projects')
        .doc(id)
        .collection('time_logs')
        .doc(logId);

    await docRef.set(
      {
        'targetId': log.targetId,
        'projectId': id,
        'hours': resolvedHours,
        'description': log.description,
        'isRegistered': log.isRegistered,
        'date': Timestamp.fromDate(log.date),
        'startTime': log.startTime,
        'endTime': log.endTime,
        'durationFormatted': log.durationFormatted,
        'projectName': log.projectName,
        'taskName': log.taskName,
        'typeHs': log.typeHs,
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return logId;
  }

  // ============================================================
  // CADASTRAR / REGISTRAR
  // ============================================================

  Future<void> register(TimeLog log) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Usuário não autenticado.');
    }

    final projectId = _getProjectIdFromLog(log);

    if (projectId.isEmpty) {
      throw Exception(
        'Não foi possível identificar o projeto do apontamento.',
      );
    }

    final logId = log.id.trim();

    String targetLogId = logId;

    if (logId.isEmpty) {
      log.isRegistered = true;

      targetLogId = await addFirebaseLog(
        projectId,
        log,
      );
    } else {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('projects')
          .doc(projectId)
          .collection('time_logs')
          .doc(logId);

      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        log.isRegistered = true;

        targetLogId = await addFirebaseLog(
          projectId,
          log,
        );
      } else {
        await docRef.set(
          {
            'isRegistered': true,
            'registeredAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    }

    final index = _logs.indexWhere(
      (item) => item.id == targetLogId,
    );

    if (index != -1) {
      _logs[index].isRegistered = true;
    } else {
      log.isRegistered = true;
      _logs.add(log);
    }

    _logs.sort(
      (a, b) => b.date.compareTo(a.date),
    );

    notifyListeners();
  }

  // ============================================================
  // REGISTRAR TODOS OS APONTAMENTOS DO PROJETO
  // ============================================================

  Future<void> registerProjectLogs(
    String projectId,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Usuário não autenticado.');
    }

    final id = projectId.trim();

    if (id.isEmpty) {
      throw Exception('ID do projeto inválido.');
    }

    final collection = _firestore
        .collection('users')
        .doc(userId)
        .collection('projects')
        .doc(id)
        .collection('time_logs');

    final snapshot = await collection.get();

    debugPrint(
      'TimeLogStore: projeto $id possui '
      '${snapshot.docs.length} apontamentos.',
    );

    final pending = snapshot.docs.where(
      (doc) {
        final data = doc.data();

        return data['isRegistered'] != true;
      },
    ).toList();

    if (pending.isNotEmpty) {
      final batch = _firestore.batch();

      for (final doc in pending) {
        batch.set(
          doc.reference,
          {
            'isRegistered': true,
            'registeredAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();

      debugPrint(
        'TimeLogStore: ${pending.length} '
        'apontamentos registrados no projeto $id.',
      );
    }

    await _loadProjectLogsIntoMemory(id);

    for (final log in _logs) {
      if (_getProjectIdFromLog(log) == id) {
        log.isRegistered = true;
      }
    }

    _logs.sort(
      (a, b) => b.date.compareTo(a.date),
    );

    notifyListeners();

    debugPrint(
      'TimeLogStore: finalização do projeto $id concluída. '
      'Todos os horários estão registrados.',
    );
  }

  // ============================================================
  // ATUALIZAR LOG
  // ============================================================

  Future<void> updateFirebaseLog(
    TimeLog log,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Usuário não autenticado.');
    }

    final projectId = _getProjectIdFromLog(log);

    if (projectId.isEmpty) {
      throw Exception('Projeto inválido.');
    }

    if (log.id.trim().isEmpty) {
      throw Exception(
        'ID do apontamento inválido.',
      );
    }

    final double? resolvedHours = log.hours ??
        _durationToHours(
          log.durationFormatted,
        );

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('projects')
        .doc(projectId)
        .collection('time_logs')
        .doc(log.id)
        .set(
      {
        'targetId': log.targetId,
        'projectId': projectId,
        'hours': resolvedHours,
        'description': log.description,
        'isRegistered': log.isRegistered,
        'date': Timestamp.fromDate(log.date),
        'startTime': log.startTime,
        'endTime': log.endTime,
        'durationFormatted': log.durationFormatted,
        'projectName': log.projectName,
        'taskName': log.taskName,
        'typeHs': log.typeHs,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    update(log);
  }

  // ============================================================
  // EXCLUIR DO FIRESTORE
  // ============================================================

  Future<void> deleteFirebaseLog(
    TimeLog log,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Usuário não autenticado.');
    }

    final projectId = _getProjectIdFromLog(log);

    if (projectId.isEmpty) {
      throw Exception('Projeto inválido.');
    }

    if (log.id.trim().isEmpty) {
      throw Exception(
        'ID do apontamento inválido.',
      );
    }

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('projects')
        .doc(projectId)
        .collection('time_logs')
        .doc(log.id)
        .delete();

    removeById(log.id);
  }

  // ============================================================
  // MEMÓRIA LOCAL
  // ============================================================

  void add(TimeLog log) {
    _logs.removeWhere(
      (item) => item.id == log.id,
    );

    _logs.add(log);

    _logs.sort(
      (a, b) => b.date.compareTo(a.date),
    );

    notifyListeners();
  }

  void update(TimeLog log) {
    final index = _logs.indexWhere(
      (item) => item.id == log.id,
    );

    if (index != -1) {
      _logs[index] = log;
    } else {
      _logs.add(log);
    }

    _logs.sort(
      (a, b) => b.date.compareTo(a.date),
    );

    notifyListeners();
  }

  void removeById(String id) {
    _logs.removeWhere(
      (log) => log.id == id,
    );

    notifyListeners();
  }

  void removeByTargetId(String targetId) {
    _logs.removeWhere(
      (log) => log.targetId == targetId,
    );

    notifyListeners();
  }

  // ============================================================
  // ENCERRAR STREAMS
  // ============================================================

  Future<void> stopListening() async {
    _scopeRefresh?.cancel();
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }

    _subscriptions.clear();
    _querySignatures.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _scopeRefresh?.cancel();
    _subscriptionGeneration++;
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }

    _subscriptions.clear();

    super.dispose();
  }

  // ============================================================
  // COMPATIBILIDADE
  // ============================================================

  void deleteLog(String s) {}

  void loadLogs() {}
}
