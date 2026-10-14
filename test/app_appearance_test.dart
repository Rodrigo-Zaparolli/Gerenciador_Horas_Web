import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_percentage.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';
import 'package:gerenciador_horas/data/services/user_cache.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

Widget harness(Widget child) => ValueListenableBuilder<AppVisualTheme>(
    valueListenable: AppAppearance.instance,
    builder: (context, mode, ignored) => MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode.mode,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) =>
            AppearanceScope(controller: AppAppearance.instance, child: child!),
        home: child));

class Draft extends StatefulWidget {
  const Draft({super.key});
  @override
  State<Draft> createState() => DraftState();
}

class DraftState extends State<Draft> {
  final controller = TextEditingController();
  final focus = FocusNode();
  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    return Scaffold(
        body: Column(children: [
      const ThemeToggleButton(),
      TextField(controller: controller, focusNode: focus),
      Text('Projeto selecionado', style: TextStyle(color: AppPalette.text)),
      TextButton(
          onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                      content:
                          Column(mainAxisSize: MainAxisSize.min, children: [
                    const ThemeToggleButton(),
                    CommentPercentageField(
                        controller: controller, enabled: true)
                  ]))),
          child: const Text('Comentário')),
    ]));
  }
}

void main() {
  setUp(() => AppAppearance.instance.value = AppVisualTheme.light);
  tearDown(() => AppAppearance.instance.value = AppVisualTheme.light);

  test('daily themes use neutral surfaces and consistent Material brightness', () {
    for (final mode in [AppVisualTheme.sand, AppVisualTheme.sage,
      AppVisualTheme.rose, AppVisualTheme.ruby]) {
      AppAppearance.instance.value = mode;
      expect(mode.mode, ThemeMode.light);
      expect(AppTheme.light.scaffoldBackgroundColor, AppPalette.background);
      expect(AppTheme.light.colorScheme.primary, AppPalette.primary);
      expect(AppTheme.light.colorScheme.onSurface, AppPalette.text);
      expect(AppPalette.success, const Color(0xFF087655));
      expect(AppPalette.warning, const Color(0xFF955500));
      expect(AppPalette.danger, const Color(0xFFBE3038));
    }
    AppAppearance.instance.value = AppVisualTheme.petroleum;
    expect(AppVisualTheme.petroleum.mode, ThemeMode.dark);
    expect(AppTheme.dark.scaffoldBackgroundColor, AppPalette.background);
    expect(AppTheme.dark.colorScheme.primary, AppPalette.primary);
  });

  for (final width in [320.0, 800.0, 1440.0]) {
    testWidgets('cabeçalho e troca de tema cabem na largura $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      UserCache().carregado = true;
      UserCache().userName = 'Teste';
      addTearDown(UserCache().limparCache);
      await tester.pumpWidget(harness(Scaffold(
          appBar: Cabecalho(
              selectedIndex: 0,
              onSelectTab: (_) {},
              searchQuery: '',
              onSearchChanged: (_) {},
              userName: 'Teste'),
          body: const SizedBox())));
      await tester.pumpAndSettle();
      expect(find.byType(ThemeToggleButton), findsOneWidget);
      await tester.tap(find.byTooltip('Escolher tema'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escuro').last);
      await tester.pumpAndSettle();
      expect(AppAppearance.instance.value, AppVisualTheme.dark);
      expect(tester.takeException(), isNull);
      if (width == 1440) {
        tester.view.physicalSize = Size(width, 400);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Teste'));
        await tester.pumpAndSettle();
        final logout = find.text('Sair da conta');
        await tester.ensureVisible(logout);
        await tester.pumpAndSettle();
        expect(logout.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final mode in AppVisualTheme.values) {
    test('paleta $mode tem contraste e fundos sem branco puro', () {
      AppAppearance.instance.value = mode;
      expect(AppPalette.background, isNot(Colors.white));
      expect(AppPalette.surface, isNot(Colors.white));
      for (final background in [
        AppPalette.background,
        AppPalette.surface,
        AppPalette.field
      ]) {
        expect(
            contrast(AppPalette.text, background), greaterThanOrEqualTo(4.5));
        expect(contrast(AppPalette.secondary, background),
            greaterThanOrEqualTo(4.5));
      }
      expect(contrast(AppPalette.onPrimary, AppPalette.primary),
          greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('alternar mantém o estado, texto, seleção e modal aberto',
      (tester) async {
    final key = GlobalKey<DraftState>();
    await tester.pumpWidget(harness(Draft(key: key)));
    final original = key.currentState;
    await tester.enterText(find.byType(TextField), '25,50');
    original!.controller.selection =
        const TextSelection(baseOffset: 0, extentOffset: 2);
    await tester.tap(find.byTooltip('Escolher tema'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Escuro').last);
    await tester.pumpAndSettle();
    expect(key.currentState, same(original));
    expect(original.controller.text, '25,50');
    expect(original.controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2));
    expect(tester.widget<Text>(find.text('Projeto selecionado')).style!.color,
        AppPalette.text);
    await tester.tap(find.text('Comentário'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byTooltip('Escolher tema').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claro').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(AppAppearance.instance.value, AppVisualTheme.light);
    expect(original.controller.text, '25,50');
    expect(find.text('% Realizado'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
