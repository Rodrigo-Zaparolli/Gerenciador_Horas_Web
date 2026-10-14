import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';

void main() {
  test('project email persists, remains optional and can be cleared', () {
    final legacy = ProjectModel.fromJson({'id': '123'});
    expect(legacy.email, isNull);
    legacy.email = 'cliente@example.com';
    final restored = ProjectModel.fromJson(legacy.toJson());
    expect(restored.email, 'cliente@example.com');
    restored.email = null;
    expect(restored.toJson()['email'], isNull);
  });
}
