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
  @override
  String toString() => '_Box(left=$left,top=$top,w=$width,h=$height)';
}

/// Finds the border color of the card photographed in [imagePath], trying
/// two strategies:
///
/// 1. Actually locate the card: find the photo's dominant color (assumed to
///    be the background/tray) and take the bounding box of everything that
///    isn't that color, then sample corners from just inside *that* box.
///    This works far more reliably the more the tray/background color
///    differs from typical card colors (black/white/silver borders, card
///    art) -- a saturated, uncommon tray color (bright green, magenta,
///    orange) makes it much more robust; a neutral white or cream tray is a
///    near-worst case, since it has almost no contrast against a
///    white-bordered card.
/// 2. If that doesn't find a confident, meaningfully-smaller-than-the-whole-
///    photo region -- a sign the card genuinely does fill the frame (the
///    "fit the card in frame" guidance given to the user), or that the
///    background has too little contrast to separate from the card at all
///    -- fall back to assuming it fills the frame and sample the photo's
///    own four corners directly.
///
/// Box detection runs *first*, not as a fallback only tried when the direct
/// corners disagree: a photo can be perfectly in focus and still leave a
/// lot of tray visible around the card (sitting loose in a box, not held
/// edge-to-edge), and in that case the photo's own four corners sample the
/// tray, not the card -- consistently, since all four corners agreeing with
/// each other on the *tray*'s color looks exactly like a confident reading
/// of the border, with nothing in that agreement able to tell the
/// difference. Trying to locate the card first avoids ever trusting a
/// confidently-wrong answer like that.
///
/// Either way, only black vs white is classified -- see the corner-sampling
/// helper below for why silver/gold aren't attempted.
Future<BorderSample> sampleBorder(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final image = img.decodeImage(bytes);
  if (image == null) return const BorderSample(null, [], 'could not decode image');

  final box = _findCardBoundingBox(image);
  // Only prefer the located box over the raw photo when it's meaningfully
  // smaller -- i.e. there's real background margin direct corners would
  // otherwise wrongly sample. When the card already fills most of the
  // frame, box detection's own dominant-color assumption gets less
  // reliable (a thin real background margin competing with the card's own
  // large single-color regions, like a solid border, for "most common
  // color"), so there's nothing to gain from preferring it there anyway.
  if (box != null && box.width * box.height < image.width * image.height * 0.8) {
    final boxed = _sampleCorners(image, box.left, box.top, box.width, box.height);
    if (boxed.color != null) {
      return BorderSample(
        boxed.color,
        boxed.cornerLuminance,
        'box detected at (${box.left},${box.top}) ${box.width}x${box.height} within ${image.width}x${image.height}',
      );
    }
  }

  final direct = _sampleCorners(image, 0, 0, image.width, image.height);
  if (direct.color != null) {
    return BorderSample(direct.color, direct.cornerLuminance, 'direct corners, ${image.width}x${image.height}');
  }
  if (direct.cornerLuminance.length < 2 || _spread(direct.cornerLuminance) <= 80) {
    return BorderSample(null, direct.cornerLuminance, 'direct corners consistent but inconclusive, ${image.width}x${image.height}');
  }

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
/// (inconclusive). Classifies each corner independently (requiring its R/G/B
/// channels to be close to each other, i.e. genuinely neutral, not a color
/// cast from background bleed) and takes a majority vote requiring at least
/// two of the (up to four) corners to agree, rather than averaging all four
/// together -- so one corner landing on background, or catching a glare
/// highlight a glossy card's laminate can throw even on an otherwise
/// consistently-dark border, doesn't by itself wash out an otherwise-clear
/// reading from the rest. There's deliberately no separate "corners vary too
/// much overall" rejection on top of that: a single outlier corner is
/// exactly what the majority vote already tolerates, and rejecting on raw
/// spread discarded real, confidently-agreeing majorities just because one
/// other corner read very differently.
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

  if (classifications.isEmpty) return BorderSample(null, luminances);

  final counts = <String, int>{};
  for (final c in classifications) {
    counts[c] = (counts[c] ?? 0) + 1;
  }
  final winner = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  final color = winner.value >= 2 ? winner.key : null; // require at least 2 of the (up to 4) corners to agree
  return BorderSample(color, luminances);
}

/// Finds the card's approximate bounding box within [image] by building a
/// background color *palette* from a thin strip around the photo's outer
/// perimeter, then taking the bounding box of pixels that don't match any
/// of those colors. Returns null when the perimeter doesn't clearly read as
/// background or the resulting "foreground" region is an implausible size
/// to be a card -- i.e. when this approach isn't confident, rather than
/// returning a wild guess.
///
/// Deliberately a palette collected from the edges, not "whichever single
/// quantized color is most common across the whole photo": a real tray is
/// often two-toned (e.g. a white foam box with a colored foam insert
/// cradling the card), and natural lighting gradients can spread even one
/// physical color across several adjacent quantization buckets, so no
/// single bucket may reach a clear majority even though a person looking
/// at the photo would call it obviously one background. Sampling directly
/// from the perimeter sidesteps both problems: whatever colors (however
/// many) actually surround the card there become the background set,
/// without needing any of them individually to dominate.
_Box? _findCardBoundingBox(img.Image image) {
  final small = img.copyResize(image, width: image.width > 160 ? 160 : image.width);
  final w = small.width, h = small.height;
  final total = w * h;
  if (total == 0) return null;

  const step = 24; // quantization step per channel
  const marginFraction = 0.06;
  final marginX = (w * marginFraction).round().clamp(1, w ~/ 2);
  final marginY = (h * marginFraction).round().clamp(1, h ~/ 2);

  int keyOf(img.Pixel p) => ((p.r.toInt() ~/ step) << 16) | ((p.g.toInt() ~/ step) << 8) | (p.b.toInt() ~/ step);

  final backgroundKeys = <int>{};
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final onPerimeter = x < marginX || x >= w - marginX || y < marginY || y >= h - marginY;
      if (!onPerimeter) continue;
      backgroundKeys.add(keyOf(small.getPixel(x, y)));
    }
  }
  if (backgroundKeys.isEmpty) return null;

  final xs = <int>[];
  final ys = <int>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!backgroundKeys.contains(keyOf(small.getPixel(x, y)))) {
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
