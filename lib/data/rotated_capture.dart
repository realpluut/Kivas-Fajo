import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// Re-runs OCR on a cropped, upscaled, 90-degree-clockwise-rotated copy of
/// the photo at [imagePath]. The card's tiny copyright/year line runs
/// vertically along the right edge, printed rotated 90 degrees
/// counter-clockwise (reads bottom-to-top) -- ML Kit reads that unreliably
/// in its original orientation and at its original size (both misses and
/// misreads, e.g. reading a 9 as an 8), but cropping to just that
/// right-hand strip, scaling it up, and rotating it 90 degrees clockwise
/// turns it into ordinary-sized, ordinary-oriented left-to-right text.
/// Returns null if the image can't be decoded.
Future<RecognizedText?> recognizeRotatedForYear(String imagePath, TextRecognizer recognizer) async {
  final bytes = await File(imagePath).readAsBytes();
  final image = img.decodeImage(bytes);
  if (image == null) return null;

  // Generous width -- the exact strip position drifts with how the card is
  // framed, and it's cheap to OCR a bit of the card's art/border alongside it.
  final cropLeft = (image.width * 0.7).round().clamp(0, image.width - 1);
  final strip = img.copyCrop(image, x: cropLeft, y: 0, width: image.width - cropLeft, height: image.height);
  final upscaled = img.copyResize(strip, width: strip.width * 3, interpolation: img.Interpolation.cubic);
  final rotated = img.copyRotate(upscaled, angle: 90);
  final rotatedPath = '$imagePath.rot.jpg';
  await File(rotatedPath).writeAsBytes(img.encodeJpg(rotated));
  try {
    return await recognizer.processImage(InputImage.fromFilePath(rotatedPath));
  } finally {
    try {
      await File(rotatedPath).delete();
    } catch (_) {
      // Best-effort cleanup of the temp rotated copy.
    }
  }
}
