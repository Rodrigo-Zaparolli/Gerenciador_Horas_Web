import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/features/edesk/edesk_history_dialog.dart';

void main() {
  setUp(() => LocalUserState.memory = {});
  tearDown(() { LocalUserState.memory = null; AppAppearance.instance.value = AppVisualTheme.light; });
  for (final theme in AppVisualTheme.values) {
    for (final size in [const Size(1100, 800), const Size(320, 568)]) {
      testWidgets('history fits ${theme.name} $size with pagination and close action', (tester) async {
        tester.view.physicalSize = size; tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
        AppAppearance.instance.value = theme;
        await tester.pumpWidget(MaterialApp(theme: theme.mode == ThemeMode.dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(body: EdeskHistoryDialog(owner: 'owner', isCurrentAccount: () => true,
            accountLoader: (_) async => List.generate(15, (i) => {
              'id': '$i', 'action': 'horas', 'project': '123, 456',
              'created': DateTime(2026, 10, i + 1).toIso8601String(),
              'state': i == 14 ? 'uncertain' : 'confirmed',
            }), ledgerLoader: () async => {'items': {'a': 'confirmed', 'b': 'uncertain'}}))));
        await tester.pumpAndSettle();
        expect(find.textContaining('1 horas confirmadas'), findsOneWidget);
        expect(find.text('1 / 2'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Próxima página'));
        await tester.tap(find.byTooltip('Próxima página')); await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);
        expect(find.text('Fechar').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
