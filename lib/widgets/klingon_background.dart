import 'package:flutter/material.dart';

/// Wraps [child] with a painted Klingon-interface-style backdrop -- sharp,
/// jagged angular shapes in blood-red and bronze on a near-black void, with
/// a faint honeycomb-like hazard grid, echoing a militaristic bird-of-prey
/// console rather than the Federation's smooth curves.
class KlingonBackground extends StatelessWidget {
  final Widget child;
  const KlingonBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF0A0505))),
        Positioned.fill(child: CustomPaint(painter: _KlingonBackgroundPainter())),
        child,
      ],
    );
  }
}

const _bloodRed = Color(0xFFC41E1E);
const _bronze = Color(0xFFB08D57);
const _darkRed = Color(0xFF5A0F0F);

class _KlingonBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    _paintHazardStripes(canvas, size);
    _paintJaggedCorner(canvas, size, topLeft: true);
    _paintJaggedCorner(canvas, size, topLeft: false);
  }

  // A row of thin diagonal hazard-stripe accents low on the screen, like a
  // warning strip on a console edge.
  void _paintHazardStripes(Canvas canvas, Size size) {
    final paint = Paint()..color = _darkRed.withValues(alpha: 0.35);
    const stripeWidth = 14.0;
    const gap = 22.0;
    final y = size.height * 0.94;
    final h = size.height * 0.03;
    var x = -size.height;
    while (x < size.width) {
      final path = Path()
        ..moveTo(x, y + h)
        ..lineTo(x + h, y)
        ..lineTo(x + h + stripeWidth, y)
        ..lineTo(x + stripeWidth, y + h)
        ..close();
      canvas.drawPath(path, paint);
      x += stripeWidth + gap;
    }
  }

  // A jagged, bat'leth-like angular blade shape anchored in one top corner,
  // fading toward the center -- angular where the Federation elbow is round.
  void _paintJaggedCorner(Canvas canvas, Size size, {required bool topLeft}) {
    final w = size.width * 0.55;
    final h = size.height * 0.22;
    final sign = topLeft ? 1.0 : -1.0;
    final originX = topLeft ? 0.0 : size.width;

    final points = <Offset>[
      Offset(originX, 0),
      Offset(originX + sign * w * 0.3, 0),
      Offset(originX + sign * w * 0.5, h * 0.35),
      Offset(originX + sign * w * 0.75, h * 0.15),
      Offset(originX + sign * w, h * 0.55),
      Offset(originX + sign * w * 0.6, h * 0.5),
      Offset(originX + sign * w * 0.4, h),
      Offset(originX + sign * w * 0.15, h * 0.6),
      Offset(originX, h * 0.75),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: topLeft ? Alignment.topLeft : Alignment.topRight,
          end: Alignment.center,
          colors: [_bloodRed.withValues(alpha: 0.5), _bloodRed.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // A thin bronze edge along the blade's outer contour for a metallic rim.
    canvas.drawPath(
      path,
      Paint()
        ..color = _bronze.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
