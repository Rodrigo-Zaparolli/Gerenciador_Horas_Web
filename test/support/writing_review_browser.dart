import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:gerenciador_horas/shared/widgets/writing_review.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(MaterialApp(
      builder: (_, child) => WritingReviewScope(child: child!),
      home: const Scaffold(
          body: Padding(padding: EdgeInsets.all(24), child: Fixture()))));
}

class Fixture extends StatefulWidget {
  const Fixture({super.key});
  @override
  State<Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<Fixture> {
  final controller = TextEditingController(text: 'Descricao do servico');
  String saved = '';
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Descrição das horas'),
            onChanged: (value) => setState(() => saved = value)),
        Text('Resultado: $saved'),
      ]);
}
