import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Keep every navigation destination inside its allotted header space.
class AdaptiveHeaderNavigation extends StatefulWidget {
  const AdaptiveHeaderNavigation(
      {super.key, required this.labels, required this.itemBuilder});
  final List<String> labels;
  final Widget Function(int index) itemBuilder;

  @override
  State<AdaptiveHeaderNavigation> createState() =>
      _AdaptiveHeaderNavigationState();
}

class _AdaptiveHeaderNavigationState extends State<AdaptiveHeaderNavigation> {
  final scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void move(double direction) {
    if (!scroll.hasClients) return;
    final target =
        (scroll.offset + direction * scroll.position.viewportDimension * .8)
            .clamp(0.0, scroll.position.maxScrollExtent);
    scroll.animateTo(target,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        double measure(List<String> labels) {
          var requiredWidth = 0.0;
          for (final label in labels) {
            final painter = TextPainter(
                text: TextSpan(
                    text: label,
                    style: DefaultTextStyle.of(context)
                        .style
                        .copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
                textDirection: Directionality.of(context),
                textScaler: scaler,
                maxLines: 1)
              ..layout();
            requiredWidth += math.max(20, painter.width.ceilToDouble()) + 22;
            painter.dispose();
          }
          return requiredWidth;
        }

        final overflow = measure(widget.labels) > constraints.maxWidth;
        if (!overflow) {
          return Row(children: [
            for (var i = 0; i < widget.labels.length; i++) widget.itemBuilder(i)
          ]);
        }
        // All destinations, including Solicitações, share the same scroll area.
        return Row(children: [
          SizedBox(
              width: 24,
              child: IconButton(
                  tooltip: 'Abas anteriores',
                  padding: EdgeInsets.zero,
                  onPressed: () => move(-1),
                  icon: const Icon(Icons.chevron_left))),
          Expanded(
              child: SingleChildScrollView(
                  controller: scroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < widget.labels.length; i++)
                      widget.itemBuilder(i),
                  ]))),
          SizedBox(
              width: 24,
              child: IconButton(
                  tooltip: 'Próximas abas',
                  padding: EdgeInsets.zero,
                  onPressed: () => move(1),
                  icon: const Icon(Icons.chevron_right))),
        ]);
      });
}
