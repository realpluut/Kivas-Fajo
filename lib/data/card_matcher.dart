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

  /// True when something *known* about this printing disagrees with what
  /// the photo actually showed -- either its border color is on record and
  /// disagrees with what was detected (e.g. set known black-bordered, photo
  /// read white), or it's an Errata-rarity printing but the photo clearly
  /// read a printed year. Errata reprints carry plain reference text on
  /// their border instead of a copyright year (see
  /// https://cardguide.fandom.com/wiki/Latinum_Payoff_(Errata) for an
  /// example), so successfully reading *any* year off the photo is itself
  /// proof it isn't the Errata printing. Unlike simply not matching (which
  /// just means no data either way), a known contradiction actively rules
  /// the printing out.
  final bool contradicted;

  const CardMatchCandidate({
    required this.card,
    required this.set,
    required this.yearMatches,
    required this.borderMatches,
    required this.contradicted,
  });

  /// How many independent signals (year, border) confirm this printing.
  /// Used to auto-pick a candidate: the wiki text is inconsistent about
  /// whether card year matches the set's stated release year (e.g.
  /// Collector's Tin cards are physically dated 1994 despite releasing in
  /// 1995), so neither signal alone is trustworthy -- but a printing that
  /// nothing else can match on both is a confident pick.
  ///
  /// Border is never credited for an Errata-rarity printing: every
  /// physical errata reprint has the same black border by construction
  /// (it's recorded once at the set level, not per card -- see
  /// isErrataRarity), so a detected black border matching one isn't
  /// evidence about which specific original printing is actually in
  /// hand -- it's true of every errata card regardless. Crediting it let
  /// an Errata printing out-score, and silently auto-pick over, the real
  /// original whenever the year wasn't read (most original sets have no
  /// border color on record at all, so they could never earn this point
  /// to begin with -- see The Naked Truth / Red Alert!).
  int get confidence => (yearMatches ? 1 : 0) + (borderMatches && !isErrataRarity(card.rarity) ? 1 : 0);
}

