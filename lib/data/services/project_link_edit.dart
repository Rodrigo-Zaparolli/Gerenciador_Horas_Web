import '../../domain/models/project_model.dart';
import 'firebase_service.dart';
import 'project_reference_save.dart';

/// Keeps a link editor isolated until its explicit selections are persisted.
class ProjectLinkEdit {
  ProjectLinkEdit(ProjectModel original)
      : draft = ProjectModel.fromJson(original.toJson()),
        previousFolder = original.folderPath,
        previousExcel = original.excelLink;
  final ProjectModel draft;
  final String? previousFolder, previousExcel;

  Future<void> save(FirebaseService service) => service.saveProject(
      draft,
      draft.id,
      ProjectReferenceChanges(
          previousFolder: previousFolder, previousExcel: previousExcel));
}
