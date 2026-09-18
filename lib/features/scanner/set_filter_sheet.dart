import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/card_set.dart';
import '../../state/providers.dart';

/// What the user picked in [SetFilterSheet]: a specific set id/name, or
/// [id] == null for "All Sets" (unrestricted matching).
class SetFilterChoice {
  final String? id;
  final String name;
  const SetFilterChoice({required this.id, required this.name});
}

/// Lets bulk scan narrow card matching to one set -- e.g. "I'm scanning a
/// Deep Space Nine box, don't match against the other 90-odd sets" -- with
/// "All Sets" always available for a mixed box of random cards.
class SetFilterSheet extends ConsumerStatefulWidget {
  final String? currentSetId;
  const SetFilterSheet({super.key, required this.currentSetId});

  @override
  ConsumerState<SetFilterSheet> createState() => _SetFilterSheetState();
}

class _SetFilterSheetState extends ConsumerState<SetFilterSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final setsAsync = ref.watch(allSetsProvider);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('Scan scope', style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search sets',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: setsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('Error: $e')),
                data: (sets) {
                  final physical = sets.where((s) => s.category == 'physical' && s.name.toLowerCase().contains(_query)).toList();
                  final virtual = sets.where((s) => s.category == 'virtual' && s.name.toLowerCase().contains(_query)).toList();
                  return ListView(
                    controller: scrollController,
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.all_inclusive,
                          color: widget.currentSetId == null ? Theme.of(context).colorScheme.primary : null,
                        ),
                        title: const Text('All Sets'),
                        subtitle: const Text('Match against every card in the database'),
                        trailing: widget.currentSetId == null ? const Icon(Icons.check) : null,
                        onTap: () => Navigator.of(context).pop(const SetFilterChoice(id: null, name: 'All Sets')),
                      ),
                      const Divider(height: 1),
                      if (physical.isNotEmpty) _SectionLabel('Physical Expansions'),
                      ...physical.map((s) => _SetTile(set: s, selected: s.id == widget.currentSetId)),
                      if (virtual.isNotEmpty) _SectionLabel('Virtual Expansions'),
                      ...virtual.map((s) => _SetTile(set: s, selected: s.id == widget.currentSetId)),
                      if (physical.isEmpty && virtual.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('No sets match.')),
                        ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _SetTile extends StatelessWidget {
  final CardSet set;
  final bool selected;
  const _SetTile({required this.set, required this.selected});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: set.iconUrl != null
          ? CachedNetworkImage(imageUrl: set.iconUrl!, width: 28, height: 28, errorWidget: (_, _, _) => const Icon(Icons.style))
          : const Icon(Icons.style),
      title: Text(set.name),
      subtitle: Text(set.date),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: () => Navigator.of(context).pop(SetFilterChoice(id: set.id, name: set.name)),
    );
  }
}
