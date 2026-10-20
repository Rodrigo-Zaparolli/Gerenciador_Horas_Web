// ignore_for_file: unnecessary_cast

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:gerenciador_horas/domain/models/checklist_format_model.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'project_reference_upgrade.dart';
import 'project_move_patch.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> applyProjectFolderMove(
      String projectId, Map<String, dynamic> move) async {
    final uid = _userId;
    final owner = _db.collection('users').doc(uid);
    final refs = [
      owner.collection('projects').doc(projectId),
      owner.collection('completed_projects').doc(projectId)
    ];
    final cache = refs.first.collection('spreadsheet').doc('snapshot');
    final history =
        owner.collection('folder_moves').doc(move['operation'] as String);
    await _db.runTransaction((transaction) async {
      final projects = [
        await transaction.get(refs[0]),
        await transaction.get(refs[1])
      ];
      final saved = await transaction.get(cache);
      if (_auth.currentUser?.uid != uid) throw StateError('A conta mudou.');
      if (!projects.any((p) => p.exists))
        throw StateError(
            'O projeto não foi encontrado para atualizar os vínculos.');
      for (var i = 0; i < projects.length; i++) {
        if (projects[i].exists)
          transaction.update(
              refs[i], projectMovePatch(projects[i].data()!, move));
      }
      if (saved.data()?['reference'] == move['oldExcelReference']) {
        transaction.update(cache, {'reference': move['excelReference']});
      }
      transaction.set(history, {
        'projectId': projectId,
        'source': move['source'],
        'target': move['target'],
        'folderReference': move['folderReference'],
        'excelReference': move['excelReference'],
        'completedAt': FieldValue.serverTimestamp()
      });
    });
  }

  Future<void> upgradeProjectLocalReference(String projectId,
      {required String field,
      required String previous,
      required String resolved}) async {
    final uid = _userId;
    final owner = _db.collection('users').doc(uid);
    final refs = [
      owner.collection('projects').doc(projectId),
      owner.collection('completed_projects').doc(projectId)
    ];
    await _db.runTransaction((transaction) async {
      final snapshots = [
        await transaction.get(refs[0]),
        await transaction.get(refs[1])
      ];
      if (_auth.currentUser?.uid != uid)
        throw StateError('A conta mudou. Abra o trabalho novamente.');
      for (var i = 0; i < refs.length; i++) {
        final data = snapshots[i].data();
        if (data == null) continue;
        final patch = projectReferenceUpgrade(data,
            uid: uid, field: field, previous: previous, resolved: resolved);
        if (patch != null) transaction.update(refs[i], patch);
      }
    });
  }

  // ============================================================
  // USUÁRIO ATUAL
  // ============================================================

  String get _userId {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception(
        'Usuário não autenticado.',
      );
    }

    return user.uid;
  }

  // ============================================================
  // REFERÊNCIAS
  // ============================================================

  CollectionReference<Map<String, dynamic>> get _projectsRef {
    return _db.collection('users').doc(_userId).collection('projects');
  }

  CollectionReference<Map<String, dynamic>> get _completedProjectsRef {
    return _db
        .collection('users')
        .doc(_userId)
        .collection('completed_projects');
  }

  CollectionReference<Map<String, dynamic>> get _checklistFormatsRef {
    return _db.collection('users').doc(_userId).collection('checklist_formats');
  }

  CollectionReference<Map<String, dynamic>> get _workFormatsRef {
    return _db.collection('users').doc(_userId).collection('work_formats');
  }

  CollectionReference<Map<String, dynamic>> get _metricsRef {
    return _db.collection('users').doc(_userId).collection('metrics');
  }

  CollectionReference<Map<String, dynamic>> get _orientacoesRef {
    return _db.collection('users').doc(_userId).collection('orientacoes');
  }

  // ============================================================
  // CONVERSÃO DE DATA
  // ============================================================

  DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  // ============================================================
  // CONVERTE SUBTASKS
  // ============================================================

  List<TaskModel> _parseSubTasks(
    dynamic value,
  ) {
    if (value == null || value is! List) {
      return [];
    }

    final List<TaskModel> tasks = [];

    for (final item in value) {
      if (item is! Map) {
        continue;
      }

      final Map<String, dynamic> data = Map<String, dynamic>.from(item);

      debugPrint(
        '''
========== DEBUG E-DESK ==========
subId: ${data['subId']}
edeskSolicitacao: ${data['edeskSolicitacao']}
edeskUrl: ${data['edeskUrl']}
edeskIdTrabalho: ${data['edeskIdTrabalho']}
==================================
''',
      );

      final DateTime? startDate = _parseDate(
        data['startDate'],
      );

      final DateTime? planStart = _parseDate(
        data['planStart'],
      );

      final DateTime? planEnd = _parseDate(
        data['planEnd'],
      );

      tasks.add(
        TaskModel(
          subId: data['subId']?.toString() ?? '',
          stage: data['stage']?.toString() ?? '',
          status: data['status']?.toString() ?? 'INI_PRO',
          startDate: startDate ?? planStart ?? DateTime.now(),
          planStart: planStart,
          planEnd: planEnd,
          estimatedHours: data['estimatedHours']?.toString() ??
              data['workedHours']?.toString() ??
              data['horasTrabalhadas']?.toString() ??
              '00:00',
          hourType: data['hourType']?.toString() ?? 'Hs Cobradas',

// ========================================================
// E-DESK
// ========================================================

          edeskSolicitacao:
              data['edeskSolicitacao']?.toString().trim().isNotEmpty == true
                  ? data['edeskSolicitacao'].toString().trim()
                  : null,

          edeskUrl: data['edeskUrl']?.toString().trim().isNotEmpty == true
              ? data['edeskUrl'].toString().trim()
              : null,

          edeskIdTrabalho:
              data['edeskIdTrabalho']?.toString().trim().isNotEmpty == true
                  ? data['edeskIdTrabalho'].toString().trim()
                  : null,
        ),
      );
    }

    return tasks;
  }
  // ============================================================
  // FIRESTORE -> PROJECT MODEL
  // ============================================================

  ProjectModel _projectFromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};

    final DateTime projectStartDate = _parseDate(
          data['startDate'],
        ) ??
        DateTime.now();

    final List<TaskModel> subTasks = _parseSubTasks(
      data['subTasks'],
    );

