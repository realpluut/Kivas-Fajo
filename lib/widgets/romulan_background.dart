import 'package:flutter/material.dart';

/// Wraps [child] with a painted Romulan-console backdrop -- a swept,
/// wing-like curve (echoing a warbird's silhouette) in teal-emerald and
/// gunmetal in one corner, with faint concentric ripple arcs suggesting a
/// cloaking field shimmer. Smoothly curved like the Federation's elbows, but
/// swept and asymmetric rather than blocky -- cold and elegant rather than
/// utilitarian or martial.
class RomulanBackground extends StatelessWidget {
  final Widget child;
  const RomulanBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF05100C))),
        Positioned.fill(child: CustomPaint(painter: _RomulanBackgroundPainter())),
        child,
      ],
    );
  }
}

const _romulanGreen = Color(0xFF00E5A0);
const _gunmetal = Color(0xFF8FA3AD);

class _RomulanBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    _paintCloakRipples(canvas, size);
    _paintWarbirdWing(canvas, size);
  }

  // Faint concentric arcs fanning from a top-right origin, like a shimmer
  // where a cloaking field almost -- but not quite -- hides the ship.
  void _paintCloakRipples(Canvas canvas, Size size) {
    final origin = Offset(size.width * 0.92, size.height * 0.06);
    final paint = Paint()
      ..color = _romulanGreen.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 1; i <= 5; i++) {
      final radius = size.width * 0.16 * i;
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: radius),
        2.4,
        2.2,
        false,
        paint,
      );
    }
  }

  // A swept wing silhouette built from smooth curves, sweeping from the
  // top edge down across the left side of the screen -- unlike Klingon's
  // jagged blade, this reads as one continuous, aerodynamic sweep.
  void _paintWarbirdWing(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height * 0.5;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.55, 0)
      ..cubicTo(w * 0.30, h * 0.10, w * 0.20, h * 0.30, w * 0.34, h * 0.46)
      ..cubicTo(w * 0.18, h * 0.42, w * 0.05, h * 0.50, 0, h * 0.62)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomLeft,
          colors: [_romulanGreen.withValues(alpha: 0.35), _gunmetal.withValues(alpha: 0.08)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = _romulanGreen.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // A second, smaller echo of the sweep lower on the screen for balance.
    final lowPath = Path()
      ..moveTo(w, size.height)
      ..lineTo(w * 0.58, size.height)
      ..cubicTo(w * 0.78, size.height - h * 0.14, w * 0.86, size.height - h * 0.28, w * 0.74, size.height - h * 0.4)
      ..cubicTo(w * 0.88, size.height - h * 0.36, w * 0.97, size.height - h * 0.46, w, size.height - h * 0.54)
      ..close();
    canvas.drawPath(lowPath, Paint()..color = _gunmetal.withValues(alpha: 0.18));
    canvas.drawPath(
      lowPath,
      Paint()
        ..color = _romulanGreen.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
