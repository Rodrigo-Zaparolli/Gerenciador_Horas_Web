import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/features/auth/screens/login_screen.dart';
import 'package:gerenciador_horas/features/auth/screens/register_screen.dart';

void main() {
  testWidgets(
    'Login abre em uma janela estreita sem depender do Firebase',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester
          .pumpWidget(MaterialApp(home: LoginScreen(onLoginSuccess: () {})));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Criar nova conta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [const Size(320, 568), const Size(1440, 900)]) {
    testWidgets('Login e cadastro adaptam-se à janela $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester
          .pumpWidget(MaterialApp(home: LoginScreen(onLoginSuccess: () {})));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
          MaterialApp(home: RegisterScreen(onRegisterSuccess: () {})));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  }
}
