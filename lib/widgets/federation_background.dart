import 'package:flutter/material.dart';

/// Wraps [child] with a painted LCARS/Okudagram-style backdrop -- rounded
/// "elbow" panel blocks in the classic Okuda palette (orange, blue-violet,
/// salmon) on a black void, plus a row of chunky pill buttons like a console
/// sidebar. Sits behind all content; the Federation theme's scaffold
/// background is transparent so this shows through everywhere.
class FederationBackground extends StatelessWidget {
  final Widget child;
  const FederationBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Colors.black)),
        Positioned.fill(child: CustomPaint(painter: _FederationBackgroundPainter())),
        child,
      ],
    );
  }
}

const _orange = Color(0xFFFF9C41);
const _violet = Color(0xFF9999FF);
const _salmon = Color(0xFFFF8577);
const _tan = Color(0xFFCC99CC);

class _FederationBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    _paintElbow(canvas, size, alignTopLeft: true);
    _paintElbow(canvas, size, alignTopLeft: false);
    _paintSidebarPills(canvas, size);
  }

  // A classic LCARS "elbow": a horizontal bar and a vertical bar joined by a
  // quarter-circle, in one corner of the screen.
  void _paintElbow(Canvas canvas, Size size, {required bool alignTopLeft}) {
    final barThickness = size.width * 0.09;
    final armLength = size.height * 0.16;
    final colors = alignTopLeft ? [_orange, _tan, _violet] : [_violet, _salmon, _orange];
    final y = alignTopLeft ? 0.0 : size.height - armLength;

    final path = Path();
    if (alignTopLeft) {
      path.moveTo(0, armLength);
      path.lineTo(0, barThickness * 1.6);
      path.quadraticBezierTo(0, 0, barThickness * 1.6, 0);
      path.lineTo(size.width * 0.42, 0);
      path.lineTo(size.width * 0.42, barThickness);
      path.lineTo(barThickness, barThickness);
      path.quadraticBezierTo(barThickness, barThickness, barThickness, armLength);
      path.close();
    } else {
      path.moveTo(size.width, size.height - armLength);
      path.lineTo(size.width, size.height - barThickness * 1.6);
      path.quadraticBezierTo(size.width, size.height, size.width - barThickness * 1.6, size.height);
      path.lineTo(size.width * 0.58, size.height);
      path.lineTo(size.width * 0.58, size.height - barThickness);
      path.lineTo(size.width - barThickness, size.height - barThickness);
      path.quadraticBezierTo(size.width - barThickness, size.height - barThickness, size.width - barThickness, size.height - armLength);
      path.close();
    }
    canvas.drawPath(path, Paint()..color = colors[0].withValues(alpha: 0.85));

    // A thin accent stripe just inside the bar.
    final stripeRect = alignTopLeft
        ? Rect.fromLTWH(0, armLength + 6, barThickness * 0.4, size.height * 0.06)
        : Rect.fromLTWH(size.width - barThickness * 0.4, y - 6 - size.height * 0.06, barThickness * 0.4, size.height * 0.06);
    canvas.drawRect(stripeRect, Paint()..color = colors[1].withValues(alpha: 0.6));
  }

  void _paintSidebarPills(Canvas canvas, Size size) {
    final colors = [_orange, _violet, _salmon, _tan, _orange, _violet];
    final pillWidth = size.width * 0.05;
    final startY = size.height * 0.30;
    final gap = size.height * 0.018;
    var y = startY;
    for (final color in colors) {
      final h = size.height * (0.03 + 0.02 * (color == _orange ? 1 : 0));
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y, pillWidth, h),
        Radius.circular(pillWidth / 2),
      );
      canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.5));
      y += h + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
