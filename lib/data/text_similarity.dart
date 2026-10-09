/// Small dependency-free string similarity helper used to match OCR'd card
/// titles (noisy, sometimes missing/extra characters) against the card
/// database. Uses Sorensen-Dice bigram overlap, which is cheap and holds up
/// reasonably well against OCR noise for short titles.
library;

String _normalize(String s) {
  return s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9 ]"), '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _openQuotes = {'"', '“', '‘'};

/// True if [s] opens with a quote mark, e.g. a line of lore quoting
/// dialogue ("Red Alert!") or a card whose own title includes the quotes
/// (`"Pup"`, `"God"`). Checked on the raw string, before [_normalize]
/// strips punctuation and loses the distinction.
///
/// Only the opening quote is required, not a matching closer -- confirmed
/// against two real scans of The Naked Truth, OCR kept the leading `"`
/// both times but dropped the trailing one off "Red Alert!" (it sits
/// right after the "!", and that whole cluster is an easy place for OCR to
/// lose a character). Requiring both ends let the unquoted-looking result
/// straight through.
bool _opensWithQuote(String s) {
  final t = s.trim();
  if (t.isEmpty) return false;
  return _openQuotes.contains(t[0]);
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
  // Which OCR line produced this candidate's best score. A card's game
  // text or lore can happen to name-check a completely different real
  // card (e.g. Bochra's lore mentions "Geordi La Forge"), or a short
  // classification stamp can be a near-total bigram subset of an
  // unrelated card's full name (e.g. "MEDICAL" vs. "Medical Kit") --
  // either can score deceptively close to the true title match despite
  // coming from an entirely different line. Callers use this to only
  // treat two candidates as plausible readings of the *same* title text,
  // not just "something on this card resembles this name."
  final String matchedLine;
  const ScoredMatch(this.value, this.score, this.matchedLine);
}

/// Scores every candidate against every line of OCR text and returns the
/// best-scoring candidates (highest score first), using each candidate's
/// best-matching line (titles can appear on any line of the recognized text).
///
/// [minLengthRatio] rejects a line that's drastically shorter (or longer)
/// than the candidate name even if its bigram score alone looks good.
/// Plain Dice similarity doesn't account for this: a short string that's a
/// near-total bigram subset of a much longer one scores deceptively high
/// regardless of whether it's actually a title -- a classification stamp
/// like "MEDICAL" scores ~0.64 length ratio against the unrelated card
/// "Medical Kit", a stat label like "SHIELDS" scores exactly 0.7 against
/// "Shields Up!", a type header like "EQUIPMENT" scores high against
/// "Equipment Replicator", lore mentioning another real card by name
/// scores high against that card, and even a garbled misread of the
/// franchise logo can coincidentally resemble some short card name. 0.8
/// leaves comfortable room above every one of those (0.7 would just barely
/// let "SHIELDS" through) while a genuine title read off a photo --
/// however noisy -- is never that lopsided in length against its real
/// candidate, so this single, position-independent check rejects all of
/// those cases without needing to know anything about card layout or
/// maintain a list of boilerplate text to exclude.
List<ScoredMatch<T>> bestMatches<T>({
  required List<String> ocrLines,
  required List<T> candidates,
  required String Function(T) nameOf,
  double minScore = 0.5,
  double minLengthRatio = 0.8,
  int limit = 10,
}) {
  final scored = <ScoredMatch<T>>[];
  for (final candidate in candidates) {
    final name = nameOf(candidate);
    final nameLen = _normalize(name).length;
    if (nameLen == 0) continue;
    var best = 0.0;
    var bestLine = '';
    for (final line in ocrLines) {
      final lineLen = _normalize(line).length;
      if (lineLen == 0) continue;
      final ratio = nameLen < lineLen ? nameLen / lineLen : lineLen / nameLen;
      if (ratio < minLengthRatio) continue;
      // A line opening with a quote mark is almost always flavor text
      // quoting dialogue -- which can happen to BE another real card's
      // exact name (The Naked Truth's entire lore is just "Red Alert!")
      // -- rather than a title, so it can't support a match against a
      // candidate whose own name doesn't also open with a quote. Not
      // applied the other way around: a quoted title (`"Pup"`) often
      // loses its quote marks to OCR, and an unquoted line should still
      // be able to match it.
      if (_opensWithQuote(line) && !_opensWithQuote(name)) continue;
      final score = diceSimilarity(name, line);
      if (score > best) {
        best = score;
        bestLine = line;
      }
    }
    if (best >= minScore) scored.add(ScoredMatch(candidate, best, bestLine));
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.take(limit).toList();
}
