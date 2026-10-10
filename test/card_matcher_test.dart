import 'package:flutter_test/flutter_test.dart';
import 'package:star_trek_ccg_collector/data/card_matcher.dart';
import 'package:star_trek_ccg_collector/data/models/trek_card.dart';

TrekCard _card({String? rarity}) => TrekCard(
      id: 'test-card',
      pageTitle: 'Test Card',
      name: 'Test Card',
      baseName: 'Test Card',
      setId: 'test-set',
      rarity: rarity,
      type: null,
      affiliation: null,
      printing: null,
      propertyLogo: null,
      lore: null,
      gameText: null,
      characteristics: const [],
      legalCardPools: const [],
      legalRulesSets: const [],
      characters: const [],
      actors: const [],
      externalLinks: const [],
      wikiUrl: '',
      imageUrl: null,
    );

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

  group('propertyLogoFragments', () {
    test('splits a colon-joined logo into its two banner pieces, plus the constant "Star Trek"', () {
      final fragments = propertyLogoFragments(['Star Trek: The Next Generation']);
      expect(fragments, containsAll(['Star Trek', 'The Next Generation']));
    });

    test('keeps the film number with "Star Trek" for numbered films', () {
      final fragments = propertyLogoFragments(['Star Trek II: The Wrath of Khan']);
      expect(fragments, containsAll(['Star Trek II', 'The Wrath of Khan']));
    });

    test('keeps a logo with no colon as-is', () {
      final fragments = propertyLogoFragments(['Deep Space Nine']);
      expect(fragments, contains('Deep Space Nine'));
    });

    test(
        'adds a digit twin of a spelled-out number in the logo -- the real card "Deep Space 9" '
        'shares no bigrams at all with the spelled-out property logo "Deep Space Nine" otherwise', () {
      final fragments = propertyLogoFragments(['Star Trek: Deep Space Nine']);
      expect(fragments, containsAll(['Deep Space Nine', 'Deep Space 9']));
    });
  });

  group('looksLikePropertyLogoLine', () {
    final fragments = propertyLogoFragments(['Star Trek: The Next Generation']);

    test('recognizes a clean read of a banner fragment', () {
      expect(looksLikePropertyLogoLine('THE NEXT GENERATION', fragments), isTrue);
    });

    test(
        'recognizes the actual garbled OCR read reported against a real Neutral Outpost scan '
        '(an "O" misread as "D") -- the card that kept getting recognized as the unrelated '
        'real card "The Next Emanation"', () {
      expect(looksLikePropertyLogoLine('THE NEXT GENERATIDN', fragments), isTrue);
    });

    test('does not flag an unrelated line', () {
      expect(looksLikePropertyLogoLine('OUTPOST', fragments), isFalse);
      expect(looksLikePropertyLogoLine('Neutral', fragments), isFalse);
    });

    test('with no fragments to check against, never flags anything', () {
      expect(looksLikePropertyLogoLine('THE NEXT GENERATIDN', []), isFalse);
    });
  });

  group('isFacilitySubtypeLine', () {
    test('matches the two known Facility subtype banners', () {
      expect(isFacilitySubtypeLine('OUTPOST'), isTrue);
      expect(isFacilitySubtypeLine('STATION'), isTrue);
      expect(isFacilitySubtypeLine('station'), isTrue);
    });

    test('does not match unrelated text', () {
      expect(isFacilitySubtypeLine('Mutation'), isFalse);
      expect(isFacilitySubtypeLine('Deep Space Station K-7'), isFalse);
      expect(isFacilitySubtypeLine(''), isFalse);
    });
  });

  group('stripTrailingPropertyLogo', () {
    final fragments = propertyLogoFragments(['Star Trek: The Original Series']);

    test(
        'strips the actual garbled franchise banner reported glued onto a real title '
        '(Deep Space Station K-7, read as one run-on line with no break before "STAR TREK")', () {
      expect(stripTrailingPropertyLogo('Deep Spoce Station K-7 STAR TREK', fragments), 'Deep Spoce Station K-7');
    });

    test('leaves a line with nothing logo-shaped at the end unchanged', () {
      expect(stripTrailingPropertyLogo('Deep Spoce Station K-7', fragments), 'Deep Spoce Station K-7');
    });

    test('never strips the whole line down to nothing', () {
      expect(stripTrailingPropertyLogo('Star Trek', propertyLogoFragments(['Star Trek'])), 'Star Trek');
    });

    test('with no fragments to check against, never changes the line', () {
      expect(stripTrailingPropertyLogo('Deep Spoce Station K-7 STAR TREK', []), 'Deep Spoce Station K-7 STAR TREK');
    });
  });

  group('isFranchiseNamedCard', () {
    final fragments = propertyLogoFragments([
      'Star Trek: Deep Space Nine',
      'Star Trek: Voyager',
      'Star Trek: Enterprise',
      'Star Trek: First Contact',
      'Star Trek: Insurrection',
    ]);

    test('flags the real cards named after the franchise itself', () {
      expect(isFranchiseNamedCard('Deep Space Nine', fragments), isTrue);
      expect(isFranchiseNamedCard('Voyager', fragments), isTrue);
      expect(isFranchiseNamedCard('Enterprise', fragments), isTrue);
    });

    test(
        'flags the digit-styled real card "Deep Space 9" too, via propertyLogoFragments\' '
        'number-word variant -- the actual reported case: "Oops!" (TTWT) kept losing to it', () {
      expect(isFranchiseNamedCard('Deep Space 9', fragments), isTrue);
      expect(isFranchiseNamedCard('Oops!', fragments), isFalse);
    });

    test(
        'does not flag a real, unrelated card name that merely echoes logo wording -- '
        'a loose threshold here would net "Darmok" (vs. "Armada"), "The Next Emanation" '
        '(vs. "The Next Generation"), "Regenerate" (vs. "Generations"), etc.', () {
      expect(isFranchiseNamedCard('Darmok', fragments), isFalse);
      expect(isFranchiseNamedCard('The Next Emanation', fragments), isFalse);
      expect(isFranchiseNamedCard('Regenerate', fragments), isFalse);
      expect(isFranchiseNamedCard('Lam', fragments), isFalse);
    });

    test('with no fragments to check against, never flags anything', () {
      expect(isFranchiseNamedCard('Voyager', []), isFalse);
    });
  });

  group('CardMatchCandidate.confidence', () {
    test('an ordinary printing is credited for a border match', () {
      final c = CardMatchCandidate(
        card: _card(rarity: 'Uncommon'),
        set: null,
        yearMatches: false,
        borderMatches: true,
        contradicted: false,
      );
      expect(c.confidence, 1);
    });

    test(
        'an Errata printing is NOT credited for a border match -- every physical errata '
        'reprint is black by construction, so matching it is not real evidence '
        '(The Naked Truth / Red Alert!)', () {
      final c = CardMatchCandidate(
        card: _card(rarity: 'Physical Errata'),
        set: null,
        yearMatches: false,
        borderMatches: true,
        contradicted: false,
      );
      expect(c.confidence, 0);
    });

    test('an Errata printing is still credited for a year match -- that signal is unaffected', () {
      final c = CardMatchCandidate(
        card: _card(rarity: 'Physical Errata'),
        set: null,
        yearMatches: true,
        borderMatches: true,
        contradicted: false,
      );
      expect(c.confidence, 1);
    });
  });
}
