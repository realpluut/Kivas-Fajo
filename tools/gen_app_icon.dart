import 'dart:io';

import 'package:image/image.dart' as img;

/// One-off generator for the launcher-icon source images: the Dominion
/// insignia PNG the user picked has its diamond points nearly touching the
/// canvas edge, which adaptive-icon masking (circle/squircle safe zone) and
/// even plain legacy masking on some launchers would clip. This pads it into
/// two properly-sized canvases for flutter_launcher_icons to consume.
void main() {
  final src = img.decodePng(File('assets/icon/app_icon_source.png').readAsBytesSync())!;

  _padded(src, canvasSize: 1024, artSize: 860, outPath: 'assets/icon/app_icon.png');
  // Adaptive foreground: Android's safe zone is roughly the center 66% of the
  // 108dp canvas, so keep the artwork well inside that.
  _padded(src, canvasSize: 1024, artSize: 620, outPath: 'assets/icon/app_icon_foreground.png');
}

void _padded(img.Image src, {required int canvasSize, required int artSize, required String outPath}) {
  final canvas = img.Image(width: canvasSize, height: canvasSize, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  final scaled = img.copyResize(src, width: artSize, height: artSize, interpolation: img.Interpolation.cubic);
  img.compositeImage(canvas, scaled, dstX: (canvasSize - artSize) ~/ 2, dstY: (canvasSize - artSize) ~/ 2);
  File(outPath).writeAsBytesSync(img.encodePng(canvas));
}
