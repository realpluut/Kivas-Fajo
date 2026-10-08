import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:star_trek_ccg_collector/data/border_detector.dart';

/// Regression coverage for sampleBorder, built around a real failure: a
/// genuinely black-bordered card, sitting in a two-toned tray (plain white
/// box top, colored foam insert around the card), read back as "white".
/// Three separate bugs compounded to cause it, each covered below:
///
/// 1. The raw photo's four corners (assuming the card fills the frame) all
///    landed on tray background, not the card -- and agreed with each
///    other on the tray's color just as "confidently" as a real border
///    would, so the box-location fallback never even ran.
/// 2. Box location itself assumed a single dominant background color; a
///    two-toned tray has no single color reaching that threshold.
/// 3. Once the box was fixed, a glare highlight on the glossy black border
///    pushed one corner's reading far from the other three, and a blanket
///    "corners vary too much" check discarded the whole sample even though
///    the other three corners cleanly agreed on black.
///
/// Images are built in-memory with package:image rather than checking in
/// real card photos, to keep this self-contained and reproducible.
void main() {
  /// Writes [image] as a JPEG to a fresh temp file and returns its path.
  Future<String> writeTemp(img.Image image, String name) async {
    final dir = await Directory.systemTemp.createTemp('border_detector_test');
    final path = '${dir.path}/$name.jpg';
    await File(path).writeAsBytes(img.encodeJpg(image));
    return path;
  }

  /// Builds a photo-ish test image: a two-toned background (plain top
  /// strip + a differently-colored strip around the rest) with a solid
  /// [borderColor] rectangle in the middle standing in for the card,
  /// leaving a real background margin on every side -- the shape of photo
  /// that broke box location before this fix (a card that doesn't fill
  /// the frame, against a background that isn't one single color).
  img.Image buildTwoTonedTrayPhoto({
    required img.Color borderColor,
    int size = 400,
    img.Color? glareCorner,
  }) {
    final image = img.Image(width: size, height: size);
    // Top ~15% is one background tone (e.g. a plain foam box lid)...
    img.fillRect(image, x1: 0, y1: 0, x2: size - 1, y2: (size * 0.15).round(), color: img.ColorRgb8(245, 245, 245));
    // ...the rest of the background is a second, different tone (e.g. a
    // colored foam insert cradling the card) -- deliberately saturated
    // and distinct from both the top strip and the card itself.
    img.fillRect(
      image,
      x1: 0,
      y1: (size * 0.15).round(),
      x2: size - 1,
      y2: size - 1,
      color: img.ColorRgb8(210, 150, 180),
    );
    // The "card": a solid-color rectangle well inside the frame on every
    // side, leaving real background margin all around.
    final left = (size * 0.2).round();
    final top = (size * 0.25).round();
    final right = (size * 0.8).round();
    final bottom = (size * 0.9).round();
    img.fillRect(image, x1: left, y1: top, x2: right, y2: bottom, color: borderColor);

    if (glareCorner != null) {
      // A bright highlight in one corner of the card, the way a glossy
      // laminate catches a light source unevenly -- small enough to only
      // affect one of the four sampled corners.
      final glareSize = ((right - left) * 0.1).round();
      img.fillRect(
        image,
        x1: right - glareSize,
        y1: bottom - glareSize,
        x2: right,
        y2: bottom,
        color: glareCorner,
      );
    }
    return image;
  }

  test('finds a black-bordered card against a two-toned (white + colored) tray', () async {
    final image = buildTwoTonedTrayPhoto(borderColor: img.ColorRgb8(18, 18, 18));
    final path = await writeTemp(image, 'black_two_toned');
    final result = await sampleBorder(path);
    expect(result.color, 'black');
  });

  test('finds a white-bordered card against the same two-toned tray', () async {
    final image = buildTwoTonedTrayPhoto(borderColor: img.ColorRgb8(238, 238, 238));
    final path = await writeTemp(image, 'white_two_toned');
    final result = await sampleBorder(path);
    expect(result.color, 'white');
  });

  test('a glare highlight in one corner does not defeat an otherwise-clear majority', () async {
    // Three corners read a clean dark border; the fourth catches a bright
    // highlight well outside the "neutral enough" per-corner check on its
    // own -- this is exactly the real Latinum Payoff scan that motivated
    // this fix. The majority of three should still carry it.
    final image = buildTwoTonedTrayPhoto(
      borderColor: img.ColorRgb8(18, 18, 18),
      glareCorner: img.ColorRgb8(240, 235, 225),
    );
    final path = await writeTemp(image, 'black_with_glare');
    final result = await sampleBorder(path);
    expect(result.color, 'black');
  });

  test('a card that genuinely fills the frame still reads directly', () async {
    // No real background margin here -- a consistent border right at the
    // image edge (wide enough to fully contain the corner-sampling box,
    // the way a real card's printed border comfortably does), matching
    // the "fit the card in frame" guidance. Box location should find
    // nothing worth preferring, and the direct-corner path should still
    // work exactly as before.
    final size = 400;
    final image = img.Image(width: size, height: size);
    img.fillRect(image, x1: 0, y1: 0, x2: size - 1, y2: size - 1, color: img.ColorRgb8(20, 20, 20));
    img.fillRect(
      image,
      x1: (size * 0.15).round(),
      y1: (size * 0.15).round(),
      x2: (size * 0.85).round(),
      y2: (size * 0.85).round(),
      color: img.ColorRgb8(200, 60, 60),
    );
    final path = await writeTemp(image, 'fills_frame');
    final result = await sampleBorder(path);
    expect(result.color, 'black');
    expect(result.debug, contains('direct corners'));
  });
}
