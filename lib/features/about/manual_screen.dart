import 'package:flutter/material.dart';

/// The same field manual published online, ported to native widgets so it
/// reads correctly offline and picks up whichever console theme is active,
/// instead of embedding the web page (which would need a connection and
/// wouldn't match the app's own styling).
class ManualScreen extends StatelessWidget {
  const ManualScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Field Manual')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _Chapter(
            number: '00',
            title: 'What this app does',
            paragraphs: [
              'Kivas Fajo is a pocket reference and collection tracker for the 1st Edition Star Trek CCG. '
                  'The full card catalog -- every physical and virtual expansion -- is bundled with the app '
                  'and sourced from the cardguide.fandom.com wiki, so browsing works with no signal at all.',
              'On top of that, it tracks what you own or want, links out to marketplaces when you\'re hunting '
                  'for a card, and can read a physical card through your phone\'s camera and mark it owned for '
                  'you -- one at a time, or in a continuous bulk-scan mode for going through a whole binder page.',
            ],
          ),
          _Chapter(
            number: '01',
            title: 'Installing on another device',
            paragraphs: [
              'This app isn\'t distributed through the Play Store -- it\'s a direct APK file, signed with a '
                  'development key. Android needs a one-time nudge to trust it.',
            ],
            steps: [
              'Get the APK file onto the phone, however it\'s sent (chat app, cloud drive, USB).',
              'Open the file. Android will likely block the install the first time and offer a link to Settings.',
              'Follow it to "Install unknown apps" and allow it for whichever app opened the file -- a one-time, per-app permission.',
              'Go back and tap Install.',
            ],
            notes: [
              'On first launch, the Scan tab asks for Camera access. Everything else -- browsing, tracking, reading card text -- works without granting it.',
            ],
          ),
          _Chapter(
            number: '02',
            title: 'Finding your way around',
            paragraphs: [
              'Four tabs sit along the bottom of the screen: Sets, Collection, Scan, and About. A gear icon in '
                  'the top-right corner of every screen opens Settings.',
              'Sets is the full catalog, grouped into Physical and Virtual Expansions. Collection is your '
                  'dashboard -- totals and per-set completion. Scan opens the card scanner. About covers '
                  'attribution and disclaimers.',
            ],
          ),
          _Chapter(
            number: '03',
            title: 'Browsing sets & tracking your collection',
            paragraphs: [
              'Tap any set on the Sets tab to open its card list. Each set row already shows a progress bar '
                  'and an owned/total count, so you can see what needs attention before you even open it.',
            ],
            subsections: [
              _SubSection(
                heading: 'Inside a set',
                text: 'Cards are grouped under type headers -- Personnel, Ship, Mission, Dilemma, and so on -- '
                    'in the same order the wiki itself lists them, not alphabetically. Personnel and Ship cards '
                    'get a second level of grouping underneath: all the Borg together, then Federation, then '
                    'Non-Aligned, and so on. Use the search field to jump to a card by name, and the All / Owned '
                    '/ Missing / Wanted chips to narrow the list. Each row shows a star if it\'s on your want '
                    'list, and a green check with a quantity if you own it.',
              ),
              _SubSection(
                heading: 'Marking cards',
                text: 'Tap a card to open its detail page, then use the Owned and Wanted chips. Marking a card '
                    'Owned starts its quantity at 1; the stepper next to it adds or removes copies from there. '
                    'Unmarking Owned resets the quantity back to 0 rather than leaving a stale count behind. '
                    'Once on a card\'s detail page, swipe left or right to move to the next or previous card in '
                    'that same list.',
              ),
              _SubSection(
                heading: 'Marking a whole set at once',
                text: 'The checkmark icon in a set\'s toolbar offers "Mark set as owned" or "Clear owned in '
                    'this set" -- useful right after scanning in (or selling off) a whole binder page. Both ask '
                    'for confirmation first, since they apply to every card in the set.',
              ),
            ],
          ),
          _Chapter(
            number: '04',
            title: 'Card details & pricing',
            paragraphs: [
              'A card\'s detail page carries its lore text, its full game text, and a link back to its page on '
                  'cardguide.fandom.com.',
            ],
            subsections: [
              _SubSection(
                heading: 'Prices',
                text: 'Live listings pull from eBay\'s own search API when a pricing backend is configured for '
                    'the build. Tapping a listing opens it in your browser. Underneath, "Search other '
                    'marketplaces" gives one-tap searches for the card\'s name on eBay, Catawiki, Marktplaats, '
                    'Phoenixcards, and Hill\'s Wholesale Gaming -- outbound links only, never scraped or stored.',
              ),
            ],
          ),
          _Chapter(
            number: '05',
            title: 'Scanning a card',
            paragraphs: [
              'From the Scan tab, tap "Take Photo" -- this opens a live camera preview right in the app, no '
                  'handing off to the phone\'s own camera app or its confirm/retake screen. Frame both the '
                  'title and the tiny copyright line near the edge, then tap the shutter. It goes straight '
                  'into reading the card, no extra tap to confirm the photo. A torch toggle sits next to the '
                  'shutter for dim light; tap the ✕ to back out without capturing.',
            ],
            subsections: [
              _SubSection(
                heading: 'What happens next',
                text: 'If the photo matches exactly one card and printing, it\'s added automatically with a '
                    'confirmation showing the card\'s name and new quantity. If several printings are '
                    'plausible, a picker appears instead:\n\n'
                    '● Green check -- both the printed year and the card\'s border color match this candidate.\n'
                    '● Amber check -- only one of those two signals matched, still plausible.\n'
                    '● Red cross -- the border color in the photo actively rules this printing out.\n\n'
                    'Tap + on the right printing to add it, or tap the row first to look at the full card '
                    'before deciding.',
              ),
              _SubSection(
                heading: 'If it doesn\'t work',
                text: 'A "Scan details" panel appears on any no-match or error screen -- it shows exactly what '
                    'text was read, the corner brightness readings used for border detection, and the year it '
                    'detected. Usually the fix is getting closer, filling the frame more, or evening out the '
                    'light.',
              ),
            ],
          ),
          _Chapter(
            number: '06',
            title: 'Bulk scanning',
            paragraphs: [
              'Tap "Bulk Scan (live)" from the idle scan screen to keep the camera open continuously -- built '
                  'for running through a stack or a binder page without tapping anything between cards. The '
                  'screen stays awake for the whole session.',
            ],
            subsections: [
              _SubSection(
                heading: 'The controls, top bar',
                text: 'Torch (on by default), VHQ/MAX resolution, pinch-to-zoom (the current multiplier shows '
                    'next to the counter), and an exposure slider on phones that support it.',
              ),
              _SubSection(
                heading: 'Scan scope',
                text: 'Just under the top bar, a scope bar reads "All Sets" by default. Tap it to restrict '
                    'matching to one chosen set instead -- fewer possible cards to match against means fewer '
                    'false ambiguous prompts. "All Sets" is always the first option, for a mixed box of random '
                    'cards.',
              ),
              _SubSection(
                heading: 'While it runs',
                text: 'Every few seconds the camera captures whatever card is in frame, reads it, and adds it '
                    'automatically on a confident match -- a short high beep confirms a successful add; a '
                    'lower double-blip means it needs attention (an ambiguous match). When a match is '
                    'ambiguous, capturing pauses and the screen freezes on the exact photo it\'s asking about, '
                    'so the picker below always matches what\'s on screen. Pick a printing or tap Skip to '
                    'resume.',
              ),
            ],
          ),
          _Chapter(
            number: '07',
            title: 'Settings & themes',
            paragraphs: [
              'The gear icon opens Settings, with two independent choices: Theme (System default / Light / '
                  'Dark) and, whenever dark mode is active, a Dark theme style -- Borg (phosphor-green glow), '
                  'Federation (LCARS/Okudagram panels in orange, violet and salmon), Klingon (blood-red and '
                  'bronze, sharp angular accents), or Romulan (teal-emerald and gunmetal, a swept warbird '
                  'curve).',
            ],
          ),
          _Chapter(
            number: '08',
            title: 'Backup & restore',
            paragraphs: [
              'Settings also has a Backup section, for moving your collection between installs -- e.g. before '
                  'uninstalling to change which key an app is signed with, or switching phones.',
            ],
            subsections: [
              _SubSection(
                heading: 'Export collection',
                text: 'Builds a backup file of everything you\'ve tracked (owned/wanted status and quantities) '
                    'and opens the share sheet, so it can be sent to Drive, email, or wherever\'s convenient.',
              ),
              _SubSection(
                heading: 'Import collection',
                text: 'Picks a previously exported backup file and restores it, after a confirmation. Only '
                    'cards the backup actually covers get overwritten -- everything else stays as it was. '
                    'Cards the backup mentions that no longer exist in this build\'s catalog (e.g. from a set '
                    'that was later split) are skipped and counted, not silently dropped.',
              ),
            ],
          ),
          _Chapter(
            number: '09',
            title: 'Data sources & limits',
            paragraphs: [
              'Card and set data is sourced from the Star Trek CCG wiki at cardguide.fandom.com, licensed '
                  'under Creative Commons Attribution-Share Alike (CC BY-SA); the full disclaimer also lives '
                  'on the About tab.',
              'Browsing the catalog and tracking your collection need no connection at all. Only live prices '
                  'and the outbound marketplace links need one -- and live eBay prices specifically only work '
                  'when a pricing backend is configured for a given build.',
            ],
          ),
        ],
      ),
    );
  }
}

class _SubSection {
  final String heading;
  final String text;
  const _SubSection({required this.heading, required this.text});
}

class _Chapter extends StatelessWidget {
  final String number;
  final String title;
  final List<String> paragraphs;
  final List<String>? steps;
  final List<String>? notes;
  final List<_SubSection>? subsections;
  const _Chapter({
    required this.number,
    required this.title,
    required this.paragraphs,
    this.steps,
    this.notes,
    this.subsections,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Row(
          children: [
            Text(number, style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in paragraphs) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(p)),
          if (steps != null) ...[
            for (var i = 0; i < steps!.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}. ', style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
                    Expanded(child: Text(steps![i])),
                  ],
                ),
              ),
            const SizedBox(height: 4),
          ],
          if (notes != null)
            for (final n in notes!)
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: primary, width: 3)),
                  color: primary.withValues(alpha: 0.08),
                ),
                child: Text(n, style: Theme.of(context).textTheme.bodySmall),
              ),
          if (subsections != null)
            for (final s in subsections!)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.heading, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(s.text),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
