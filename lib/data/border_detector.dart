import 'dart:io';

import 'package:image/image.dart' as img;

class BorderSample {
  final String? color;
  final List<double> cornerLuminance;
  final String debug;
  const BorderSample(this.color, this.cornerLuminance, [this.debug = '']);
}

class _Box {
  final int left, top, width, height;
  const _Box(this.left, this.top, this.width, this.height);
}

/// Finds the border color of the card photographed in [imagePath], trying
/// two strategies:
///
/// 1. Assume the card fills the frame (the "fit the card in frame" guidance
///    given to the user) and sample the photo's own four corners directly.
/// 2. If those corners disagree too much to trust -- a sign the card
///    *doesn't* fill the frame, e.g. sitting loose in a tray with a lot of
///    background visible -- fall back to actually locating the card: find
///    the photo's dominant color (assumed to be the background/tray) and
///    take the bounding box of everything that isn't that color, then
///    re-sample corners from just inside *that* box instead of the raw
///    photo. This works far more reliably the more the tray/background
///    color differs from typical card colors (black/white/silver borders,
///    card art) -- a neutral white or cream tray is a near-worst case,
///    since it has almost no contrast against a white-bordered card. A
///    saturated, uncommon color (bright green, magenta, orange) makes this
///    detection much more robust.
///
/// Either way, only black vs white is classified -- see the corner-sampling
/// helper below for why silver/gold aren't attempted.
Future<BorderSample> sampleBorder(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final image = img.decodeImage(bytes);
  if (image == null) return const BorderSample(null, [], 'could not decode image');

  final direct = _sampleCorners(image, 0, 0, image.width, image.height);
  if (direct.color != null) {
    return BorderSample(direct.color, direct.cornerLuminance, 'direct corners, ${image.width}x${image.height}');
  }
  if (direct.cornerLuminance.length < 2 || _spread(direct.cornerLuminance) <= 80) {
    return BorderSample(null, direct.cornerLuminance, 'direct corners consistent but inconclusive, ${image.width}x${image.height}');
  }

  final box = _findCardBoundingBox(image);
  if (box == null) {
    return BorderSample(null, direct.cornerLuminance, 'direct corners inconsistent; box detection found nothing confident, ${image.width}x${image.height}');
  }
  final boxed = _sampleCorners(image, box.left, box.top, box.width, box.height);
  return BorderSample(
    boxed.color,
    boxed.cornerLuminance,
    'box detected at (${box.left},${box.top}) ${box.width}x${box.height} within ${image.width}x${image.height}',
  );
}

Future<String?> detectBorderColor(String imagePath) async {
  return (await sampleBorder(imagePath)).color;
}

double _spread(List<double> values) {
  return values.reduce((a, b) => a > b ? a : b) - values.reduce((a, b) => a < b ? a : b);
}

