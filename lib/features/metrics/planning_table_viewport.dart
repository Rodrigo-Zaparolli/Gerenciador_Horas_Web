import 'dart:math' as math;
import 'package:flutter/material.dart';

class PlanningTableViewport extends StatefulWidget {
  const PlanningTableViewport({super.key, required this.child});
  final Widget child;
  @override
  State<PlanningTableViewport> createState() => _PlanningTableViewportState();
}
class _PlanningTableViewportState extends State<PlanningTableViewport> {
  final _controller = ScrollController();
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) => Scrollbar(
    controller: _controller, thumbVisibility: true, trackVisibility: true,
    thickness: 9, interactive: true, scrollbarOrientation: ScrollbarOrientation.bottom,
    notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
    child: SingleChildScrollView(controller: _controller, scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 20),
      child: SizedBox(width: math.max(1420, constraints.maxWidth),
        child: Align(alignment: Alignment.topCenter, heightFactor: 1,
          child: SizedBox(width: 1420, child: widget.child))),
    ),
  ));
}
