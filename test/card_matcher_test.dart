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
}
