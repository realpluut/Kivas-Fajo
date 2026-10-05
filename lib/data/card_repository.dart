import 'db.dart';
import 'models/card_set.dart';
import 'models/trek_card.dart';

class CardRepository {
  CardRepository(this._db);
  final AppDatabase _db;

  Future<List<CardSet>> allSets() async {
    final db = await _db.database;
    final rows = await db.query('sets', orderBy: 'category ASC, order_index ASC');
    return rows.map(CardSet.fromRow).toList();
  }

  Future<CardSet?> setById(String id) async {
    final db = await _db.database;
    final rows = await db.query('sets', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return CardSet.fromRow(rows.first);
  }

  Future<List<TrekCard>> cardsInSet(String setId, {String? searchQuery}) async {
    final db = await _db.database;
    final where = StringBuffer('set_id = ?');
    final args = <Object?>[setId];
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      where.write(' AND name LIKE ?');
      args.add('%${searchQuery.trim()}%');
    }
    final rows = await db.query(
      'cards',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'name ASC',
    );
    return rows.map(TrekCard.fromRow).toList();
  }

  Future<TrekCard?> cardById(String id) async {
    final db = await _db.database;
    final rows = await db.query('cards', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return TrekCard.fromRow(rows.first);
  }

  Future<int> cardCountInSet(String setId) async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM cards WHERE set_id = ?', [setId]);
    return (result.first['c'] as int?) ?? 0;
  }

  Future<List<TrekCard>> searchCards(String query, {int limit = 100}) async {
    if (query.trim().isEmpty) return [];
    final db = await _db.database;
    final rows = await db.query(
      'cards',
      where: 'name LIKE ?',
      whereArgs: ['%${query.trim()}%'],
      orderBy: 'name ASC',
      limit: limit,
    );
    return rows.map(TrekCard.fromRow).toList();
  }

  /// Every distinct card name in the database -- used as the candidate list
  /// for scanner text matching, since scoring each of the ~8,660 individual
  /// printings (many sharing a name across reprints) would be redundant.
  Future<List<String>> distinctCardNames() async {
    final db = await _db.database;
    final rows = await db.rawQuery('SELECT DISTINCT base_name FROM cards');
    return rows.map((r) => r['base_name'] as String).toList();
  }

  /// All printings of a card sharing the same base name (e.g. every set that
  /// printed "Betazoid Gift Box") -- the scanner's disambiguation candidates.
  Future<List<TrekCard>> cardsByBaseName(String baseName) async {
    final db = await _db.database;
    final rows = await db.query('cards', where: 'base_name = ?', whereArgs: [baseName], orderBy: 'set_id ASC');
    return rows.map(TrekCard.fromRow).toList();
  }

  /// Every distinct card type in the database (e.g. "Personnel", "Equipment",
  /// "Incident") -- lets the scanner recognize when a photographed card's
  /// topmost text is a generic type-category header rather than its own
  /// unique title. Several card types (Equipment, Incident, Interrupt,
  /// Event, Dilemma, ...) print the type across the very top of the card,
  /// with the actual unique name in a separate line below the artwork --
  /// unlike Personnel/Ship cards, which print the unique name directly at
  /// the top.
  Future<List<String>> distinctCardTypes() async {
    final db = await _db.database;
    final rows = await db.rawQuery("SELECT DISTINCT type FROM cards WHERE type IS NOT NULL AND type != ''");
    return rows.map((r) => r['type'] as String).toList();
  }

  /// Every distinct property-logo string in the database (e.g. "Star Trek:
  /// The Next Generation", "Star Trek: Deep Space Nine") -- every card
  /// prints its franchise logo in the same header area as the type (see
  /// [distinctCardTypes]), split across its own line(s) ("STAR TREK" /
  /// "THE NEXT GENERATION"), so it needs excluding from title matching too.
  Future<List<String>> distinctPropertyLogos() async {
    final db = await _db.database;
    final rows =
        await db.rawQuery("SELECT DISTINCT property_logo FROM cards WHERE property_logo IS NOT NULL AND property_logo != ''");
    return rows.map((r) => r['property_logo'] as String).toList();
  }
}
