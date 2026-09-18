import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'collection_repository.dart';
import 'models/collection_entry.dart';

/// A backup file is never guaranteed to be well-formed (hand-edited, from a
/// future/older app version, or just not a Kivas Fajo backup at all) --
/// thrown with a message safe to show directly to the user.
class BackupFormatException implements Exception {
  final String message;
  const BackupFormatException(this.message);
  @override
  String toString() => message;
}

/// Exports/imports the user's owned/wanted/quantity tracking as a small JSON
/// file -- the one thing that can't be recovered from the bundled card data,
/// and the one thing lost when reinstalling (e.g. after a signing-key change
/// forces an uninstall first; see collection_repository.dart's save()).
class BackupService {
  BackupService(this._repo);
  final CollectionRepository _repo;

  static const _formatVersion = 1;

  /// Writes the current collection to a temp file and returns it, ready to
  /// hand to a share sheet -- the caller decides where it actually ends up
  /// (Drive, email, Files, ...).
  Future<File> buildExportFile() async {
    final entries = await _repo.allEntries();
    final payload = {
      'app': 'Kivas Fajo',
      'format_version': _formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'entries': entries
          .map((e) => {
                'card_id': e.cardId,
                'owned': e.owned,
                'wanted': e.wanted,
                'quantity': e.quantity,
                if (e.condition != null) 'condition': e.condition,
                if (e.notes != null) 'notes': e.notes,
              })
          .toList(),
    };

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final file = File('${dir.path}/kivas-fajo-collection-$stamp.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    return file;
  }

  Future<ImportResult> importFromFile(File file) async {
    final String raw;
    try {
      raw = await file.readAsString();
    } catch (e) {
      throw BackupFormatException('Could not read that file: $e');
    }

    final Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) throw const FormatException('not an object');
      decoded = parsed;
    } catch (_) {
      throw const BackupFormatException('That file isn\'t a valid Kivas Fajo backup (not readable JSON).');
    }

    final rawEntries = decoded['entries'];
    if (rawEntries is! List) {
      throw const BackupFormatException('That file isn\'t a valid Kivas Fajo backup (missing "entries").');
    }

    final entries = <CollectionEntry>[];
    for (final raw in rawEntries) {
      if (raw is! Map<String, dynamic>) continue;
      final cardId = raw['card_id'];
      if (cardId is! String || cardId.isEmpty) continue;
      entries.add(CollectionEntry(
        cardId: cardId,
        owned: raw['owned'] == true,
        wanted: raw['wanted'] == true,
        quantity: (raw['quantity'] is num) ? (raw['quantity'] as num).toInt() : 0,
        condition: raw['condition'] as String?,
        notes: raw['notes'] as String?,
      ));
    }

    if (entries.isEmpty) {
      throw const BackupFormatException('That backup file has no entries to restore.');
    }

    return _repo.importEntries(entries);
  }
}
