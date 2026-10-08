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

    test('pairs a classification stamp with the card\'s own title when given one (the known collision risk)', () {
      // shortLinePairs itself has no way to know "SCIENCE" is a
      // classification stamp and "Varel" is the real title -- it happily
      // generates this pair (see the "KNOWN GAP" test in
      // text_similarity_test.dart for what it scores against the
      // unrelated real card "Science Vessel"). This is exactly why
      // matchCardFromOcr filters classification stamps out of the pool
      // *before* calling shortLinePairs in its fallback path, rather than
      // relying on shortLinePairs itself to know better -- see
      // isClassificationStampLine below.
      final pairs = shortLinePairs(['Varel', 'SCIENCE', 'Physics']);
      expect(pairs, contains('SCIENCE Varel'));
    });
  });

  group('isClassificationStampLine', () {
    test('matches the four known classification stamps', () {
      expect(isClassificationStampLine('SCIENCE'), isTrue);
      expect(isClassificationStampLine('MEDICAL'), isTrue);
      expect(isClassificationStampLine('SECURITY'), isTrue);
      expect(isClassificationStampLine('ENGINEER'), isTrue);
      expect(isClassificationStampLine('science'), isTrue);
    });

    test('does not match real card titles that start with the same word', () {
      expect(isClassificationStampLine('Science Vessel'), isFalse);
      expect(isClassificationStampLine('Medical Kit'), isFalse);
      expect(isClassificationStampLine('Security Briefing'), isFalse);
      expect(isClassificationStampLine('Engineering Kit'), isFalse);
    });

    test('does not match unrelated text', () {
      expect(isClassificationStampLine('Varel'), isFalse);
      expect(isClassificationStampLine('Tomek'), isFalse);
      expect(isClassificationStampLine(''), isFalse);
    });

    test('filtering classification stamps before pairing removes the collision pair', () {
      // The actual fix: matchCardFromOcr's fallback path filters with
      // this before calling shortLinePairs, so "SCIENCE Varel" is never
      // generated in the first place -- unlike the raw shortLinePairs
      // test above, which deliberately shows what happens without it.
      final lines = ['Varel', 'SCIENCE', 'Physics'];
      final pairableLines = [for (final l in lines) if (!isClassificationStampLine(l)) l];
      final pairs = shortLinePairs(pairableLines);
      expect(pairs, isNot(contains('SCIENCE Varel')));
      expect(pairs, isNot(contains('Varel SCIENCE')));
    });

    test('a Tomek/Engineer scan no longer produces the "ENGINEER Tomek" collision pair', () {
      // The real second case reported: Tomek is Engineer-classification,
      // and "ENGINEER" + "Tomek" scores well against the unrelated real
      // card "Engineering Kit" the same way "SCIENCE" + "Varel" did
      // against "Science Vessel".
      final lines = ['Tomek', 'ENGINEER', 'Astrophysics'];
      final pairableLines = [for (final l in lines) if (!isClassificationStampLine(l)) l];
      final pairs = shortLinePairs(pairableLines);
      expect(pairs, isNot(contains('ENGINEER Tomek')));
      expect(pairs, isNot(contains('Tomek ENGINEER')));
    });
  });

  group('isErrataRarity', () {
    test('matches every observed errata rarity string, including scrape typos', () {
      expect(isErrataRarity('Physical Errata'), isTrue);
      expect(isErrataRarity('Virtual Errata'), isTrue);
      expect(isErrataRarity('Errata'), isTrue);
      // A real scrape artifact seen in the data -- matching on the
      // "errata" substring catches it without needing to fix every typo.
      expect(isErrataRarity('Pgtsical Errata'), isTrue);
    });

    test('does not match ordinary rarities', () {
      expect(isErrataRarity('Common'), isFalse);
      expect(isErrataRarity('Rare'), isFalse);
      expect(isErrataRarity('Uncommon'), isFalse);
      expect(isErrataRarity(null), isFalse);
    });
  });
}
