import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Keep every navigation destination inside its allotted header space.
class AdaptiveHeaderNavigation extends StatelessWidget {
  const AdaptiveHeaderNavigation(
      {super.key, required this.labels, required this.itemBuilder});
  final List<String> labels;
  final Widget Function(int index, bool compact) itemBuilder;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
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
        final compact =
            requiredWidth > constraints.maxWidth || scaler.scale(11) > 15;
        return Row(children: [
          for (var i = 0; i < labels.length; i++)
            if (compact)
              Expanded(child: itemBuilder(i, true))
            else
              itemBuilder(i, false),
        ]);
      });
}
