import 'dart:math' as math;
import 'package:flutter/material.dart';

class BetaHologram extends StatelessWidget {
  const BetaHologram({super.key, required this.speaking});
  final bool speaking;
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Holograma da BETA',
      child: TweenAnimationBuilder<double>(
          tween: Tween(end: speaking ? 1 : .25),
          duration: const Duration(milliseconds: 500),
          builder: (_, value, child) => CustomPaint(
              size: const Size(140, 108), painter: _Hologram(value))));
}

class _Hologram extends CustomPainter {
  _Hologram(this.energy);
  final double energy;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, 0);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.cyanAccent.withValues(alpha: .35 + energy * .4);
    canvas.drawOval(const Rect.fromLTWH(-43, 90, 86, 12), stroke);
    canvas.drawOval(const Rect.fromLTWH(-31, 93, 62, 6), stroke);
    canvas.drawCircle(
        const Offset(0, 46),
        41,
        stroke
          ..color = Colors.cyanAccent.withValues(alpha: .16 + energy * .12));
    for (var i = 0; i < 20; i++) {
      final a = i * math.pi / 10;
      canvas.drawLine(Offset(math.cos(a) * 43, 46 + math.sin(a) * 43),
          Offset(math.cos(a) * 46, 46 + math.sin(a) * 46), stroke);
    }
    stroke.color = Colors.cyanAccent.withValues(alpha: .65 + energy * .3);
    final face = Path()
      ..moveTo(-18, 31)
      ..quadraticBezierTo(-18, 12, 0, 12)
      ..quadraticBezierTo(18, 12, 18, 31)
      ..lineTo(15, 49)
      ..lineTo(7, 59)
      ..lineTo(0, 63)
      ..lineTo(-7, 59)
      ..lineTo(-15, 49)
      ..close();
    canvas.drawPath(
        face,
        Paint()
          ..color = Colors.cyanAccent.withValues(alpha: .06 + energy * .08));
    canvas.drawPath(face, stroke);
    final body = Path()
      ..moveTo(-34, 87)
      ..quadraticBezierTo(-33, 75, -10, 69)
      ..lineTo(-8, 59)
      ..moveTo(8, 59)
      ..lineTo(10, 69)
      ..quadraticBezierTo(33, 75, 34, 87)
      ..moveTo(-10, 69)
      ..lineTo(0, 86)
      ..lineTo(10, 69)
      ..moveTo(-17, 31)
      ..lineTo(0, 37)
      ..lineTo(17, 31)
      ..moveTo(0, 13)
      ..lineTo(0, 38)
      ..lineTo(-3, 47)
      ..lineTo(3, 47)
      ..moveTo(-15, 49)
      ..lineTo(0, 54)
      ..lineTo(15, 49);
    canvas.drawPath(body, stroke);
    canvas.drawLine(
        const Offset(-11, 38), const Offset(-5, 39), stroke..strokeWidth = 2);
    canvas.drawLine(const Offset(5, 39), const Offset(11, 38), stroke);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(0, 54), width: 9, height: 1 + energy * 3),
        stroke..strokeWidth = 1);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Hologram oldDelegate) => oldDelegate.energy != energy;
}
