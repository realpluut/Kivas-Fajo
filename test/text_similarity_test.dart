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
  });
}
