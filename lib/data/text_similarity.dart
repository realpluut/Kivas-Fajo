/// Small dependency-free string similarity helper used to match OCR'd card
/// titles (noisy, sometimes missing/extra characters) against the card
/// database. Uses Sorensen-Dice bigram overlap, which is cheap and holds up
/// reasonably well against OCR noise for short titles.
library;

String _normalize(String s) {
  return s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9 ]"), '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

Set<String> _bigrams(String s) {
  final n = _normalize(s);
  if (n.length < 2) return {n};
  return {for (var i = 0; i < n.length - 1; i++) n.substring(i, i + 2)};
}

/// Returns a 0.0-1.0 similarity score between two strings.
double diceSimilarity(String a, String b) {
  final ba = _bigrams(a);
  final bb = _bigrams(b);
  if (ba.isEmpty || bb.isEmpty) return 0.0;
  final intersection = ba.intersection(bb).length;
  return (2.0 * intersection) / (ba.length + bb.length);
}

class ScoredMatch<T> {
  final T value;
  final double score;
  const ScoredMatch(this.value, this.score);
}

/// Scores every candidate against every line of OCR text and returns the
/// best-scoring candidates (highest score first), using each candidate's
/// best-matching line (titles can appear on any line of the recognized text).
List<ScoredMatch<T>> bestMatches<T>({
  required List<String> ocrLines,
  required List<T> candidates,
  required String Function(T) nameOf,
  double minScore = 0.5,
  int limit = 10,
}) {
  final scored = <ScoredMatch<T>>[];
  for (final candidate in candidates) {
    final name = nameOf(candidate);
    var best = 0.0;
    for (final line in ocrLines) {
      final score = diceSimilarity(name, line);
      if (score > best) best = score;
    }
    if (best >= minScore) scored.add(ScoredMatch(candidate, best));
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.take(limit).toList();
}
