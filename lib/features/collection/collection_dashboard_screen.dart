import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

class CollectionDashboardScreen extends ConsumerWidget {
  const CollectionDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(collectionSummaryProvider);
    final progressAsync = ref.watch(setProgressProvider);
    final setsAsync = ref.watch(allSetsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        summaryAsync.when(
          loading: () => const SizedBox(),
          error: (e, st) => const SizedBox(),
          data: (summary) => Row(
            children: [
              Expanded(child: _StatCard(label: 'Owned', value: '${summary.owned}')),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(label: 'Wanted', value: '${summary.wanted}')),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Set completion', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        setsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Text('Error: $e'),
          data: (sets) {
            final progress = progressAsync.value ?? const {};
            final withOwned = sets.where((s) => (progress[s.id]?.ownedCards ?? 0) > 0).toList()
              ..sort((a, b) => (progress[b.id]?.fraction ?? 0).compareTo(progress[a.id]?.fraction ?? 0));
            if (withOwned.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('You haven\'t marked any cards as owned yet. Browse a set to get started.'),
              );
            }
            return Column(
              children: withOwned.map((s) {
                final p = progress[s.id]!;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                      Expanded(
                        flex: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: p.fraction, minHeight: 8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${p.ownedCards}/${p.totalCards}'),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