class CardMatchResult {
  final bool hasText;
  final String rawText;
  // Whatever the rotated-strip OCR pass read (see recognizeRotatedForYear),
  // shown alongside rawText in the scan diagnostics so a "year not found"
  // report can be told apart from "that pass read nothing at all" versus
  // "it read something, just not a year" -- otherwise a failure there is
  // invisible, since only the year extracted from it (if any) surfaces
  // anywhere else.
  final String? rotatedRawText;
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
    this.rotatedRawText,
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

// Star Trek CCG 1st Edition's actual print run starts 1994 (per the wiki's
// own set dates) -- narrower than a generic "looks like a year" pattern
// would allow, so an OCR digit misread that still looks year-shaped (e.g.
// misreading a 9 as an 8 and landing on "1985") gets rejected outright
// instead of silently pointing to the wrong printing.
int? _firstYear(String text) {
  for (final m in RegExp(r'(199[4-9]|20[0-3]\d)').allMatches(text)) {
    final y = int.tryParse(m.group(0)!);
    if (y != null) return y;
  }
  return null;
}

final _statBadgePattern = RegExp(r'^(shields|weapons|range)\s*\d*$', caseSensitive: false);

/// True for a Ship/Facility stat badge line ("SHIELDS 32", "WEAPONS 9",
/// "RANGE 7", or the bare label with no number) -- never a card's own
/// title. The label word alone being a near-total bigram subset of a
/// longer unrelated card name is exactly the failure bestMatches' length-
/// ratio gate exists to catch (see its doc comment), but the digits can
/// coincidentally pad the line out to the *same* length as that unrelated
/// name -- "SHIELDS 32" and the real card "Shields Up!" both normalize to
/// 10 characters -- which defeats a length-based check entirely. Unlike a
/// type label or franchise logo (free text that OCR noise can garble into
/// dodging a fuzzy exclusion list), this is a fixed, game-defined print
/// format with no real title ever shaped like it, so it can be recognized
/// and dropped outright instead.
bool isStatBadgeLine(String line) => _statBadgePattern.hasMatch(line.trim());

final _facilitySubtypeWords = {'outpost', 'station'};

/// True for a Facility-type card's subtype banner, printed as a bare word
/// near the bottom of the card ("OUTPOST", "STATION") -- confirmed against
/// the wiki's own category structure (Category:Outpost (Star Trek CCG 1E),
/// Category:Station (Star Trek CCG 1E)) as the only two such banners in
/// this game, and no real card is named either word alone. Same shape and
/// risk profile as isClassificationStampLine's four classification stamps
/// -- a small, closed, always-printed-bare-and-alone set -- not the much
/// larger, free-text card TYPE banner ("EQUIPMENT", "ARTIFACT", ...) that
/// deliberately isn't hardcoded elsewhere in this file (see bestMatches'
/// doc comment above). "STATION" alone bigram-matches the unrelated real
/// card "Mutation" at 0.77 -- well past minScore -- the same way "MEDICAL"
/// does against "Medical Kit", just without a longer real title alongside
/// it (*"Shields Up!"*-style) to lose to instead.
bool isFacilitySubtypeLine(String line) => _facilitySubtypeWords.contains(line.trim().toLowerCase());

// The game's personnel classification stamp is one of exactly these four
// words (confirmed against the wiki's own category structure -- Command,
// Diplomacy, etc. aren't classifications in this game, just skills/roles),
// always printed cleanly on its own as a single bold word, never garbled
// the way the franchise logo sometimes is.
final _classificationStampPattern = RegExp(r'^(science|medical|security|engineer)$', caseSensitive: false);

/// True for a personnel classification stamp line ("SCIENCE", "MEDICAL",
/// "SECURITY", "ENGINEER") -- never a card's own title. Reading it alone
/// is already safe (bestMatches' length-ratio gate rejects e.g. "MEDICAL"
/// against the much longer "Medical Kit"), but pairing it with another
/// short line via shortLinePairs is not: "SCIENCE" + the card's own title
/// "Varel" scores 0.72 against the unrelated real card "Science Vessel",
/// and "ENGINEER" + "Tomek" similarly collides with "Engineering Kit" --
/// both real cards whose names start with the classification word. So
/// this is excluded from the pool shortLinePairs draws from, not just
/// from being treated as a title on its own.
bool isClassificationStampLine(String line) => _classificationStampPattern.hasMatch(line.trim());

/// Breaks each property-logo string on record (e.g. "Star Trek: The Next
/// Generation", "Star Trek II: The Wrath of Khan") into the pieces the
/// physical card actually prints as separate banner lines -- "Star Trek"
/// (or "Star Trek II" for the numbered films) plus whatever follows the
/// colon -- so a garbled OCR read of just one of those lines (see
/// _looksLikePropertyLogoLine) can still be recognized without needing the
/// whole banner to have been read back as a single line.
List<String> propertyLogoFragments(Iterable<String> propertyLogos) {
  final fragments = <String>{'Star Trek'};
  for (final logo in propertyLogos) {
    final colon = logo.indexOf(':');
    if (colon == -1) {
      fragments.add(logo);
      continue;
    }
    fragments.add(logo.substring(0, colon).trim());
    fragments.add(logo.substring(colon + 1).trim());
  }
  return fragments.toList();
}

/// True when [line] is a strong fuzzy match for one of [propertyLogoFragments]
/// -- the show/movie banner text printed on every card ("Star Trek", "The
/// Next Generation", "Deep Space Nine", ...) -- rather than a card's own
/// title. Built from the property logos actually in the database instead of
/// a fixed list (Decipher's wording varies, and scrape typos like "Star
/// Trek: Yoyager" happen), and checked with the same fuzzy scoring as real
/// candidate matching rather than an exact/regex check, because OCR garbles
/// this stylized banner text unpredictably -- an exact exclusion list keeps
/// missing new garbled variants (see bestMatches' doc comment on why a
/// franchise-logo exclusion list was dropped in favor of the length-ratio
/// gate in the first place).
/// Strips a trailing run of 1-3 words from [line] when that suffix is a
/// strong, near-exact match for one of [propertyLogoFragments] -- a card's
/// own title and its franchise banner sometimes print close enough
/// together that OCR reads them as a single run-on line with no break
/// ("Deep Spoce Station K-7 STAR TREK"), which pushes the line's length
/// well past the real candidate's via bestMatches' length-ratio gate and
/// loses it entirely. Tries the longest suffix first so "STAR TREK" (two
/// words) strips as one unit rather than leaving a dangling "STAR" behind.
/// Deliberately strict (0.8/0.8, vs. looksLikePropertyLogoLine's 0.6/0.6)
/// since this changes the line itself rather than just classifying it --
/// a real multi-word title that happens to end in a franchise-ish word
/// ("U.S.S. Voyager") must not get truncated into something that no
/// longer matches its own card. Only ever consulted as a last-resort
/// fallback (see matchCardFromOcr) after that title would already have
/// matched on its own unstripped, so a case like that never actually
/// reaches this function in practice.
String stripTrailingPropertyLogo(String line, List<String> propertyLogoFragments) {
  if (propertyLogoFragments.isEmpty) return line;
  final words = line.trim().split(RegExp(r'\s+'));
  for (var take = 3; take >= 1; take--) {
    if (words.length <= take) continue;
    final suffix = words.sublist(words.length - take).join(' ');
    final hit = bestMatches<String>(
      ocrLines: [suffix],
      candidates: propertyLogoFragments,
      nameOf: (f) => f,
      minScore: 0.8,
      minLengthRatio: 0.8,
      limit: 1,
    );
    if (hit.isNotEmpty) return words.sublist(0, words.length - take).join(' ');
  }
  return line;
}

bool looksLikePropertyLogoLine(String line, List<String> propertyLogoFragments) {
  if (propertyLogoFragments.isEmpty) return false;
  return bestMatches<String>(
    ocrLines: [line],
    candidates: propertyLogoFragments,
    nameOf: (f) => f,
    minScore: 0.6,
    minLengthRatio: 0.6,
    limit: 1,
  ).isNotEmpty;
}

/// True when [candidateName] is itself (near-exactly) one of the franchise
/// banner fragments -- the handful of real cards named "Deep Space Nine",
/// "Enterprise", "Voyager", "First Contact", "Insurrection", "Lower Decks",
/// "The Final Frontier", "The Undiscovered Country". Deliberately much
/// stricter than [looksLikePropertyLogoLine] (0.95/0.9 vs. 0.6/0.6):
/// that one tolerates OCR noise when checking a *line* someone is trying to
/// read as a title, where a loose match is still useful signal; this one
/// classifies a *candidate name itself*, where a loose threshold would
/// wrongly net real, unrelated card names that merely echo logo wording
/// ("Darmok" vs. "Armada", "The Next Emanation" vs. "The Next Generation",
/// "Regenerate" vs. "Generations", ...) -- confirmed against the full
/// catalog to land on exactly those eight names and nothing else.
bool isFranchiseNamedCard(String candidateName, List<String> propertyLogoFragments) {
  if (propertyLogoFragments.isEmpty) return false;
  return bestMatches<String>(
    ocrLines: [candidateName],
    candidates: propertyLogoFragments,
    nameOf: (f) => f,
    minScore: 0.95,
    minLengthRatio: 0.9,
    limit: 1,
  ).isNotEmpty;
}

/// True for an Errata-rarity printing ("Physical Errata", "Virtual Errata",
/// bare "Errata", and scrape typos like "Pgtsical Errata" -- matches on the
/// "errata" substring rather than the exact string for that reason). These
/// are reference reprints carrying corrected rules text, not a separate
/// physical card with its own copyright year printed on it -- so reading a
/// real year off the photo is itself proof the scanned card isn't one of
/// these (see [CardMatchCandidate.contradicted]).
bool isErrataRarity(String? rarity) => rarity != null && rarity.toLowerCase().contains('errata');

/// Every short line from [lines] concatenated with every other short line,
/// in both orders. Some card types print their unique name split across
/// two distant lines instead of one: an Outpost shows its affiliation at
/// the top ("Romulan") and "OUTPOST" near the bottom, below the art and
/// all the lore/game text, with the real name "Romulan Outpost" never
/// appearing as a single line anywhere. Neither fragment alone is long
/// enough to clear bestMatches' length-ratio gate against the full
/// two-word name, so without this, that real title could never even be
/// considered as a candidate -- leaving the field open for a coincidental
/// match elsewhere on the card to win by default. Pairing every short
/// line with every other (both orders, since which fragment prints first
/// isn't fixed) lets a split title combine back into one matchable line,
/// the same as if it had been printed as one to begin with.
///
/// Bounded to lines of [maxPartLength] or less (a generous cutoff for a
/// few-word title fragment) so this doesn't start pairing up whole
/// lore/game-text sentences and blow up the number of comparisons for no
/// benefit.
List<String> shortLinePairs(List<String> lines, {int maxPartLength = 25}) {
  final shortLines = [for (final l in lines) if (l.trim().length <= maxPartLength) l];
  return [
    for (var i = 0; i < shortLines.length; i++)
      for (var j = 0; j < shortLines.length; j++)
        if (i != j) '${shortLines[i]} ${shortLines[j]}',
  ];
}

/// The first plausible copyright/print year found across [passes] (Star Trek
/// CCG 1st Edition ran 1994-2029ish) -- a proxy for the small copyright line
/// printed on every card, used to prefer the matching printing/set when a
/// card name was reprinted across multiple editions.
///
/// [passes] is checked in order, and within each pass, lines are checked
/// right-to-left -- the copyright/year text sits in a narrow strip near the
/// card's right edge, printed sideways (see recognizeRotatedForYear, which
/// supplies a rotated-image OCR pass so that strip reads normally instead of
/// vertically), so callers should put that pass first. This avoids picking
/// up a stray year-like number from flavor/game text elsewhere on the card
/// before ever looking there. Falls back to scanning each pass' full text in
/// whatever order ML Kit returned it, in case the strip wasn't read as its
/// own line.
int? extractYear(List<RecognizedText> passes) {
  for (final recognized in passes) {
    final lines = [
      for (final block in recognized.blocks) for (final line in block.lines) line,
    ]..sort((a, b) => b.boundingBox.left.compareTo(a.boundingBox.left));
    for (final line in lines) {
      final y = _firstYear(line.text);
      if (y != null) return y;
    }
  }
  for (final recognized in passes) {
    final y = _firstYear(recognized.text);
    if (y != null) return y;
  }
  return null;
}

/// Matches OCR'd text (and, optionally, a photo-detected border color)
/// against the card database: finds the best-matching card name(s), pulls
/// every printing of those names, and figures out whether the detected
/// year/border narrow it down to a single confident pick.
Future<CardMatchResult> matchCardFromOcr({
  required RecognizedText recognized,
  // OCR pass over a rotated copy of the same photo -- see
  // recognizeRotatedForYear -- used only to help find the sideways-printed
  // year; the un-rotated [recognized] pass above is still what drives name
  // matching. Optional since not every caller has one to offer.
  RecognizedText? rotatedRecognized,
  required CardRepository repo,
  required List<String> names,
  // Used to recognize an OCR'd read of a card's franchise banner text (see
  // propertyLogoFragments) so it can't masquerade as a false title match --
  // see the comment where this is used, below. Optional since not every
  // caller has it to offer; matching just loses that extra safety net.
  List<String> propertyLogoFragments = const [],
  String? detectedBorderColor,
  List<double> cornerLuminance = const [],
  // When set, only printings from this set are considered at all -- both
  // the [names] pool passed in and this filter are expected to already be
  // scoped to it (see ContinuousScanScreen's set-filter picker), so a card
  // from any other set reads as no match rather than a wrong-set guess.
  String? restrictToSetId,
}) async {
  final allLines = <String>[
    for (final block in recognized.blocks) for (final line in block.lines) line.text,
  ];
  if (allLines.isEmpty) return CardMatchResult.noText;

  // Ship/Facility stat badges ("SHIELDS <number>", "WEAPONS <number>",
  // "RANGE <number>") can coincidentally come out the exact same length
  // as an unrelated real card name -- see isStatBadgeLine's doc comment --
  // so they're dropped outright before matching rather than relying on a
  // length check to catch them.
  final filteredLines = [for (final l in allLines) if (!isStatBadgeLine(l)) l];
  final lines = filteredLines.isNotEmpty ? filteredLines : allLines;

  final year = extractYear([?rotatedRecognized, recognized]);
  // Matches against every recognized line, not just a guessed "title
  // line" -- earlier attempts at guessing which line/row was the title
  // (by position, or by excluding known type/franchise-logo text) kept
  // breaking in new ways: a classification stamp ("MEDICAL"), a type
  // header ("EQUIPMENT"), lore name-checking a different real card
  // ("Geordi La Forge"), or even the franchise logo itself garbled just
  // enough to dodge the exclusion list ("STEh ER" for "STAR TREK") could
  // each end up anchoring the search on the wrong line, losing the real
  // title entirely even when it was read perfectly. bestMatches' length
  // ratio requirement (see text_similarity.dart) rejects all of those
  // directly, without needing to know anything about card layout: each
  // one is short/noisy text scoring deceptively high against a much
  // longer candidate name purely because it's a near-complete subset of
  // it, and a real title match is never that lopsided in length.
  var matches = bestMatches<String>(ocrLines: lines, candidates: names, nameOf: (n) => n, minScore: 0.55, limit: 3);
  // A single-line match grounded solely on a Facility subtype banner
  // ("OUTPOST", "STATION") is exactly the kind of coincidence
  // isStatBadgeLine/isClassificationStampLine already guard against
  // elsewhere -- see isFacilitySubtypeLine. Unlike those, this word is
  // also the piece shortLinePairs needs to recombine a split title
  // ("Neutral" + "OUTPOST"), so it can't just be dropped from the line
  // pool outright the way stat badges are -- only a match grounded solely
  // on it gets discarded here, leaving the word itself free to still take
  // part in pairing below.
  matches = [for (final m in matches) if (!isFacilitySubtypeLine(m.matchedLine)) m];
  // Only fall back to combining short-line pairs (see shortLinePairs) when
  // single-line matching found nothing at all -- e.g. a split title like
  // an Outpost's "Romulan" / "OUTPOST". Trying pairs unconditionally
  // caused its own false matches: pairing a classification stamp with the
  // card's own (even cleanly-read) title -- "SCIENCE" + "Varel" -- scores
  // high enough against an unrelated real card with a similar name
  // ("Science Vessel") to occasionally outscore "Varel" itself on a
  // noisier frame, a collision that single-line matching alone would
  // never have been vulnerable to. Gating this behind "nothing else
  // matched" keeps the split-title fix for the cards that actually need
  // it without opening that door for every other card.
  //
  // One more condition reopens that gate even when something *did* match:
  // a garbled read of the franchise banner can itself coincidentally clear
  // minScore against an unrelated real card -- an Outpost's "Star Trek:
  // The Next Generation" logo, misread as "THE NEXT GENERATIDN", scores
  // 0.59 against the real card "The Next Emanation", which shares its
  // "The Next ___" opening. That's a real single-line match (so the
  // isEmpty check alone lets it through), but a weak, coincidental one,
  // from a line that's provably banner text, not a title -- so it's
  // treated the same as finding nothing: pairing still gets a chance, and
  // the two pools compete on score below rather than pairing being
  // skipped outright. The 0.85 floor keeps this from ever firing on a
  // genuine, cleanly-read match -- including the handful of real cards
  // whose own title *is* a franchise name ("Voyager", "Enterprise",
  // "Deep Space Nine", ...), which score far above it against their own
  // exact name.
  final topIsWeakLogoMatch = matches.isNotEmpty &&
      matches.first.score < 0.85 &&
      looksLikePropertyLogoLine(matches.first.matchedLine, propertyLogoFragments);
  if (matches.isEmpty || topIsWeakLogoMatch) {
    // Even in the fallback, a classification stamp never belongs in a
    // pair -- it's not a piece of a split title the way "Romulan" and
    // "OUTPOST" are, just a word that happens to prefix-match unrelated
    // real cards (see isClassificationStampLine).
    final pairableLines = [for (final l in lines) if (!isClassificationStampLine(l)) l];
    // A run-on line with the franchise banner glued onto the end of the
    // real title (see stripTrailingPropertyLogo) only ever needs trying
    // here, in the same already-gated fallback lane as pairing -- a title
    // that already matched cleanly on its own unstripped never reaches
    // this far, so stripping can't touch it.
    final strippedLines = [for (final l in lines) stripTrailingPropertyLogo(l, propertyLogoFragments)];
    final pairedLines = [...lines, ...shortLinePairs(pairableLines), ...strippedLines];
    final pairedMatches = bestMatches<String>(ocrLines: pairedLines, candidates: names, nameOf: (n) => n, minScore: 0.55, limit: 3);
    matches = matches.isEmpty
        ? pairedMatches
        : ([...matches, ...pairedMatches]..sort((a, b) => b.score.compareTo(a.score))).take(3).toList();
  }
  if (matches.isEmpty) {
    return CardMatchResult(
      hasText: true,
      rawText: recognized.text,
      rotatedRawText: rotatedRecognized?.text,
      matchedName: null,
      detectedYear: year,
      detectedBorderColor: detectedBorderColor,
      cornerLuminance: cornerLuminance,
      candidates: const [],
      autoPick: null,
    );
  }

  // A handful of real cards are named after the franchise itself ("Deep
  // Space Nine", "Enterprise", "Voyager", ...) -- see isFranchiseNamedCard.
  // Their own property-logo banner, printed on literally every card from
  // that franchise, scores a perfect match against their name too, so it's
  // barely any evidence this particular card is the one named after it
  // rather than any other card sharing the same logo -- reading "DEEP
  // SPACE NINE" off a DS9 personnel card's own franchise banner ties the
  // real card "Deep Space Nine" with that personnel's own (also perfectly
  // read) title, "Lam", on an unrelated line, and only wins the tie by
  // chance of sort order. When something else in the same OCR text *also*
  // cleared the bar on a different line, that's real discriminating
  // evidence and should win instead -- a franchise-named candidate only
  // stands on its own when nothing else matched at all, which is exactly
  // the case of genuinely scanning that card with nothing else
  // coincidentally matching.
  final nonFranchiseNamed = matches.where((m) => !isFranchiseNamedCard(m.value, propertyLogoFragments)).toList();
  if (nonFranchiseNamed.isNotEmpty) matches = nonFranchiseNamed;

  // Keep names within a small margin of the top score -- OCR noise can put
  // the real match just under a slightly-higher false positive -- but only
  // when they're competing readings of the *same* OCR line as the top
  // match. Without this, a name that happens to appear in the card's own
  // lore/game text (Bochra's lore mentions "Geordi La Forge") or a short
  // classification stamp that's a near-total bigram subset of an unrelated
  // card's full name ("MEDICAL" vs. "Medical Kit") scores close enough to
  // get treated as an alternate printing of a completely different card.
  final topScore = matches.first.score;
  final titleLine = matches.first.matchedLine;
  final candidateNames =
      matches.where((m) => m.score >= topScore - 0.08 && m.matchedLine == titleLine).map((m) => m.value);

  final results = <CardMatchCandidate>[];
  for (final name in candidateNames) {
    for (final printing in await repo.cardsByBaseName(name)) {
      if (restrictToSetId != null && printing.setId != restrictToSetId) continue;
      final set = await repo.setById(printing.setId);
      final knownBorder = set?.borderColor;
      final borderContradicted = detectedBorderColor != null && knownBorder != null && knownBorder != detectedBorderColor;
      final errataButYearRead = year != null && isErrataRarity(printing.rarity);
      results.add(CardMatchCandidate(
        card: printing,
        set: set,
        yearMatches: year != null && set?.year == year,
        borderMatches: detectedBorderColor != null && knownBorder != null && knownBorder == detectedBorderColor,
        contradicted: borderContradicted || errataButYearRead,
      ));
    }
  }
  // Printings a known contradiction rules out sort last (very likely
  // wrong), then best-confirmed first, then in the wiki's chronological
  // set order.
  results.sort((a, b) {
    if (a.contradicted != b.contradicted) return a.contradicted ? 1 : -1;
    if (a.confidence != b.confidence) return b.confidence.compareTo(a.confidence);
    return (a.set?.order ?? 0).compareTo(b.set?.order ?? 0);
  });

  CardMatchCandidate? autoPick;
  if (results.length == 1) {
    autoPick = results.first;
  } else {
    // A known contradiction rules a printing out entirely, not just "no
    // bonus" -- e.g. if the photo reads white, a set on record as
    // black-bordered can't be it, and if the photo read a real year, an
    // Errata reprint (no printed year at all) can't be it either, even if
    // nothing else disagrees.
    final viable = results.where((r) => !r.contradicted).toList();
    if (viable.length == 1) {
      autoPick = viable.first;
    } else if (viable.isNotEmpty) {
      final topConfidence = viable.first.confidence;
      final atTop = viable.where((r) => r.confidence == topConfidence).toList();
      if (topConfidence > 0 && atTop.length == 1) {
        autoPick = atTop.first;
      } else if (topConfidence == 0 && atTop.length > 1) {
        // No year or border evidence either way for any of them. An
        // Errata reprint is a niche reference product -- far more often
        // someone's scanning the genuine original than its corrected
        // reissue -- so it shouldn't win a bare tie just because nothing
        // ruled it out, as long as exactly one non-Errata printing is
        // still in the running. Leaves a real multi-printing ambiguity
        // (more than one non-Errata candidate) for a manual pick, same
        // as before.
        final nonErrata = atTop.where((r) => !isErrataRarity(r.card.rarity)).toList();
        if (nonErrata.length == 1) autoPick = nonErrata.first;
      }
    }
  }

  return CardMatchResult(
    hasText: true,
    rawText: recognized.text,
    rotatedRawText: rotatedRecognized?.text,
    matchedName: matches.first.value,
    detectedYear: year,
    detectedBorderColor: detectedBorderColor,
    cornerLuminance: cornerLuminance,
    candidates: results,
    autoPick: autoPick,
  );
}
