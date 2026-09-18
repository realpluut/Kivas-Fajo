import 'package:flutter/material.dart';

import '../../data/release_notes.dart';

class ReleaseNotesScreen extends StatelessWidget {
  const ReleaseNotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('What\'s changed')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: kReleaseNotes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final note = kReleaseNotes[i];
          final isCurrent = i == 0;
          return _ReleaseCard(note: note, isCurrent: isCurrent);
        },
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  final ReleaseNote note;
  final bool isCurrent;
  const _ReleaseCard({required this.note, required this.isCurrent});

  Color _tagColor(BuildContext context, ReleaseTag tag) {
    final scheme = Theme.of(context).colorScheme;
    return switch (tag) {
      ReleaseTag.initial => scheme.primary,
      ReleaseTag.feature => scheme.primary,
      ReleaseTag.bugFix => scheme.error,
      ReleaseTag.dataFix => scheme.secondary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tagColor = _tagColor(context, note.tag);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  note.version,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tagColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    note.tag.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tagColor, fontWeight: FontWeight.bold),
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  Text('Current', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(note.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...note.bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(b, style: Theme.of(context).textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
