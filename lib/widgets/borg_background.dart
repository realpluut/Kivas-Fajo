import 'package:flutter/material.dart';

/// Wraps [child] with a painted "Borg console" backdrop -- glowing green
/// circuitry nodes and faint grid lines on a black void, echoing the dark
/// theme's inspiration image. Sits behind all content; the dark theme's
/// scaffold background is transparent so this shows through everywhere.
class BorgBackground extends StatelessWidget {
  final Widget child;
  const BorgBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: Colors.black)),
        Positioned.fill(child: CustomPaint(painter: _BorgBackgroundPainter())),
        child,
      ],
    );
  }
}

class _Node {
  final double dx, dy, radius;
  final Color color;
  const _Node(this.dx, this.dy, this.radius, this.color);
}

const _green = Color(0xFF39FF14);
const _amber = Color(0xFFFFC400);

// Fractional (0..1) positions so the layout scales to any screen size --
// loosely echoing the reference wallpaper's clusters of glowing nodes.
const _nodes = [
  _Node(0.08, 0.08, 26, _green),
  _Node(0.18, 0.11, 20, _green),
  _Node(0.30, 0.09, 16, _green),
  _Node(0.46, 0.07, 34, _green),
  _Node(0.60, 0.10, 18, _amber),
  _Node(0.74, 0.08, 20, _green),
  _Node(0.50, 0.28, 22, _green),
  _Node(0.62, 0.34, 26, _amber),
  _Node(0.78, 0.40, 24, _green),
  _Node(0.55, 0.48, 20, _green),
  _Node(0.09, 0.55, 22, _green),
  _Node(0.20, 0.58, 18, _green),
  _Node(0.32, 0.56, 20, _green),
  _Node(0.88, 0.20, 60, _green),
  _Node(0.14, 0.80, 16, _green),
  _Node(0.34, 0.85, 20, _amber),
  _Node(0.70, 0.86, 18, _green),
  _Node(0.85, 0.90, 22, _green),
];

// Index pairs into _nodes connected by faint circuit lines.
const _links = [
  [0, 1], [1, 2], [2, 3], [3, 4], [4, 5],
  [3, 6], [6, 7], [7, 8], [6, 9],
  [10, 11], [11, 12],
  [9, 15], [15, 16], [16, 17],
];

class _BorgBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = _green.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    // A handful of faint grid/crosshair lines, like the console's dividers.
    for (final f in [0.12, 0.5, 0.88]) {
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), gridPaint);
    }
    for (final f in [0.15, 0.47, 0.82]) {
      canvas.drawLine(Offset(size.width * f, 0), Offset(size.width * f, size.height), gridPaint);
    }

    final linePaint = Paint()
      ..color = _green.withValues(alpha: 0.10)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (final link in _links) {
      final a = _nodes[link[0]];
      final b = _nodes[link[1]];
      canvas.drawLine(
        Offset(a.dx * size.width, a.dy * size.height),
        Offset(b.dx * size.width, b.dy * size.height),
        linePaint,
      );
    }

    for (final node in _nodes) {
      final center = Offset(node.dx * size.width, node.dy * size.height);
      // Soft outer glow.
      final glow = Paint()
        ..color = node.color.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
      canvas.drawCircle(center, node.radius, glow);
      // Brighter core.
      final core = Paint()
        ..shader = RadialGradient(
          colors: [node.color.withValues(alpha: 0.55), node.color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCircle(center: center, radius: node.radius * 0.6));
      canvas.drawCircle(center, node.radius * 0.6, core);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
