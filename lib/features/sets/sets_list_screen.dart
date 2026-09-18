import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/collection_repository.dart';
import '../../data/models/card_set.dart';
import '../../state/providers.dart';
import '../cards/card_list_screen.dart';

class SetsListScreen extends ConsumerWidget {
  const SetsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setsAsync = ref.watch(allSetsProvider);
    final progressAsync = ref.watch(setProgressProvider);

    return setsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Could not load sets: $e')),
      data: (sets) {
        final physical = sets.where((s) => s.category == 'physical').toList();
        final virtual = sets.where((s) => s.category == 'virtual').toList();
        final progress = progressAsync.value ?? const {};

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _SectionHeader('Physical Expansions'),
            ...physical.map((s) => _SetTile(set: s, progress: progress[s.id])),
            _SectionHeader('Virtual Expansions'),
            ...virtual.map((s) => _SetTile(set: s, progress: progress[s.id])),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _SetTile extends StatelessWidget {
  final CardSet set;
  final SetProgress? progress;
  const _SetTile({required this.set, required this.progress});

  @override
  Widget build(BuildContext context) {
    final fraction = progress?.fraction ?? 0;
    return ListTile(
      leading: set.iconUrl != null
          ? CachedNetworkImage(
              imageUrl: set.iconUrl!,
              width: 28,
              height: 28,
              errorWidget: (_, _, _) => const Icon(Icons.style),
            )
          : const Icon(Icons.style),
      title: Text(set.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(set.date, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: fraction, minHeight: 6),
          ),
        ],
      ),
      trailing: progress != null
          ? Text('${progress!.ownedCards}/${progress!.totalCards}')
          : null,
      isThreeLine: true,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CardListScreen(set: set)),
        );
      },
    );
  }
}
