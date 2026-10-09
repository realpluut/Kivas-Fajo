import 'package:flutter_test/flutter_test.dart';
import 'package:star_trek_ccg_collector/data/text_similarity.dart';

/// Regression coverage for bestMatches' length-ratio gate (see its doc
/// comment in lib/data/text_similarity.dart). Each case below is a real
/// false match hit during manual scan testing -- short or noisy text on a
/// card scoring deceptively high against an unrelated, longer candidate
/// name purely because it's a near-total bigram subset of it. Lines are
/// taken verbatim from actual "Scan details" raw OCR output where we had
/// it, to keep these anchored in what ML Kit actually produces rather
/// than idealized text.
void main() {
  group('bestMatches rejects unrelated candidates from non-title text', () {
    test('lore name-checking a different real card (Bochra / Geordi La Forge)', () {
      final results = bestMatches<String>(
        ocrLines: const [
          'Bochra',
          'STAR TREK',
          'THE NEXT GENERATION',
          'Once marooned on Galorndon Core with Lt. Commander Geordi La Forge.',
        ],
        candidates: const ['Bochra', 'Geordi La Forge'],
        nameOf: (n) => n,
      );
      expect(results.map((r) => r.value), contains('Bochra'));
      expect(results.map((r) => r.value), isNot(contains('Geordi La Forge')));
    });

    test('classification stamp as a bigram subset of a longer name (Takket / Medical Kit)', () {
      final results = bestMatches<String>(
        ocrLines: const [
          'Takket',
          'MEDICAL',
          'Romulan male trained in Romulan anatomy and medicine. Extensively trained in exobiology.',
          'Exobiology',
        ],
        candidates: const ['Takket', 'Medical Kit'],
        nameOf: (n) => n,
      );
      expect(results.map((r) => r.value), contains('Takket'));
      expect(results.map((r) => r.value), isNot(contains('Medical Kit')));
    });

    test('type header as a bigram subset of a longer name (Romulan Disruptor / Equipment Replicator)', () {
      final results = bestMatches<String>(
        ocrLines: const [
          'EQUIPMENT',
          'STEh ER',
          'THE OEXT GENERATTON',
          'ROMULAN DISRUPTOR',
          'Diretedenergy weapon used by Romulans axd otter',
          'Dces. Disruptor fire can be identfied by o hgh residue of',
          'antigrotons thot linger for severol hours',
        ],
        candidates: const ['Romulan Disruptor', 'Equipment Replicator'],
        nameOf: (n) => n,
      );
      expect(results.map((r) => r.value), contains('Romulan Disruptor'));
      expect(results.first.value, 'Romulan Disruptor');
      expect(results.map((r) => r.value), isNot(contains('Equipment Replicator')));
    });

    test('garbled franchise logo coincidentally resembling short card names (Thei / Tarus)', () {
      final results = bestMatches<String>(
        ocrLines: const [
          'EQUIPMENT',
          'STEh ER',
          'THE OEXT GENERATTON',
          'ROMULAN DISRUPTOR',
          'Diretedenergy weapon used by Romulans axd otter',
        ],
        candidates: const ['Romulan Disruptor', 'Thei', 'Tarus'],
        nameOf: (n) => n,
      );
      expect(results.map((r) => r.value), isNot(contains('Thei')));
      expect(results.map((r) => r.value), isNot(contains('Tarus')));
    });

    test('stat label as a bigram subset of a longer name (Federation Outpost / Shields Up!)', () {
      final results = bestMatches<String>(
        ocrLines: const [
          'FACILITY',
          'STAR TREK',
          'THE NEXT GENERATION',
          'Federation Outpost',
          'Earth is a member of the United Federation of Planets.',
          'SHIELDS',
          '30',
        ],
        candidates: const ['Federation Outpost', 'Shields Up!'],
        nameOf: (n) => n,
      );
      expect(results.map((r) => r.value), contains('Federation Outpost'));
      expect(results.map((r) => r.value), isNot(contains('Shields Up!')));
    });

    test(
        'KNOWN GAP: a merged stat badge can coincidentally match the length of an unrelated name '
        '(this is why card_matcher.dart drops stat badge lines before calling bestMatches at all -- '
        'see isStatBadgeLine in card_matcher_test.dart)', () {
      // "SHIELDS 32" and "Shields Up!" both normalize to exactly 10
      // characters, so no length-ratio threshold can tell them apart --
      // bestMatches alone still matches this. Asserting that here (rather
      // than pretending it doesn't) is the point: it documents why
      // isStatBadgeLine has to filter this out upstream, instead of this
      // function quietly growing a second, overlapping defense.
      final results = bestMatches<String>(
        ocrLines: const ['Federation Outpost', 'SHIELDS 32'],
        candidates: const ['Federation Outpost', 'Shields Up!'],
        nameOf: (n) => n,
      );
      expect(results.map((r) => r.value), contains('Shields Up!'));
    });

    test('a wrapped lore line sharing a distinctive word with an unrelated mission (Q2 / Investigate Time Continuum)', () {
      final results = bestMatches<String>(
        ocrLines: const [
          'Q2',
          'STAR TREK',
          'THE NEXT GENERATION',
          "Member of the Q who observed Q's act of self-sacrifice and",
          're-instated him in the Q continuum.',
        ],
        candidates: const ['Q2', 'Investigate Time Continuum'],
        nameOf: (n) => n,
      );
      expect(results.map((r) => r.value), contains('Q2'));
      expect(results.map((r) => r.value), isNot(contains('Investigate Time Continuum')));
    });

    test(
        'a split title recombined via shortLinePairs beats a franchise-logo coincidence '
        '(Romulan Outpost / The Next Emanation)', () {
      // Without the "Romulan OUTPOST" pair (see card_matcher_test.dart's
      // shortLinePairs test, which confirms this is what actually gets
      // generated from these lines), "The Next Emanation" wins here --
      // its name shares the "THE NEXT" phrase with the garbled franchise
      // logo line, and nothing else clears the length-ratio gate at all.
      // bestMatches alone still returns both (up to `limit` candidates
      // regardless of score gap) -- it's matchCardFromOcr's "within a
      // small margin of the top score" filter, one level up, that drops
      // "The Next Emanation" from the final result once "Romulan
      // Outpost" scores decisively higher. What matters here is that the
      // real title now wins outright instead of never being considered.
      final results = bestMatches<String>(
        ocrLines: const [
          'Romulan',
          'STEHazR',
          'THE NEXT GENEHATIDN',
          'Ronulus is one of the two homeworlds for the Romulans.',
          'OUTPOST',
          'Romulan OUTPOST', // what shortLinePairs adds for this card
        ],
        candidates: const ['Romulan Outpost', 'The Next Emanation'],
        nameOf: (n) => n,
      );
      expect(results.first.value, 'Romulan Outpost');
      expect(results.first.score, 1.0);
      expect(results.first.score - results.last.score, greaterThan(0.08));
    });

    test(
        'KNOWN GAP: pairing a classification stamp with the card\'s OWN title creates a new collision '
        '(this is why card_matcher.dart only falls back to shortLinePairs when single-line matching '
        'finds nothing at all -- see the "two-pass gating" test in card_matcher_test.dart)', () {
      // "SCIENCE" + "Varel" -- a pair shortLinePairs genuinely generates
      // from a real Varel scan -- scores 0.72 against the unrelated real
      // card "Science Vessel", comfortably clearing minScore. Unlike the
      // Outpost case, Varel's own title line *does* read on its own (here,
      // cleanly, at 1.0) -- so trying pairs unconditionally would only add
      // risk here, never benefit. This is the actual regression hit during
      // manual testing: on a noisier frame where "Varel" itself scored
      // lower than 1.0, "SCIENCE Varel" was briefly able to outscore it.
      final results = bestMatches<String>(
        ocrLines: const ['Varel', 'SCIENCE', 'SCIENCE Varel', 'Varel SCIENCE'],
        candidates: const ['Varel', 'Science Vessel', 'Science Kit', 'Science Lab'],
        nameOf: (n) => n,
      );
      expect(results.map((r) => r.value), contains('Science Vessel'));
    });

    test(
        'the same classification-pairing collision for a second classification word '
        '(Tomek / Engineering Kit)', () {
      // Same mechanism, a different classification stamp and a different
      // card -- confirms this isn't specific to "Science"/"Varel", but
      // the whole class of classification-stamp word (Science, Medical,
      // Security, Engineer; see isClassificationStampLine).
      final results = bestMatches<String>(
        ocrLines: const ['Tomek', 'ENGINEER', 'ENGINEER Tomek', 'Tomek ENGINEER'],
        candidates: const ['Tomek', 'Engineering Kit', 'Engineering PADD', 'Engineering Tricorder'],
        nameOf: (n) => n,
      );
      expect(results.map((r) => r.value), contains('Engineering Kit'));
    });

    test('a quoted lore line that IS another real card\'s exact name (The Naked Truth / Red Alert!)', () {
      // The Naked Truth has no game text at all -- its entire text box is
      // the quoted lore line "Red Alert!", which happens to be the exact
      // name of a real, unrelated card. Unlike the Bochra/Q2/Takket cases
      // above, the false-match candidate's name isn't embedded in a longer
      // sentence, so the length-ratio gate alone can't reject it: the
      // quoted line and "Red Alert!" are the same length. The quote marks
      // are the only signal that this is flavor text, not a title.
      final results = bestMatches<String>(
        ocrLines: const ['The Naked Truth', 'STAR TREK', 'THE NEXT GENERATION', '"Red Alert!"'],
        candidates: const ['The Naked Truth', 'Red Alert!'],
        nameOf: (n) => n,
      );
      expect(results.map((r) => r.value), contains('The Naked Truth'));
      expect(results.first.value, 'The Naked Truth');
      expect(results.map((r) => r.value), isNot(contains('Red Alert!')));
    });
  });

  group('bestMatches still finds a clean, correctly-read title', () {
    test('exact single-word title', () {
      final results = bestMatches<String>(
        ocrLines: const ['Bochra', 'STAR TREK', 'THE NEXT GENERATION'],
        candidates: const ['Bochra', 'Picard'],
        nameOf: (n) => n,
      );
      expect(results.first.value, 'Bochra');
      expect(results.first.score, 1.0);
    });

    test('exact multi-word title', () {
      final results = bestMatches<String>(
        ocrLines: const ['EQUIPMENT', 'STAR TREK', 'ROMULAN DISRUPTOR', 'some lore text here'],
        candidates: const ['Romulan Disruptor', 'Klingon Disruptor'],
        nameOf: (n) => n,
      );
      expect(results.first.value, 'Romulan Disruptor');
      expect(results.first.score, 1.0);
    });

    test('a title whose quote marks are part of the name still matches ("Pup")', () {
      // The quote-exclusion added for the Naked Truth/Red Alert! case only
      // disqualifies a quoted line from matching a *non*-quoted candidate
      // name -- "Pup"'s own name is quoted too, so this must still work.
      final results = bestMatches<String>(
        ocrLines: const ['"Pup"', 'STAR TREK', 'DEEP SPACE NINE'],
        candidates: const ['"Pup"', 'Odo'],
        nameOf: (n) => n,
      );
      expect(results.first.value, '"Pup"');
      expect(results.first.score, 1.0);
    });

    test('OCR dropping the quote marks off a quoted title still matches ("Pup")', () {
      // The common real-world failure mode -- OCR misses thin punctuation
      // -- must still work even though the line is no longer "quoted" on
      // either side; the exclusion only triggers when the LINE is quoted
      // and the candidate isn't, never the reverse.
      final results = bestMatches<String>(
        ocrLines: const ['Pup', 'STAR TREK', 'DEEP SPACE NINE'],
        candidates: const ['"Pup"', 'Odo'],
        nameOf: (n) => n,
      );
      expect(results.first.value, '"Pup"');
    });
  });
}
