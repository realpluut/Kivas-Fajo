import 'package:flutter_test/flutter_test.dart';
import 'package:star_trek_ccg_collector/data/card_matcher.dart';

/// isStatBadgeLine filters out Ship/Facility stat badges ("SHIELDS 32",
/// "WEAPONS 9", "RANGE 7") before name matching even runs, because a
/// merged label+number line can coincidentally come out the exact same
/// length as an unrelated real card name ("SHIELDS 32" / "Shields Up!"
/// both normalize to 10 characters) -- see text_similarity_test.dart's
/// "KNOWN GAP" case for why a length-ratio check alone can't catch this.
void main() {
  group('isStatBadgeLine', () {
    test('matches a label with its number, any amount of whitespace', () {
      expect(isStatBadgeLine('SHIELDS 32'), isTrue);
      expect(isStatBadgeLine('shields 32'), isTrue);
      expect(isStatBadgeLine('SHIELDS32'), isTrue);
      expect(isStatBadgeLine('WEAPONS 9'), isTrue);
      expect(isStatBadgeLine('RANGE 7'), isTrue);
    });

    test('matches the bare label with no number', () {
      expect(isStatBadgeLine('SHIELDS'), isTrue);
      expect(isStatBadgeLine('WEAPONS'), isTrue);
    });

    test('does not match real card titles that start with the same word', () {
      expect(isStatBadgeLine('Shields Up!'), isFalse);
      expect(isStatBadgeLine('Weapons Locker'), isFalse);
    });

    test('does not match unrelated text', () {
      expect(isStatBadgeLine('ROMULAN DISRUPTOR'), isFalse);
      expect(isStatBadgeLine('Federation Outpost'), isFalse);
      expect(isStatBadgeLine(''), isFalse);
    });
  });

  group('shortLinePairs', () {
    test('combines distant short lines in both orders, letting a split title recombine', () {
      // Actual raw OCR lines read off a Romulan Outpost: the affiliation
      // ("Romulan") prints at the top, "OUTPOST" near the bottom, with
      // lore/game text in between -- the real name "Romulan Outpost"
      // never appears as a single line anywhere on the card.
      final lines = [
        'Romulan',
        'STEHazR',
        'THE NEXT GENEHATIDN',
        'Ronulus is one of the two homeworlds for the Romulans.',
        'Ihe Romulan Stor Empire establishes outposts throughout',
        'its teritory.',
        'Seed one if playing Romulan OR build later at ony',
        'location where a Romulan ENGINEER is present.',
        'OUTPOST',
      ];
      final pairs = shortLinePairs(lines);
      expect(pairs, contains('Romulan OUTPOST'));
      expect(pairs, contains('OUTPOST Romulan'));
      // The long lore/game-text lines never get paired -- only noise and
      // extra comparisons would come from combining whole sentences.
      expect(pairs.any((p) => p.contains('homeworlds')), isFalse);
    });

    test('excludes a line from pairing with itself', () {
      expect(shortLinePairs(['Romulan']), isEmpty);
    });

    test('also pairs a classification stamp with the card\'s own title (the known collision risk)', () {
      // Confirms the regression mechanism directly: shortLinePairs has no
      // way to know "SCIENCE" is a classification stamp and "Varel" is
      // the real title, so it happily generates this pair too. This is
      // exactly why matchCardFromOcr only calls shortLinePairs as a
      // fallback when single-line matching finds nothing at all (see the
      // "KNOWN GAP" test in text_similarity_test.dart for what this pair
      // scores against the unrelated real card "Science Vessel") --
      // never unconditionally, which was the actual bug hit in testing.
      final pairs = shortLinePairs(['Varel', 'SCIENCE', 'Physics']);
      expect(pairs, contains('SCIENCE Varel'));
    });
  });
}
