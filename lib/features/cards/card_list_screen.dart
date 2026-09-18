import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/card_set.dart';
import '../../data/models/trek_card.dart';
import '../../state/providers.dart';
import '../card_detail/card_detail_screen.dart';

enum _Filter { all, owned, missing, wanted }

/// Matches the "Card Types" order listed on the wiki's main 1st Edition page
/// (cardguide.fandom.com/wiki/Star_Trek_CCG_1st_Edition). Types not in this
/// list (data quirks, etc.) are grouped alphabetically after these.
const _cardTypeOrder = [
  'Artifact',
  'Combo Dilemma',
  'Damage Marker',
  'Dilemma',
  'Doorway',
  'Equipment',
  'Event',
  'Facility',
  'Outpost',
  'Incident',
  'Interrupt',
  'Mission',
  'Objective',
  'Personnel',
  'Q Dilemma',
  'Q Dilemma/Event', // a real, separate wiki category for the rare dual-typed Q card (e.g. "Hide and Seek")
  'Q Event',
  'Q Interrupt',
  'Ship',
  'Site',
  'Tactic',
  'Time Location',
  'Tribble',
  'Trouble',
];

int _typeSortIndex(String? type) {
  if (type == null || type.isEmpty) return _cardTypeOrder.length + 1;
  final i = _cardTypeOrder.indexOf(type);
  return i == -1 ? _cardTypeOrder.length : i;
}

/// Personnel and Ships carry a meaningful affiliation (Borg, Federation,
/// Non-Aligned, ...); most other types don't (their affiliation is just
/// "-"), so only these two get grouped/sub-headered by it.
bool _groupsByAffiliation(String? type) => type == 'Personnel' || type == 'Ship';

class CardListScreen extends ConsumerStatefulWidget {
  final CardSet set;
  const CardListScreen({super.key, required this.set});

  @override
  ConsumerState<CardListScreen> createState() => _CardListScreenState();
}