// ============================================================
// GARANTIR E-DESK EM PROJETOS ANTIGOS
// ============================================================
//
// Se o projeto foi criado antes da implementação dos campos
// E-Desk, os campos podem estar ausentes/null no Firestore.
//
// Nesse caso reconstruímos automaticamente:
// projeto + subId.
//
// Exemplo:
// 2263797 + 18 -> 2263797 / 18
// 2263797 + 31 -> 2263797 / 31
// ============================================================

    final String projetoEdesk =
        (data['id']?.toString().trim().isNotEmpty == true)
            ? data['id'].toString().trim()
            : doc.id.trim();

    for (final task in subTasks) {
      if (task.edeskSolicitacao == null ||
          task.edeskSolicitacao!.trim().isEmpty) {
        task.edeskSolicitacao = projetoEdesk;
      } else {
        task.edeskSolicitacao = task.edeskSolicitacao!.trim();
      }

      if (task.edeskIdTrabalho == null ||
          task.edeskIdTrabalho!.trim().isEmpty) {
        task.edeskIdTrabalho = task.subId.trim();
      } else {
        task.edeskIdTrabalho = task.edeskIdTrabalho!.trim();
      }

      if (task.edeskUrl != null) {
        task.edeskUrl = task.edeskUrl!.trim();

        if (task.edeskUrl!.isEmpty) {
          task.edeskUrl = null;
        }
      }

      debugPrint('''
========== E-DESK NORMALIZADO ==========
Projeto: $projetoEdesk
Tarefa: ${task.subId}
Solicitação: ${task.edeskSolicitacao}
ID Trabalho: ${task.edeskIdTrabalho}
URL: ${task.edeskUrl}
========================================
''');
    }

    final String resolvedHours = data['estimatedHours']?.toString() ??
        data['workedHours']?.toString() ??
        data['horasTrabalhadas']?.toString() ??
        data['timeSpent']?.toString() ??
        '00:00';

    List<Map<String, dynamic>> parsedChecklist = [];

    final dynamic rawChecklist = data['checklist'];

    if (rawChecklist is List) {
      parsedChecklist = rawChecklist
          .whereType<Map>()
          .map(
            (item) => Map<String, dynamic>.from(
              item,
            ),
          )
          .toList();
    }

    return ProjectModel(
      id: data['id']?.toString() ?? doc.id,
      id2: data['id2']?.toString() ?? '0',
      client: data['client']?.toString() ?? '',
      serviceType: data['serviceType']?.toString() ?? '',
      stage: data['stage']?.toString() ?? '',
      task: data['task']?.toString() ?? '',
      status: data['status']?.toString() ?? 'INI_PRO',
      startDate: projectStartDate,
      estimatedHours: resolvedHours,
      leader: data['leader']?.toString() ?? '',
      hourType: data['hourType']?.toString() ?? 'Hs Cobradas',
      subTasks: subTasks,
      checklist: parsedChecklist,
      observacao: data['observacao']?.toString(),
      excelLink: data['excelLink']?.toString(),
      folderPath: data['folderPath']?.toString(),
      email: data['email']?.toString(),
    );
  }

  // ============================================================
  // PROJETOS
  // ============================================================

  Future<List<ProjectModel>> getProjects() async {
    final snapshot = await _projectsRef.get();

    return snapshot.docs
        .map(
          (doc) => _projectFromFirestore(doc),
        )
        .toList();
  }

  Stream<List<ProjectModel>> getProjectsStream() {
    return _projectsRef.snapshots().map(
      (snapshot) {
        return snapshot.docs
            .map(
              (doc) => _projectFromFirestore(
                doc,
              ),
            )
            .toList();
      },
    );
  }

  Future<ProjectModel?> getProject(
    String projectId,
  ) async {
    final doc = await _projectsRef.doc(projectId).get();

    if (!doc.exists) {
      return null;
    }

    return _projectFromFirestore(doc);
  }

