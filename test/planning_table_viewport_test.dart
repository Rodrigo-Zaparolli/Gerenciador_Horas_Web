import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/metrics/planning_table_viewport.dart';
void main() {
  for (final width in [360.0, 2000.0]) {
    testWidgets('planning table centers or scrolls at $width', (tester) async {
      tester.view.physicalSize = Size(width, 600); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlanningTableViewport(
        child: Container(key: const ValueKey('table'), height: 240, color: Colors.grey,
          child: const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('January'), Text('December')]))))));
      await tester.pumpAndSettle();
      final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
      final bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(bar.thumbVisibility, isTrue); expect(bar.interactive, isTrue);
      if (width < 1420) {
        expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
        await tester.drag(find.byType(SingleChildScrollView), const Offset(-1200, 0));
        await tester.pumpAndSettle();
        expect(scroll.controller!.offset, greaterThan(0));
        expect(find.text('December').hitTestable(), findsOneWidget);
      } else {
        expect(tester.getTopLeft(find.byKey(const ValueKey('table'))).dx, (width - 1420) / 2);
        expect(scroll.controller!.position.maxScrollExtent, 0);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
