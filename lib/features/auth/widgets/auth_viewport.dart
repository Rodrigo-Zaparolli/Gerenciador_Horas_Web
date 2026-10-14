import 'package:flutter/material.dart';

class AuthViewport extends StatelessWidget {
  final Widget child;
  const AuthViewport({super.key, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        ),
      );
}
