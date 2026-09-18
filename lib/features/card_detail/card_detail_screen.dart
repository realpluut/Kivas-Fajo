import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/ebay_service.dart';
import '../../data/marketplace_links.dart';
import '../../data/models/collection_entry.dart';
import '../../data/models/trek_card.dart';
import '../../state/providers.dart';

class CardDetailScreen extends StatefulWidget {
  final String cardId;

  /// The full, ordered list of card ids from wherever this screen was opened
  /// (e.g. the currently filtered/sorted set list) -- when there's more than
  /// one, left/right swipes move through this same order instead of just
  /// showing a single card. Omit (or pass a single-item list) to disable
  /// swiping, e.g. when opening a card from the scanner with no such order.
  final List<String>? cardIds;

  const CardDetailScreen({super.key, required this.cardId, this.cardIds});

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  late final List<String> _ids;
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _ids = widget.cardIds ?? [widget.cardId];
    final i = _ids.indexOf(widget.cardId);
    _index = i == -1 ? 0 : i;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSwipe = _ids.length > 1;
    return Scaffold(
      appBar: AppBar(title: Text(canSwipe ? 'Card ${_index + 1} of ${_ids.length}' : 'Card')),
      body: canSwipe
          ? PageView.builder(
              controller: _controller,
              itemCount: _ids.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => _CardDetailPage(cardId: _ids[i]),
            )
          : _CardDetailPage(cardId: _ids[_index]),
    );
  }
}

class _CardDetailPage extends ConsumerWidget {
  final String cardId;
  const _CardDetailPage({required this.cardId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(cardByIdProvider(cardId));
    return cardAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (card) {
        if (card == null) return const Center(child: Text('Card not found.'));
        return _CardDetailBody(card: card);
      },
    );
  }
}

class _CardDetailBody extends ConsumerWidget {
  final TrekCard card;
  const _CardDetailBody({required this.card});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryAsync = ref.watch(collectionEntryProvider(card.id));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (card.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: card.imageUrl!,
                  width: 120,
                  errorWidget: (_, _, _) => const SizedBox(),
                ),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text([card.type, card.rarity, card.affiliation, if (card.printing != 'Normal') card.printing]
                      .where((e) => e != null && e.isNotEmpty)
                      .join(' • ')),
                  if (card.propertyLogo != null) Text(card.propertyLogo!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        entryAsync.when(
          loading: () => const SizedBox(),
          error: (e, st) => const SizedBox(),
          data: (entry) => _CollectionControls(cardId: card.id, entry: entry),
        ),
        const Divider(height: 32),
        if (card.lore != null && card.lore!.isNotEmpty) ...[
          Text('Lore', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(card.lore!, style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
        ],
        if (card.gameText != null && card.gameText!.isNotEmpty) ...[
          Text('Game Text', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(card.gameText!),
          const SizedBox(height: 16),
        ],
        const Divider(height: 32),
        Text('Prices', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _PricesSection(card: card),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => launchUrl(Uri.parse(card.wikiUrl), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new),
          label: const Text('View on cardguide.fandom.com'),
        ),
      ],
    );
  }
}

class _CollectionControls extends ConsumerWidget {
  final String cardId;
  final CollectionEntry entry;
  const _CollectionControls({required this.cardId, required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(collectionRepositoryProvider);

    Future<void> update({bool? owned, bool? wanted, int? quantity}) async {
      await repo.save(entry.copyWith(owned: owned, wanted: wanted, quantity: quantity));
      ref.read(collectionRevisionProvider.notifier).state++;
    }

    return Row(
      children: [
        FilterChip(
          label: const Text('Owned'),
          avatar: const Icon(Icons.check_circle_outline, size: 18),
          selected: entry.owned,
          // Marking owned starts the count at 1 (unless it already has one);
          // unmarking it means you have zero, not whatever count was left
          // over from before.
          onSelected: (v) => update(owned: v, quantity: v ? (entry.quantity == 0 ? 1 : null) : 0),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: const Text('Wanted'),
          avatar: const Icon(Icons.star_border, size: 18),
          selected: entry.wanted,
          onSelected: (v) => update(wanted: v),
        ),
        const Spacer(),
        if (entry.owned) ...[
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => update(quantity: (entry.quantity - 1).clamp(0, 999)),
          ),
          // A quantity of 0 (owned but not yet counted, e.g. right after
          // decrementing) isn't worth spelling out as text.
          if (entry.quantity > 0) Text('${entry.quantity}'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => update(quantity: entry.quantity + 1),
          ),
        ],
      ],
    );
  }
}

class _PricesSection extends ConsumerWidget {
  final TrekCard card;
  const _PricesSection({required this.card});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ebayService = ref.read(ebayServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<List<EbayListing>>(
          future: ebayService.search(card.baseName),
          builder: (context, snapshot) {
            if (ebayService.backendBaseUrl.isEmpty) {
              return const Text(
                'Live eBay prices are not configured for this build.',
                style: TextStyle(color: Colors.grey),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              );
            }
            if (snapshot.hasError) {
              return const Text('Could not load eBay prices right now.', style: TextStyle(color: Colors.grey));
            }
            final listings = snapshot.data ?? [];
            if (listings.isEmpty) {
              return const Text('No current eBay listings found.', style: TextStyle(color: Colors.grey));
            }
            return Column(
              children: listings
                  .map((l) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: l.imageUrl != null
                            ? CachedNetworkImage(imageUrl: l.imageUrl!, width: 40, errorWidget: (_, _, _) => const SizedBox())
                            : null,
                        title: Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(l.condition ?? ''),
                        trailing: Text(l.price != null ? '${l.price} ${l.currency ?? ''}' : ''),
                        onTap: () => launchUrl(Uri.parse(l.url), mode: LaunchMode.externalApplication),
                      ))
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 12),
        Text('Search other marketplaces', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: marketplaceLinksFor(card.baseName)
              .map((m) => OutlinedButton(
                    onPressed: () => launchUrl(Uri.parse(m.url), mode: LaunchMode.externalApplication),
                    child: Text(m.label),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