// ============================================================
// SALVAR PROJETO
// ============================================================

  Future<void> saveProject(
    ProjectModel project, [
    String? docId,
  ]) async {
    final String targetDocId = (docId != null && docId.trim().isNotEmpty)
        ? docId.trim()
        : project.id.trim();

    if (targetDocId.isEmpty) {
      throw Exception(
        'Não foi possível salvar o projeto: ID vazio.',
      );
    }

    // ============================================================
    // GARANTIR DADOS DO E-DESK NAS TAREFAS
    // ============================================================
    //
    // A solicitação do E-Desk corresponde ao ID do projeto.
    //
    // O número do trabalho corresponde ao subId da tarefa.
    //
    // Exemplo:
    //
    // Projeto: 2263797
    // Tarefa: 31
    //
    // Resultado:
    // edeskSolicitacao = 2263797
    // edeskIdTrabalho = 31
    //
    // ============================================================

    if (project.subTasks != null) {
      for (final task in project.subTasks!) {
        final String projetoEdesk = project.id.trim();
        final String tarefaEdesk = task.subId.trim();

        if (task.edeskSolicitacao == null ||
            task.edeskSolicitacao!.trim().isEmpty) {
          task.edeskSolicitacao = projetoEdesk;
        } else {
          task.edeskSolicitacao = task.edeskSolicitacao!.trim();
        }

        if (task.edeskIdTrabalho == null ||
            task.edeskIdTrabalho!.trim().isEmpty) {
          task.edeskIdTrabalho = tarefaEdesk;
        } else {
          task.edeskIdTrabalho = task.edeskIdTrabalho!.trim();
        }

        if (task.edeskUrl != null) {
          task.edeskUrl = task.edeskUrl!.trim();

          if (task.edeskUrl!.isEmpty) {
            task.edeskUrl = null;
          }
        }

        debugPrint('''
========== FIREBASE SAVE E-DESK ==========
Projeto: ${project.id}
Tarefa: ${task.subId}
Solicitação: ${task.edeskSolicitacao}
ID Trabalho: ${task.edeskIdTrabalho}
URL: ${task.edeskUrl}
==========================================
''');
      }
    }

    // ============================================================
    // SE O PROJETO ESTÁ FINALIZADO
    // ============================================================
    //
    // IMPORTANTE:
    // O bloco E-DESK precisa executar ANTES daqui.
    //
    // Assim finalizarProjeto() recebe as tarefas já preenchidas.
    //
    // ============================================================

    if (project.status == 'TRAB_FIM') {
      await finalizarProjeto(
        project,
        docId: targetDocId,
      );

      return;
    }

    // ============================================================
    // CONVERTER PROJETO PARA JSON
    // ============================================================

    final Map<String, dynamic> data = project.toJson();

    // ============================================================
    // GARANTIR CAMPOS PRINCIPAIS
    // ============================================================

    data['id'] = project.id;
    data['estimatedHours'] = project.estimatedHours;
    data['workedHours'] = project.estimatedHours;
    data['horasTrabalhadas'] = project.estimatedHours;

    // ============================================================
    // GARANTIR SUBTASKS NO JSON
    // ============================================================

    if (project.subTasks != null) {
      data['subTasks'] = project.subTasks!.map((task) {
        return task.toJson();
      }).toList();
    } else {
      data['subTasks'] = <Map<String, dynamic>>[];
    }

    // ============================================================
    // CHECKLIST
    // ============================================================

    data['checklist'] = List<Map<String, dynamic>>.from(
      project.checklist.map(
        (item) => Map<String, dynamic>.from(item),
      ),
    );

    // ============================================================
    // SALVAR
    // ============================================================

    await _projectsRef.doc(targetDocId).set(
          data,
          SetOptions(merge: true),
        );

    debugPrint(
      'Projeto $targetDocId salvo com sucesso no Firestore.',
    );
  }
  // ============================================================
  // CHECKLIST
  // ============================================================

  Future<void> saveProjectChecklist(
    String projectId,
    List<Map<String, dynamic>> checklist,
  ) async {
    final String id = projectId.trim();

    if (id.isEmpty) {
      throw Exception(
        'Não foi possível salvar o checklist: ID do projeto vazio.',
      );
    }

    final List<Map<String, dynamic>> normalizedChecklist =
        checklist.map((item) {
      return Map<String, dynamic>.from(
        item,
      );
    }).toList();

    await _projectsRef.doc(id).set(
      {
        'checklist': normalizedChecklist,
        'checklistUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> replaceProjectChecklist(
    ProjectModel project,
    List<Map<String, dynamic>> checklist,
  ) async {
    final List<Map<String, dynamic>> copiedChecklist = checklist.map((item) {
      final copy = Map<String, dynamic>.from(
        item,
      );

      copy['completed'] = false;

      return copy;
    }).toList();

    project.checklist = copiedChecklist;

    await saveProjectChecklist(
      project.id,
      copiedChecklist,
    );
  }

  Future<void> addChecklistItemToProject(
    ProjectModel project,
    Map<String, dynamic> item,
  ) async {
    final List<Map<String, dynamic>> checklist = project.checklist.map((item) {
      return Map<String, dynamic>.from(
        item,
      );
    }).toList();

    final Map<String, dynamic> newItem = Map<String, dynamic>.from(
      item,
    );

    newItem['completed'] = newItem['completed'] == true;

    checklist.add(newItem);

    project.checklist = checklist;

    await saveProjectChecklist(
      project.id,
      checklist,
    );
  }

  Future<void> updateChecklistItem(
    ProjectModel project,
    int index,
    Map<String, dynamic> item,
  ) async {
    final List<Map<String, dynamic>> checklist = project.checklist.map((item) {
      return Map<String, dynamic>.from(
        item,
      );
    }).toList();

    if (index < 0 || index >= checklist.length) {
      throw Exception(
        'Item de checklist inválido.',
      );
    }

    checklist[index] = Map<String, dynamic>.from(item);

    project.checklist = checklist;

    await saveProjectChecklist(
      project.id,
      checklist,
    );
  }

  Future<void> toggleChecklistItem(
    ProjectModel project,
    int index,
  ) async {
    final List<Map<String, dynamic>> checklist = project.checklist.map((item) {
      return Map<String, dynamic>.from(
        item,
      );
    }).toList();

    if (index < 0 || index >= checklist.length) {
      throw Exception(
        'Item de checklist inválido.',
      );
    }

    final bool current = checklist[index]['completed'] == true;

    checklist[index]['completed'] = !current;

    project.checklist = checklist;

    await saveProjectChecklist(
      project.id,
      checklist,
    );
  }

  Future<void> removeChecklistItem(
    ProjectModel project,
    int index,
  ) async {
    final List<Map<String, dynamic>> checklist = project.checklist.map((item) {
      return Map<String, dynamic>.from(
        item,
      );
    }).toList();

    if (index < 0 || index >= checklist.length) {
      throw Exception(
        'Item de checklist inválido.',
      );
    }

    checklist.removeAt(index);

    for (int i = 0; i < checklist.length; i++) {
      checklist[i]['order'] = i + 1;
    }

    project.checklist = checklist;

    await saveProjectChecklist(
      project.id,
      checklist,
    );
  }

  // ============================================================
  // APONTAMENTOS
  // ============================================================

  Future<void> addTimeEntry({
    required String projectId,
    required String hours,
    required String description,
    DateTime? date,
  }) async {
    final String idTrimmed = projectId.trim();

    if (idTrimmed.isEmpty) {
      throw Exception(
        'ID do projeto inválido para apontamento de horas.',
      );
    }

    final entryRef = _projectsRef.doc(idTrimmed).collection('time_entries');

    await entryRef.add({
      'hours': hours,
      'description': description,
      'date': date ?? FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> getTimeEntries(
    String projectId,
  ) async {
    final String idTrimmed = projectId.trim();

    if (idTrimmed.isEmpty) {
      return [];
    }

    final snapshot = await _projectsRef
        .doc(idTrimmed)
        .collection('time_entries')
        .orderBy(
          'date',
          descending: true,
        )
        .get();

    return snapshot.docs.map((doc) {
      return {
        'id': doc.id,
        ...doc.data(),
      };
    }).toList();
  }

  Future<void> atualizarHorasProjeto(
    String projectId,
    String novasHoras,
  ) async {
    final String idTrimmed = projectId.trim();

    if (idTrimmed.isEmpty) {
      throw Exception(
        'ID do projeto inválido para atualizar horas.',
      );
    }

    await _projectsRef.doc(idTrimmed).update({
      'estimatedHours': novasHoras,
      'workedHours': novasHoras,
      'horasTrabalhadas': novasHoras,
    });
  }

  // ============================================================
  // FINALIZAR PROJETO
  // ============================================================

  Future<void> finalizarProjeto(
    ProjectModel project, {
    String? docId,
  }) async {
    final String projectId = (docId != null && docId.trim().isNotEmpty)
        ? docId.trim()
        : project.id.trim();

    if (projectId.isEmpty) {
      throw Exception(
        'Não foi possível finalizar o projeto: ID vazio.',
      );
    }

    project.status = 'TRAB_FIM';

    final Map<String, dynamic> completedData = project.toJson();

    completedData['id'] = project.id;

    completedData['status'] = 'TRAB_FIM';

    completedData['estimatedHours'] = project.estimatedHours;

    completedData['workedHours'] = project.estimatedHours;

    completedData['horasTrabalhadas'] = project.estimatedHours;

    completedData['finalizedAt'] = FieldValue.serverTimestamp();

    completedData['sourceCollection'] = 'projects';

    final activeProjectRef = _projectsRef.doc(projectId);

    final completedProjectRef = _completedProjectsRef.doc(
      projectId,
    );

    final WriteBatch batch = _db.batch();

    batch.set(
      completedProjectRef,
      completedData,
      SetOptions(merge: true),
    );

    batch.delete(
      activeProjectRef,
    );

    await batch.commit();

    final activeCheck = await activeProjectRef.get();

    if (activeCheck.exists) {
      await activeProjectRef.delete();
    }
  }

  // ============================================================
  // EXCLUIR PROJETO
  // ============================================================

  Future<void> deleteProject(
    String docId,
  ) async {
    await _projectsRef.doc(docId).delete();
  }

  // ============================================================
  // WORK FORMATS
  // ============================================================

  Future<List<WorkFormat>> getWorkFormats() async {
    final snapshot = await _workFormatsRef.get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      final dynamic rawSteps = data['steps'];

      final List<String> normalizedSteps = [];

      if (rawSteps is List) {
        for (final step in rawSteps) {
          if (step is String) {
            final value = step.trim();

            if (value.isNotEmpty) {
              normalizedSteps.add(
                value,
              );
            }
          } else if (step is Map) {
            final Map<String, dynamic> map = Map<String, dynamic>.from(
              step,
            );

            final dynamic name = map['name'] ??
                map['stage'] ??
                map['title'] ??
                map['descricao'] ??
                map['description'];

            if (name != null) {
              final value = name.toString().trim();

              if (value.isNotEmpty) {
                normalizedSteps.add(
                  value,
                );
              }
            }
          } else {
            final value = step.toString().trim();

            if (value.isNotEmpty) {
              normalizedSteps.add(
                value,
              );
            }
          }
        }
      }

      return WorkFormat(
        id: doc.id,
        name: data['name']?.toString() ?? '',
        steps: normalizedSteps,
      );
    }).toList();
  }

  Future<void> saveWorkFormat(
    WorkFormat format,
  ) async {
    final List<String> normalizedSteps = [];

    for (final step in format.steps) {
      if (step is String) {
        final value = step.trim();

        if (value.isNotEmpty) {
          normalizedSteps.add(value);
        }
      } else if (step is Map) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(
          step,
        );

        final dynamic name = map['name'] ??
            map['stage'] ??
            map['title'] ??
            map['descricao'] ??
            map['description'];

        if (name != null) {
          final value = name.toString().trim();

          if (value.isNotEmpty) {
            normalizedSteps.add(
              value,
            );
          }
        }
      } else {
        final value = step.toString().trim();

        if (value.isNotEmpty) {
          normalizedSteps.add(value);
        }
      }
    }

    await _workFormatsRef.doc(format.id).set(
      {
        'id': format.id,
        'name': format.name,
        'steps': normalizedSteps,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deleteWorkFormat(
    String id,
  ) async {
    await _workFormatsRef.doc(id).delete();
  }

  // ============================================================
  // EXPORTAR MODELOS
  // ============================================================

  Future<List<Map<String, dynamic>>> exportWorkFormats() async {
    final snapshot = await _workFormatsRef.get();

    return snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(
        doc.data(),
      );

      return {
        'id': doc.id,
        'name': data['name']?.toString() ?? '',
        'steps': data['steps'] is List
            ? List<dynamic>.from(
                data['steps'],
              )
            : <dynamic>[],
      };
    }).toList();
  }

  // ============================================================
  // IMPORTAR MODELOS
  // ============================================================

  Future<int> importWorkFormats(
    List<dynamic> formats,
  ) async {
    int importedCount = 0;

    final WriteBatch batch = _db.batch();

    for (final item in formats) {
      if (item is! Map) {
        continue;
      }

      final Map<String, dynamic> data = Map<String, dynamic>.from(
        item,
      );

      final String id = data['id']?.toString().trim() ?? '';

      final String name = data['name']?.toString().trim() ?? '';

      if (id.isEmpty || name.isEmpty) {
        continue;
      }

      final dynamic rawSteps = data['steps'];

      final List<dynamic> steps = rawSteps is List
          ? List<dynamic>.from(
              rawSteps,
            )
          : <dynamic>[];

      final DocumentReference<Map<String, dynamic>> ref =
          _workFormatsRef.doc(id);

      batch.set(
        ref,
        {
          'id': id,
          'name': name,
          'steps': steps,
        },
        SetOptions(merge: true),
      );

      importedCount++;
    }

    if (importedCount > 0) {
      await batch.commit();
    }

    return importedCount;
  }

  // ============================================================
  // MÉTRICAS
  // ============================================================

  Future<void> saveUserMetrics(
    Map<String, dynamic> data,
  ) async {
    await _metricsRef.doc('yearly_data').set(
          data,
          SetOptions(merge: true),
        );
  }

  Future<Map<String, dynamic>?> getUserMetrics() async {
    final doc = await _metricsRef.doc('yearly_data').get();

    return doc.data();
  }

  // ============================================================
  // ORIENTAÇÕES
  // ============================================================

  /// Mantido para compatibilidade
  /// com código antigo do projeto.
  get firestore => _db;

  /// Mantido para compatibilidade
  /// com código antigo do projeto.
  get currentUserId => _userId;

  // ------------------------------------------------------------
  // BUSCAR ORIENTAÇÕES
  // ------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getOrientacoes() async {
    final snapshot = await _orientacoesRef.get();

    return snapshot.docs.map((doc) {
      final data = doc.data();

      // Garante que o ID também
      // esteja disponível para a tela.
      final Map<String, dynamic> resultado = {
        'id': doc.id,
        ...data,
      };

      // Normaliza imagens antigas.
      if (resultado['imagens'] is List) {
        resultado['imagens'] = List<String>.from(
          (resultado['imagens'] as List).whereType<String>(),
        );
      } else {
        resultado['imagens'] = <String>[];
      }

      return resultado;
    }).toList();
  }

  // ------------------------------------------------------------
  // SALVAR ORIENTAÇÃO
  // ------------------------------------------------------------

  Future<void> saveOrientacao(
    String id,
    Map<String, dynamic> data,
  ) async {
    if (id.trim().isEmpty) {
      throw Exception(
        'Não foi possível salvar orientação: ID vazio.',
      );
    }

    final Map<String, dynamic> dadosParaSalvar = Map<String, dynamic>.from(
      data,
    );

    // Garante o ID no documento.
    dadosParaSalvar['id'] = id.trim();

    // ----------------------------------------------------------
    // IMAGENS
    // ----------------------------------------------------------
    //
    // As imagens são mantidas como
    // List<String> em Base64.
    //

    final dynamic rawImagens = dadosParaSalvar['imagens'];

    if (rawImagens is List) {
      dadosParaSalvar['imagens'] = rawImagens
          .whereType<String>()
          .where(
            (item) => item.trim().isNotEmpty,
          )
          .toList();
    } else {
      dadosParaSalvar['imagens'] = <String>[];
    }

    await _orientacoesRef.doc(id.trim()).set(
          dadosParaSalvar,
          SetOptions(merge: true),
        );
  }

  // ------------------------------------------------------------
  // EXCLUIR ORIENTAÇÃO
  // ------------------------------------------------------------

  Future<void> deleteOrientacao(
    String id,
  ) async {
    if (id.trim().isEmpty) {
      throw Exception(
        'Não foi possível excluir orientação: ID vazio.',
      );
    }

    await _orientacoesRef.doc(id.trim()).delete();
  }

  // ============================================================
  // PROJETOS FINALIZADOS
  // ============================================================

  Stream<List<Map<String, dynamic>>> getCompletedProjectsStream() {
    return _completedProjectsRef.snapshots().map(
      (snapshot) {
        return snapshot.docs.map(
          (doc) {
            final data = doc.data();

            return {
              'id': doc.id,
              ...data,
            };
          },
        ).toList();
      },
    );
  }

  Future<List<Map<String, dynamic>>> getCompletedProjects() async {
    final snapshot = await _completedProjectsRef.get();

    return snapshot.docs.map(
      (doc) {
        final data = doc.data();

        return {
          'id': doc.id,
          ...data,
        };
      },
    ).toList();
  }

  Future<void> saveCompletedProject(
    String id,
    Map<String, dynamic> data,
  ) async {
    if (id.trim().isEmpty) {
      throw Exception(
        'Não foi possível salvar projeto finalizado: ID vazio.',
      );
    }

    final Map<String, dynamic> completedData = Map<String, dynamic>.from(
      data,
    );

    completedData['id'] = id;
    completedData['status'] = 'TRAB_FIM';

    if (!completedData.containsKey('finalizedAt')) {
      completedData['finalizedAt'] = FieldValue.serverTimestamp();
    }

    await _completedProjectsRef.doc(id).set(
          completedData,
          SetOptions(merge: true),
        );

    await _projectsRef.doc(id).delete();
  }

  Future<void> deleteCompletedProject(
    String id,
  ) async {
    await _completedProjectsRef.doc(id).delete();
  }

  // ============================================================
  // REABRIR PROJETO
  // ============================================================

  Future<void> reopenCompletedProject(
    String projectId,
  ) async {
    if (projectId.trim().isEmpty) {
      throw Exception(
        'ID do projeto inválido.',
      );
    }

    final String id = projectId.trim();

    final completedRef = _completedProjectsRef.doc(id);

    final completedSnapshot = await completedRef.get();

    if (!completedSnapshot.exists) {
      throw Exception(
        'O projeto $id não foi encontrado em projetos finalizados.',
      );
    }

    final Map<String, dynamic> completedData = Map<String, dynamic>.from(
      completedSnapshot.data() ?? <String, dynamic>{},
    );

    final dynamic savedPreviousStatus = completedData['statusBeforeCompletion'];

    final String previousStatus =
        savedPreviousStatus?.toString().trim().isNotEmpty == true
            ? savedPreviousStatus.toString()
            : 'TRAB';

    completedData['status'] = previousStatus;

    completedData.remove(
      'finalizedAt',
    );

    completedData.remove(
      'statusBeforeCompletion',
    );

    completedData['sourceCollection'] = 'projects';

    completedData['reopenedAt'] = FieldValue.serverTimestamp();

    final projectRef = _projectsRef.doc(id);

    final batch = _db.batch();

    batch.set(
      projectRef,
      completedData,
      SetOptions(merge: false),
    );

    batch.delete(
      completedRef,
    );

    await batch.commit();
  }

  // ============================================================
  // MODELOS DE CHECK LIST
  // ============================================================

  Future<List<ChecklistFormat>> getChecklistFormats() async {
    try {
      final snapshot = await _checklistFormatsRef.get();

      return snapshot.docs.map((doc) {
        final data = doc.data();

        return ChecklistFormat.fromJson(
          data,
          doc.id,
        );
      }).toList();
    } catch (e) {
      print(
        'Erro ao buscar modelos de check list: $e',
      );

      return [];
    }
  }

  Future<void> saveChecklistFormat(
    ChecklistFormat format,
  ) async {
    try {
      await _checklistFormatsRef.doc(format.id).set(
            format.toJson(),
            SetOptions(merge: true),
          );
    } catch (e) {
      print(
        'Erro ao salvar modelo de check list: $e',
      );

      rethrow;
    }
  }

  Future<void> deleteChecklistFormat(
    String id,
  ) async {
    try {
      await _checklistFormatsRef.doc(id).delete();
    } catch (e) {
      print(
        'Erro ao excluir modelo de check list: $e',
      );

      rethrow;
    }
  }

  // ============================================================
  // ALIASES
  // ============================================================

  Future<void> salvarProjeto(
    ProjectModel project, [
    String? docId,
  ]) async {
    await saveProject(
      project,
      docId,
    );
  }

  Future<void> excluirProjeto(
    String id,
  ) async {
    await _projectsRef.doc(id).delete();

    await _completedProjectsRef.doc(id).delete();
  }

  Future<void> deleteTimeLog(
    String s,
  ) async {}

  Future<void> addProject(
    ProjectModel project,
  ) async {
    await saveProject(
      project,
      project.id,
    );
  }

  Future<void> updateProject(
    ProjectModel project,
  ) async {
    await saveProject(
      project,
      project.id,
    );
  }
}
