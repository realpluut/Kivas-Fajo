import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'card_repository.dart';
import 'models/card_set.dart';
import 'models/trek_card.dart';
import 'text_similarity.dart';

/// One candidate printing found for an OCR'd card name, with whether its
/// set's year and/or border color match what was detected on the physical
/// card.
class CardMatchCandidate {
  final TrekCard card;
  final CardSet? set;
  final bool yearMatches;
  final bool borderMatches;

  /// True when this set's border color is *known* and disagrees with what
  /// was detected on the photo -- e.g. the set is on record as black-bordered
  /// but the photo read white. Unlike simply not matching (which just means
  /// no data either way), a known contradiction actively rules the printing
  /// out.
  final bool borderContradicted;

  const CardMatchCandidate({
    required this.card,
    required this.set,
    required this.yearMatches,
    required this.borderMatches,
    required this.borderContradicted,
  });

  /// How many independent signals (year, border) confirm this printing.
  /// Used to auto-pick a candidate: the wiki text is inconsistent about
  /// whether card year matches the set's stated release year (e.g.
  /// Collector's Tin cards are physically dated 1994 despite releasing in
  /// 1995), so neither signal alone is trustworthy -- but a printing that
  /// nothing else can match on both is a confident pick.
  int get confidence => (yearMatches ? 1 : 0) + (borderMatches ? 1 : 0);
}

class CardMatchResult {
  final bool hasText;
  final String rawText;
  final String? matchedName;
  final int? detectedYear;
  final String? detectedBorderColor;
  final List<double> cornerLuminance;
  final List<CardMatchCandidate> candidates;

  /// Set only when there's no real ambiguity: either just one printing
  /// matched the name at all, or the detected year/border narrow it down to
  /// a single confident pick among several reprints.
  final CardMatchCandidate? autoPick;

  const CardMatchResult({
    required this.hasText,
    required this.rawText,
    required this.matchedName,
    required this.detectedYear,
    required this.detectedBorderColor,
    required this.cornerLuminance,
    required this.candidates,
    required this.autoPick,
  });

  static const noText = CardMatchResult(
    hasText: false,
    rawText: '',
    matchedName: null,
    detectedYear: null,
    detectedBorderColor: null,
    cornerLuminance: [],
    candidates: [],
    autoPick: null,
  );
}

int? _firstYear(String text) {
  for (final m in RegExp(r'(19[6-9]\d|20[0-3]\d)').allMatches(text)) {
    final y = int.tryParse(m.group(0)!);
    if (y != null) return y;
  }
  return null;
}

/// The first plausible copyright/print year found in the OCR'd text (Star
/// Trek CCG 1st Edition ran 1994-2029ish) -- a proxy for the small copyright
/// line printed on every card, used to prefer the matching printing/set when
/// a card name was reprinted across multiple editions.
///
/// Checked right-to-left across recognized lines first, since the
/// copyright/year text sits in a narrow strip near the card's right edge
/// (see the camera's right-biased focus point in the scanner screens) --
/// this avoids picking up a stray year-like number from flavor/game text
/// elsewhere on the card before ever looking there. Falls back to scanning
/// everything in whatever order ML Kit returned it, in case that strip
/// wasn't read as its own line.
int? extractYear(RecognizedText recognized) {
  final lines = [
    for (final block in recognized.blocks) for (final line in block.lines) line,
  ]..sort((a, b) => b.boundingBox.left.compareTo(a.boundingBox.left));
  for (final line in lines) {
    final y = _firstYear(line.text);
    if (y != null) return y;
  }
  return _firstYear(recognized.text);
}

/// Matches OCR'd text (and, optionally, a photo-detected border color)
/// against the card database: finds the best-matching card name(s), pulls
/// every printing of those names, and figures out whether the detected
/// year/border narrow it down to a single confident pick.
Future<CardMatchResult> matchCardFromOcr({
  required RecognizedText recognized,
  required CardRepository repo,
  required List<String> names,
  String? detectedBorderColor,
  List<double> cornerLuminance = const [],
  // When set, only printings from this set are considered at all -- both
  // the [names] pool passed in and this filter are expected to already be
  // scoped to it (see ContinuousScanScreen's set-filter picker), so a card
  // from any other set reads as no match rather than a wrong-set guess.
  String? restrictToSetId,
}) async {
  final lines = <String>[
    for (final block in recognized.blocks)
      for (final line in block.lines) line.text,
  ];
  if (lines.isEmpty) return CardMatchResult.noText;

  final year = extractYear(recognized);
  final matches = bestMatches<String>(ocrLines: lines, candidates: names, nameOf: (n) => n, minScore: 0.55, limit: 3);
  if (matches.isEmpty) {
    return CardMatchResult(
      hasText: true,
      rawText: recognized.text,
      matchedName: null,
      detectedYear: year,
      detectedBorderColor: detectedBorderColor,
      cornerLuminance: cornerLuminance,
      candidates: const [],
      autoPick: null,
    );
  }

  // Keep names within a small margin of the top score -- OCR noise can put
  // the real match just under a slightly-higher false positive.
  final topScore = matches.first.score;
  final candidateNames = matches.where((m) => m.score >= topScore - 0.08).map((m) => m.value);

  final results = <CardMatchCandidate>[];
  for (final name in candidateNames) {
    for (final printing in await repo.cardsByBaseName(name)) {
      if (restrictToSetId != null && printing.setId != restrictToSetId) continue;
      final set = await repo.setById(printing.setId);
      final knownBorder = set?.borderColor;
      results.add(CardMatchCandidate(
        card: printing,
        set: set,
        yearMatches: year != null && set?.year == year,
        borderMatches: detectedBorderColor != null && knownBorder != null && knownBorder == detectedBorderColor,
        borderContradicted: detectedBorderColor != null && knownBorder != null && knownBorder != detectedBorderColor,
      ));
    }
  }
  // Printings a known border contradicts sort last (very likely wrong), then
  // best-confirmed first, then in the wiki's chronological set order.
  results.sort((a, b) {
    if (a.borderContradicted != b.borderContradicted) return a.borderContradicted ? 1 : -1;
    if (a.confidence != b.confidence) return b.confidence.compareTo(a.confidence);
    return (a.set?.order ?? 0).compareTo(b.set?.order ?? 0);
  });

  CardMatchCandidate? autoPick;
  if (results.length == 1) {
    autoPick = results.first;
  } else {
    // A known border contradiction rules a printing out entirely, not just
    // "no bonus" -- e.g. if the photo reads white, a set on record as
    // black-bordered can't be it, even if nothing else disagrees.
    final viable = results.where((r) => !r.borderContradicted).toList();
    if (viable.length == 1) {
      autoPick = viable.first;
    } else if (viable.isNotEmpty) {
      final topConfidence = viable.first.confidence;
      final atTop = viable.where((r) => r.confidence == topConfidence).toList();
      if (topConfidence > 0 && atTop.length == 1) autoPick = atTop.first;
    }
  }

  return CardMatchResult(
    hasText: true,
    rawText: recognized.text,
    matchedName: matches.first.value,
    detectedYear: year,
    detectedBorderColor: detectedBorderColor,
    cornerLuminance: cornerLuminance,
    candidates: results,
    autoPick: autoPick,
  );
}
