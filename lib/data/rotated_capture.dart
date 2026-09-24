import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// Re-runs OCR on a 90-degree-clockwise-rotated copy of the photo at
/// [imagePath]. The card's tiny copyright/year line runs vertically along
/// the right edge, printed rotated 90 degrees counter-clockwise (reads
/// bottom-to-top) -- ML Kit reads that unreliably in its original
/// orientation, but rotating the whole photo 90 degrees clockwise turns
/// that strip into ordinary left-to-right text. Returns null if the image
/// can't be decoded.
Future<RecognizedText?> recognizeRotatedForYear(String imagePath, TextRecognizer recognizer) async {
  final bytes = await File(imagePath).readAsBytes();
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final rotated = img.copyRotate(image, angle: 90);
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
