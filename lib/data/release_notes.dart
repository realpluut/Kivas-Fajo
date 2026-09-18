/// The version shown in Settings and at the top of the release notes page.
/// Bump this (and add a matching [ReleaseNote] at the top of [kReleaseNotes])
/// whenever a set of related fixes/features ships -- grouped by round of
/// work, not one entry per individual change.
const String kAppVersionLabel = '1.10 Beta';

enum ReleaseTag { initial, feature, bugFix, dataFix }

extension ReleaseTagLabel on ReleaseTag {
  String get label => switch (this) {
        ReleaseTag.initial => 'Initial release',
        ReleaseTag.feature => 'Feature',
        ReleaseTag.bugFix => 'Bug fix',
        ReleaseTag.dataFix => 'Data fix',
      };
}

class ReleaseNote {
  final String version;
  final ReleaseTag tag;
  final String title;
  final List<String> bullets;
  const ReleaseNote({required this.version, required this.tag, required this.title, required this.bullets});
}

/// Newest first -- this reads as a "what's new" feed, not a history book.
const List<ReleaseNote> kReleaseNotes = [
  ReleaseNote(
    version: '1.10 Beta',
    tag: ReleaseTag.feature,
    title: 'Backup, in-app manual & release notes',
    bullets: [
      'Export your collection to a backup file and import it back -- Settings > Backup. Restoring only overwrites cards the backup actually covers.',
      'This manual and the version history are now built into the app, not just the online copy.',
    ],
  ),
  ReleaseNote(
    version: '1.09 Beta',
    tag: ReleaseTag.dataFix,
    title: 'Blaze of Glory foils',
    bullets: [
      'Split Blaze of Glory into two sets -- the base 130-card set and a new 18-card Blaze of Glory Foil Cards set -- since the foil variants had been mixed into the same list as their normal counterparts with nothing to tell them apart.',
    ],
  ),
  ReleaseNote(
    version: '1.08 Beta',
    tag: ReleaseTag.bugFix,
    title: 'Sorting & type data',
    bullets: [
      'Fixed a case-sensitivity bug where all-caps names like "DNA Clues" sorted ahead of names like "Dal\'Rok" instead of true alphabetical order.',
      'Normalized 58 cards across the database with inconsistently-cased types (stray lowercase "Q dilemma" / "Q event" / "Q interrupt" variants), which had been silently splitting into duplicate sections or dropping out of their proper group entirely.',
    ],
  ),
  ReleaseNote(
    version: '1.07 Beta',
    tag: ReleaseTag.feature,
    title: 'Bulk scan set scope',
    bullets: [
      'Added a scope picker to bulk scan: restrict matching to one chosen set for faster, more accurate results, or leave it on All Sets for a mixed box.',
    ],
  ),
  ReleaseNote(
    version: '1.06 Beta',
    tag: ReleaseTag.dataFix,
    title: 'Starter Deck II',
    bullets: [
      'Split the single Starter Deck II listing -- which had silently mixed two separate real print runs (1998 original and 2000 reprint) into one 16-card set -- into two proper sets.',
    ],
  ),
  ReleaseNote(
    version: '1.05 Beta',
    tag: ReleaseTag.feature,
    title: 'Personnel & Ship sorting',
    bullets: [
      'Personnel and Ship cards within a set are now grouped by affiliation (all Borg together, then Federation, and so on) instead of one flat alphabetical list.',
    ],
  ),
  ReleaseNote(
    version: '1.04 Beta',
    tag: ReleaseTag.feature,
    title: 'Scanner overhaul',
    bullets: [
      'Single-shot scanning now opens a live in-app camera preview and analyzes the photo immediately on capture, instead of handing off to the phone\'s camera app and its confirm/retake screen.',
      'Bulk scan now gives audio feedback: one tone for a successful add, a different one when a match needs your attention.',
    ],
  ),
  ReleaseNote(
    version: '1.03 Beta',
    tag: ReleaseTag.feature,
    title: 'Swipe between cards',
    bullets: [
      'Opening a card from a set\'s list now supports swiping left/right to the next/previous card in that same filtered, sorted order.',
    ],
  ),
  ReleaseNote(
    version: '1.02 Beta',
    tag: ReleaseTag.bugFix,
    title: 'Collection accuracy',
    bullets: [
      'Fixed a tap-handling bug that could add two copies of a card from a single scan (affected both single-shot and bulk scan).',
      'Fixed unmarking a card as Owned -- individually, or via "Clear owned in this set" -- not resetting its quantity back to 0.',
      'A quantity of 0 no longer shows as a number in card lists or the detail page.',
    ],
  ),
  ReleaseNote(
    version: '1.01 Beta',
    tag: ReleaseTag.dataFix,
    title: 'First Contact card types',
    bullets: [
      'Corrected 3 First Contact cards mislabeled as Dilemma instead of Equipment (Assimilation Table, Starfleet Type III Phaser Rifle, Tommygun), matching a fix made on the source wiki.',
    ],
  ),
  ReleaseNote(
    version: '1.0 Beta',
    tag: ReleaseTag.initial,
    title: 'Initial release',
    bullets: [
      'Core app: browse every set and card, track owned/wanted status and quantity, per-set and overall collection dashboards.',
      'Card detail pages with lore, game text, eBay price lookups, and outbound search links to Catawiki, Marktplaats, Phoenixcards, and Hill\'s Wholesale Gaming.',
      'Camera card scanner: single-shot photo scan and a continuous bulk-scan mode, using the printed year and border color to tell reprints apart.',
      'Four dark console themes (Borg, Federation, Klingon, Romulan) plus Light/System.',
      'Renamed to Kivas Fajo with a custom app icon; signed Play Store bundle prepared; iOS project scaffolded for a future Mac build.',
    ],
  ),
];
