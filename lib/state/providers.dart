import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/backup_service.dart';
import '../data/card_repository.dart';
import '../data/collection_repository.dart';
import '../data/db.dart';
import '../data/ebay_service.dart';
import '../data/models/card_set.dart';
import '../data/models/collection_entry.dart';
import '../data/models/trek_card.dart';
import '../theme.dart';

const _backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: '');

final cardRepositoryProvider = Provider((ref) => CardRepository(AppDatabase.instance));
final collectionRepositoryProvider = Provider((ref) => CollectionRepository(AppDatabase.instance));
final ebayServiceProvider = Provider((ref) => EbayService(backendBaseUrl: _backendUrl));
final backupServiceProvider = Provider((ref) => BackupService(ref.watch(collectionRepositoryProvider)));

/// Must be overridden in main() with a resolved SharedPreferences instance
/// before the app is built.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider was not overridden in main()');
});

const _themeModeKey = 'theme_mode';

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs) : super(_load(_prefs));
  final SharedPreferences _prefs;

  static ThemeMode _load(SharedPreferences prefs) {
    final saved = prefs.getString(_themeModeKey);
    return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_themeModeKey, mode.name);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(ref.watch(sharedPreferencesProvider));
});

const _themeStyleKey = 'theme_style';

class AppThemeStyleController extends StateNotifier<AppThemeStyle> {
  AppThemeStyleController(this._prefs) : super(_load(_prefs));
  final SharedPreferences _prefs;

  static AppThemeStyle _load(SharedPreferences prefs) {
    final saved = prefs.getString(_themeStyleKey);
    return AppThemeStyle.values.firstWhere((s) => s.name == saved, orElse: () => AppThemeStyle.borg);
  }

  Future<void> setStyle(AppThemeStyle style) async {
    state = style;
    await _prefs.setString(_themeStyleKey, style.name);
  }
}

final appThemeStyleProvider = StateNotifierProvider<AppThemeStyleController, AppThemeStyle>((ref) {
  return AppThemeStyleController(ref.watch(sharedPreferencesProvider));
});

final allSetsProvider = FutureProvider<List<CardSet>>((ref) {
  return ref.watch(cardRepositoryProvider).allSets();
});

/// Bumped after any collection edit to force dependent providers to refresh.
final collectionRevisionProvider = StateProvider<int>((ref) => 0);

final setProgressProvider = FutureProvider((ref) {
  ref.watch(collectionRevisionProvider);
  return ref.watch(collectionRepositoryProvider).progressForAllSets();
});

final collectionSummaryProvider = FutureProvider((ref) async {
  ref.watch(collectionRevisionProvider);
  final repo = ref.watch(collectionRepositoryProvider);
  final owned = await repo.totalOwnedCount();
  final wanted = await repo.totalWantedCount();
  return (owned: owned, wanted: wanted);
});

final collectionEntryProvider = FutureProvider.family<CollectionEntry, String>((ref, cardId) {
  ref.watch(collectionRevisionProvider);
  return ref.watch(collectionRepositoryProvider).entryFor(cardId);
});

final cardsInSetProvider = FutureProvider.family<List<TrekCard>, String>((ref, setId) {
  return ref.watch(cardRepositoryProvider).cardsInSet(setId);
});

/// card_id -> CollectionEntry for every card in a set, so the list screen can
/// show owned/wanted badges without one query per row.
final collectionEntriesForSetProvider = FutureProvider.family<Map<String, CollectionEntry>, String>((ref, setId) async {
  ref.watch(collectionRevisionProvider);
  final cards = await ref.watch(cardsInSetProvider(setId).future);
  return ref.watch(collectionRepositoryProvider).entriesForCardIds(cards.map((c) => c.id).toList());
});

final cardByIdProvider = FutureProvider.family<TrekCard?, String>((ref, cardId) {
  return ref.watch(cardRepositoryProvider).cardById(cardId);
});

final cardSearchProvider = FutureProvider.family<List<TrekCard>, String>((ref, query) {
  return ref.watch(cardRepositoryProvider).searchCards(query);
});

/// Cached for the lifetime of the app -- used by the card scanner to score
/// OCR'd text against every known card name.
final distinctCardNamesProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(cardRepositoryProvider).distinctCardNames();
});

/// Same idea as [distinctCardNamesProvider], but narrowed to one set -- lets
/// bulk scan's set-filter restrict matching to just that edition's names
/// instead of scoring OCR text against every card in the database.
final namesInSetProvider = FutureProvider.family<List<String>, String>((ref, setId) async {
  final cards = await ref.watch(cardRepositoryProvider).cardsInSet(setId);
  return cards.map((c) => c.name).toSet().toList();
});
