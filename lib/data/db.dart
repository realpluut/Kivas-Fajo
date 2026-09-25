import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models/card_set.dart';
import 'models/trek_card.dart';

/// Bump this whenever assets/sets.json or assets/cards.json are regenerated
/// with a meaningfully different shape/content, so existing installs reseed.
const int kCurrentDataVersion = 13;

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    await _seedIfNeeded(_db!);
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = p.join(await getDatabasesPath(), 'star_trek_ccg.db');
    return openDatabase(
      dbPath,
      version: 2,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE sets ADD COLUMN border_color TEXT');
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE sets (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            page_title TEXT NOT NULL,
            category TEXT NOT NULL,
            order_index INTEGER NOT NULL,
            date TEXT,
            card_count_hint TEXT,
            block TEXT,
            icon_url TEXT,
            wiki_url TEXT NOT NULL,
            border_color TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE cards (
            id TEXT PRIMARY KEY,
            page_title TEXT NOT NULL,
            name TEXT NOT NULL,
            base_name TEXT NOT NULL,
            set_id TEXT NOT NULL,
            rarity TEXT,
            type TEXT,
            affiliation TEXT,
            printing TEXT,
            property_logo TEXT,
            lore TEXT,
            game_text TEXT,
            characteristics TEXT,
            legal_card_pools TEXT,
            legal_rules_sets TEXT,
            characters TEXT,
            actors TEXT,
            external_links TEXT,
            wiki_url TEXT NOT NULL,
            image_url TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_cards_set_id ON cards(set_id)');
        await db.execute('CREATE INDEX idx_cards_name ON cards(name)');
        await db.execute('''
          CREATE TABLE collection_entries (
            card_id TEXT PRIMARY KEY,
            owned INTEGER NOT NULL DEFAULT 0,
            wanted INTEGER NOT NULL DEFAULT 0,
            quantity INTEGER NOT NULL DEFAULT 0,
            condition TEXT,
            notes TEXT,
            updated_at TEXT
          )
        ''');
      },
    );
  }

  Future<void> _seedIfNeeded(Database db) async {
    final row = await db.query('meta', where: 'key = ?', whereArgs: ['data_version']);
    final storedVersion = row.isEmpty ? -1 : int.tryParse(row.first['value'] as String? ?? '') ?? -1;
    if (storedVersion == kCurrentDataVersion) return;

    final setsJson = jsonDecode(await rootBundle.loadString('assets/sets.json')) as List;
    final cardsJson = jsonDecode(await rootBundle.loadString('assets/cards.json')) as List;

    await db.transaction((txn) async {
      await txn.delete('sets');
      await txn.delete('cards');

      final setsBatch = txn.batch();
      for (final raw in setsJson) {
        setsBatch.insert(
          'sets',
          CardSet.fromJson(raw as Map<String, dynamic>).toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await setsBatch.commit(noResult: true);

      // Large table: insert in chunks so a single batch doesn't get too big.
      const chunkSize = 500;
      for (var i = 0; i < cardsJson.length; i += chunkSize) {
        final chunk = cardsJson.skip(i).take(chunkSize);
        final cardsBatch = txn.batch();
        for (final raw in chunk) {
          cardsBatch.insert(
            'cards',
            TrekCard.fromJson(raw as Map<String, dynamic>).toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await cardsBatch.commit(noResult: true);
      }

      await txn.insert(
        'meta',
        {'key': 'data_version', 'value': kCurrentDataVersion.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}