/// Samples pixels near the four corners of the rectangle (x0,y0,w,h) within
/// [image] and classifies the border as black, white, or null
/// (inconclusive). Classifies each corner independently and takes a
/// majority vote, rather than averaging all four together, so one corner
/// landing on background/table doesn't wash out an otherwise-clear reading
/// from the other three. Also refuses to guess when the corners disagree
/// too widely with each other (a sign they aren't all sampling the same
/// border) rather than force a vote out of inconsistent data.
///
/// Only distinguishes black from white, not silver/gold: a real
/// white-bordered card measured 146-196 across its four corners under
/// ordinary indoor lighting, and silver/gold are reflective foil whose
/// brightness swings with glare and viewing angle far more than matte
/// black or white cardstock -- not reliably tellable apart by plain
/// average luminance.
BorderSample _sampleCorners(img.Image image, int x0, int y0, int w, int h) {
  final cornerSize = (w * 0.06).round().clamp(4, 200);
  final inset = (w * 0.02).round();

  final corners = [
    (x0 + inset, y0 + inset),
    (x0 + w - inset - cornerSize, y0 + inset),
    (x0 + inset, y0 + h - inset - cornerSize),
    (x0 + w - inset - cornerSize, y0 + h - inset - cornerSize),
  ];

  final luminances = <double>[];
  final classifications = <String>[];
  for (final corner in corners) {
    final cx = corner.$1, cy = corner.$2;
    double rSum = 0, gSum = 0, bSum = 0;
    var count = 0;
    for (var y = cy; y < cy + cornerSize; y += 2) {
      for (var x = cx; x < cx + cornerSize; x += 2) {
        if (x < 0 || y < 0 || x >= image.width || y >= image.height) continue;
        final p = image.getPixel(x, y);
        rSum += p.r;
        gSum += p.g;
        bSum += p.b;
        count++;
      }
    }
    if (count == 0) continue;
    final r = rSum / count, g = gSum / count, b = bSum / count;
    final luminance = (r + g + b) / 3.0;
    luminances.add(luminance);
    final maxDeviation = [(r - luminance).abs(), (g - luminance).abs(), (b - luminance).abs()].reduce((a, b) => a > b ? a : b);
    if (maxDeviation < 22) {
      classifications.add(luminance < 110 ? 'black' : 'white');
    }
  }

  if (luminances.length >= 2 && _spread(luminances) > 80) return BorderSample(null, luminances);
  if (classifications.isEmpty) return BorderSample(null, luminances);

  final counts = <String, int>{};
  for (final c in classifications) {
    counts[c] = (counts[c] ?? 0) + 1;
  }
  final winner = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  final color = winner.value >= 2 ? winner.key : null; // require at least 2 of the (up to 4) corners to agree
  return BorderSample(color, luminances);
}

/// Finds the card's approximate bounding box within [image] by assuming the
/// most common color is the background, then taking the bounding box of
/// pixels sufficiently different from it. Returns null when there's no
/// clearly-dominant background or the resulting "foreground" region is an
/// implausible size to be a card -- i.e. when this approach isn't
/// confident, rather than returning a wild guess.
_Box? _findCardBoundingBox(img.Image image) {
  final small = img.copyResize(image, width: image.width > 160 ? 160 : image.width);
  final w = small.width, h = small.height;
  final total = w * h;
  if (total == 0) return null;

  const step = 24; // quantization step per channel
  final counts = <int, int>{};
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      final key = ((p.r.toInt() ~/ step) << 16) | ((p.g.toInt() ~/ step) << 8) | (p.b.toInt() ~/ step);
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  if (counts.isEmpty) return null;
  final dominant = counts.entries.reduce((a, b) => a.value > b.value ? a : b);
  if (dominant.value / total < 0.2) return null; // no clearly-dominant background color

  final bgR = ((dominant.key >> 16) & 0xFF) * step + step / 2;
  final bgG = ((dominant.key >> 8) & 0xFF) * step + step / 2;
  final bgB = (dominant.key & 0xFF) * step + step / 2;

  const distThreshold = 60.0 * 60.0;
  final xs = <int>[];
  final ys = <int>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      final dr = p.r - bgR, dg = p.g - bgG, db = p.b - bgB;
      if (dr * dr + dg * dg + db * db > distThreshold) {
        xs.add(x);
        ys.add(y);
      }
    }
  }
  final fgFraction = xs.length / total;
  if (fgFraction < 0.05 || fgFraction > 0.9) return null; // implausible size for "the card"

  xs.sort();
  ys.sort();
  int percentile(List<int> sorted, double p) => sorted[(sorted.length * p).clamp(0, sorted.length - 1).floor()];
  final left = percentile(xs, 0.03), right = percentile(xs, 0.97);
  final top = percentile(ys, 0.03), bottom = percentile(ys, 0.97);
  if (right <= left || bottom <= top) return null;

  final scaleX = image.width / w, scaleY = image.height / h;
  return _Box(
    (left * scaleX).round(),
    (top * scaleY).round(),
    ((right - left) * scaleX).round(),
    ((bottom - top) * scaleY).round(),
  );
}