class _CardListScreenState extends ConsumerState<CardListScreen> {
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(cardsInSetProvider(widget.set.id));
    final entriesAsync = ref.watch(collectionEntriesForSetProvider(widget.set.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.set.name),
        actions: [
          PopupMenuButton<bool>(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark whole set',
            onSelected: (markOwned) => _confirmAndSetWholeSet(context, cardsAsync.value ?? [], markOwned),
            itemBuilder: (context) => const [
              PopupMenuItem(value: true, child: Text('Mark set as owned')),
              PopupMenuItem(value: false, child: Text('Clear owned in this set')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search this set',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('All', _Filter.all),
                  _filterChip('Owned', _Filter.owned),
                  _filterChip('Missing', _Filter.missing),
                  _filterChip('Wanted', _Filter.wanted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: cardsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
              data: (cards) {
                final entries = entriesAsync.value ?? const {};
                var filtered = cards.where((c) {
                  if (_query.trim().isNotEmpty &&
                      !c.name.toLowerCase().contains(_query.trim().toLowerCase())) {
                    return false;
                  }
                  final entry = entries[c.id];
                  switch (_filter) {
                    case _Filter.all:
                      return true;
                    case _Filter.owned:
                      return entry?.owned ?? false;
                    case _Filter.missing:
                      return !(entry?.owned ?? false);
                    case _Filter.wanted:
                      return entry?.wanted ?? false;
                  }
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('No cards match.'));
                }

                filtered.sort((a, b) {
                  final byType = _typeSortIndex(a.type).compareTo(_typeSortIndex(b.type));
                  if (byType != 0) return byType;
                  final byTypeName = (a.type ?? '').toLowerCase().compareTo((b.type ?? '').toLowerCase());
                  if (byTypeName != 0) return byTypeName;
                  // Personnel and Ships read better clustered by affiliation
                  // (all the Borg together, then Federation, etc.) rather
                  // than one alphabetical name list mixing every side.
                  if (_groupsByAffiliation(a.type)) {
                    final byAffiliation = (a.affiliation ?? '').toLowerCase().compareTo((b.affiliation ?? '').toLowerCase());
                    if (byAffiliation != 0) return byAffiliation;
                  }
                  // Plain String.compareTo is case-sensitive (code-point
                  // order), which sorts any all-caps name like "DNA Clues"
                  // before "Dal'Rok" -- capital N sorts below lowercase a --
                  // even though "Dal" alphabetically precedes "DNA". Compare
                  // case-insensitively so names read in normal dictionary order.
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                });

                // So opening a card can swipe to the next/previous one in
                // this same filtered/sorted order, not just push a lone
                // detail screen with no sense of what's around it.
                final orderedIds = filtered.map((c) => c.id).toList();

                final rows = <Widget>[];
                String? currentType;
                String? currentAffiliation;
                for (final card in filtered) {
                  final typeLabel = (card.type == null || card.type!.isEmpty) ? 'Other' : card.type!;
                  if (typeLabel != currentType) {
                    currentType = typeLabel;
                    currentAffiliation = null;
                    rows.add(_TypeHeader(typeLabel));
                  }
                  if (_groupsByAffiliation(card.type)) {
                    final affLabel = (card.affiliation == null || card.affiliation!.isEmpty) ? 'Unspecified' : card.affiliation!;
                    if (affLabel != currentAffiliation) {
                      currentAffiliation = affLabel;
                      rows.add(_AffiliationHeader(affLabel));
                    }
                  }
                  final entry = entries[card.id];
                  rows.add(_CardRow(
                    card: card,
                    owned: entry?.owned ?? false,
                    wanted: entry?.wanted ?? false,
                    quantity: entry?.quantity ?? 0,
                    orderedIds: orderedIds,
                  ));
                }

                return ListView(children: rows);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _Filter value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Future<void> _confirmAndSetWholeSet(BuildContext context, List<TrekCard> cards, bool markOwned) async {
    if (cards.isEmpty) return;
    final action = markOwned ? 'Mark all ${cards.length} cards in this set as owned?' : 'Clear owned status for all ${cards.length} cards in this set?';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(markOwned ? 'Mark set as owned' : 'Clear owned in set'),
        content: Text(action),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(collectionRepositoryProvider).setOwnedForCards(cards.map((c) => c.id).toList(), markOwned);
    ref.read(collectionRevisionProvider.notifier).state++;
  }
}

class _TypeHeader extends StatelessWidget {
  final String label;
  const _TypeHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// A lighter sub-header nested under a _TypeHeader, grouping Personnel/Ships
/// by affiliation -- less prominent than the type header so the two stay
/// visually distinct as a group-within-a-group.
class _AffiliationHeader extends StatelessWidget {
  final String label;
  const _AffiliationHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  final TrekCard card;
  final bool owned;
  final bool wanted;
  final int quantity;
  final List<String> orderedIds;
  const _CardRow({
    required this.card,
    required this.owned,
    required this.wanted,
    required this.quantity,
    required this.orderedIds,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 56,
        child: card.imageUrl != null
            ? CachedNetworkImage(
                imageUrl: card.imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const Icon(Icons.image_not_supported),
              )
            : const Icon(Icons.image_not_supported),
      ),
      title: Text(card.name),
      // "Normal" printing is the common case and not worth spelling out --
      // but a distinguishing one (e.g. Starter Deck II's 1998 Original vs.
      // 2000 Reprint of the same 8 cards) is exactly what tells two
      // otherwise-identical-looking rows apart.
      subtitle: Text(
        [card.rarity, card.affiliation, if (card.printing != 'Normal') card.printing]
            .where((e) => e != null && e.isNotEmpty)
            .join(' • '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (wanted) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.star, color: Colors.amber, size: 20)),
          if (owned) ...[
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
            // A quantity of 0 (owned but not yet counted) isn't worth
            // spelling out as "×0" -- the checkmark alone already says owned.
            if (quantity > 0) ...[
              const SizedBox(width: 4),
              Text(
                '×$quantity',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ],
          ],
        ],
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CardDetailScreen(cardId: card.id, cardIds: orderedIds)),
        );
      },
    );
  }
}
