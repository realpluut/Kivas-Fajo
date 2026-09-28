import 'dart:io';

import 'package:image/image.dart' as img;

/// Writes a grayscale copy of the photo at [imagePath] next to it and
/// returns its path (or [imagePath] itself if the image can't be decoded).
/// OCR reads the card's tiny printed title and copyright/year text more
/// reliably off a grayscale image than the original color photo -- colored
/// card art and borders behind that text add per-channel noise that plain
/// grayscale conversion strips out, leaving just the light/dark contrast
/// ML Kit's text recognizer actually uses. Border-color detection
/// deliberately keeps using the original color photo instead (see
/// border_detector.dart) -- it needs the real RGB channels to tell a
/// neutral border from a colored background.
Future<String> grayscaleCopy(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final image = img.decodeImage(bytes);
  if (image == null) return imagePath;
  final gray = img.grayscale(image);
  final grayPath = '$imagePath.gray.jpg';
  await File(grayPath).writeAsBytes(img.encodeJpg(gray));
  return grayPath;
}
