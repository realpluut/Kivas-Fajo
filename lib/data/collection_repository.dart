import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'models/collection_entry.dart';

class SetProgress {
  final int totalCards;
  final int ownedCards;
  const SetProgress({required this.totalCards, required this.ownedCards});

  double get fraction => totalCards == 0 ? 0 : ownedCards / totalCards;
}

/// How many rows an import actually applied vs. skipped (e.g. a card id from
/// an older/newer catalog that no longer exists in this build's data).
class ImportResult {
  final int imported;
  final int skipped;
  const ImportResult({required this.imported, required this.skipped});
}

class CollectionRepository {
  CollectionRepository(this._db);
  final AppDatabase _db;

  Future<CollectionEntry> entryFor(String cardId) async {
    final db = await _db.database;
    final rows = await db.query('collection_entries', where: 'card_id = ?', whereArgs: [cardId], limit: 1);
    if (rows.isEmpty) return CollectionEntry(cardId: cardId);
    return CollectionEntry.fromRow(rows.first);
  }

  Future<void> save(CollectionEntry entry) async {
    final db = await _db.database;
    // card_id is the primary key, and every card already has a row after its
    // first edit -- a plain insert() would throw a unique-constraint error on
    // any later edit, so this must replace rather than insert-only.
    await db.insert('collection_entries', entry.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Marks a single card owned, bumping its quantity by one -- used by the
  /// scanner: scanning a card you don't have yet sets owned + quantity 1,
  /// scanning one you already have adds another copy.
  Future<CollectionEntry> incrementOwned(String cardId) async {
    final current = await entryFor(cardId);
    final updated = current.copyWith(owned: true, quantity: current.quantity + 1);
    await save(updated);
    return updated;
  }

  /// Marks every card in a set owned (or clears owned) in one go, e.g. "mark
  /// this whole edition as owned". Owned cards with no quantity yet default
  /// to 1; clearing owned also zeroes the quantity, rather than leaving a
  /// stale count behind for a card you no longer have.
  Future<void> setOwnedForCards(List<String> cardIds, bool owned) async {
    if (cardIds.isEmpty) return;
    final db = await _db.database;
    final existing = await entriesForCardIds(cardIds);
    final batch = db.batch();
    for (final id in cardIds) {
      final current = existing[id] ?? CollectionEntry(cardId: id);
      final updated = current.copyWith(
        owned: owned,
        quantity: owned ? (current.quantity == 0 ? 1 : current.quantity) : 0,
      );
      batch.insert('collection_entries', updated.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Card ids the user owns or wants, for quick lookups when rendering lists.
  Future<Map<String, CollectionEntry>> entriesForCardIds(List<String> cardIds) async {
    if (cardIds.isEmpty) return {};
    final db = await _db.database;
    final placeholders = List.filled(cardIds.length, '?').join(',');
    final rows = await db.query(
      'collection_entries',
      where: 'card_id IN ($placeholders)',
      whereArgs: cardIds,
    );
    return {for (final r in rows) r['card_id'] as String: CollectionEntry.fromRow(r)};
  }

  Future<SetProgress> progressForSet(String setId) async {
    final db = await _db.database;
    final totalResult = await db.rawQuery('SELECT COUNT(*) as c FROM cards WHERE set_id = ?', [setId]);
    final total = (totalResult.first['c'] as int?) ?? 0;
    final ownedResult = await db.rawQuery('''
      SELECT COUNT(*) as c FROM collection_entries ce
      JOIN cards c ON c.id = ce.card_id
      WHERE c.set_id = ? AND ce.owned = 1
    ''', [setId]);
    final owned = (ownedResult.first['c'] as int?) ?? 0;
    return SetProgress(totalCards: total, ownedCards: owned);
  }

  Future<Map<String, SetProgress>> progressForAllSets() async {
    final db = await _db.database;
    final totals = await db.rawQuery('SELECT set_id, COUNT(*) as c FROM cards GROUP BY set_id');
    final owned = await db.rawQuery('''
      SELECT c.set_id as set_id, COUNT(*) as c FROM collection_entries ce
      JOIN cards c ON c.id = ce.card_id
      WHERE ce.owned = 1
      GROUP BY c.set_id
    ''');
    final ownedMap = {for (final r in owned) r['set_id'] as String: r['c'] as int};
    return {
      for (final r in totals)
        (r['set_id'] as String): SetProgress(
          totalCards: r['c'] as int,
          ownedCards: ownedMap[r['set_id'] as String] ?? 0,
        ),
    };
  }

  Future<int> totalOwnedCount() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM collection_entries WHERE owned = 1');
    return (result.first['c'] as int?) ?? 0;
  }

  Future<int> totalWantedCount() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM collection_entries WHERE wanted = 1');
    return (result.first['c'] as int?) ?? 0;
  }

  /// Every tracked entry, for a backup export. Untracked cards (never
  /// touched) simply have no row and are omitted -- nothing to back up.
  Future<List<CollectionEntry>> allEntries() async {
    final db = await _db.database;
    final rows = await db.query('collection_entries');
    return rows.map(CollectionEntry.fromRow).toList();
  }

  /// Restores entries from a backup, overwriting any existing row for the
  /// same card. Entries whose card id doesn't exist in this build's catalog
  /// (e.g. a backup made before a set was split, or from a mismatched build)
  /// are counted as skipped rather than silently dropped.
  Future<ImportResult> importEntries(List<CollectionEntry> entries) async {
    if (entries.isEmpty) return const ImportResult(imported: 0, skipped: 0);
    final db = await _db.database;
    final cardRows = await db.query('cards', columns: ['id']);
    final validCardIds = cardRows.map((r) => r['id'] as String).toSet();

    var imported = 0;
    var skipped = 0;
    final batch = db.batch();
    for (final entry in entries) {
      if (!validCardIds.contains(entry.cardId)) {
        skipped++;
        continue;
      }
      batch.insert('collection_entries', entry.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      imported++;
    }
    await batch.commit(noResult: true);
    return ImportResult(imported: imported, skipped: skipped);
  }
}
