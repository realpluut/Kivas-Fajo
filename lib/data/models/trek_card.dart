import 'dart:convert';

/// A single card printing (one row per set/expansion appearance).
/// Named TrekCard to avoid clashing with Flutter's own Card widget.
class TrekCard {
  final String id;
  final String pageTitle;
  final String name;
  final String baseName;
  final String setId;
  final String? rarity;
  final String? type;
  final String? affiliation;
  final String? printing;
  final String? propertyLogo;
  final String? lore;
  final String? gameText;
  final List<String> characteristics;
  final List<String> legalCardPools;
  final List<String> legalRulesSets;
  final List<String> characters;
  final List<String> actors;
  final List<String> externalLinks;
  final String wikiUrl;
  final String? imageUrl;

  const TrekCard({
    required this.id,
    required this.pageTitle,
    required this.name,
    required this.baseName,
    required this.setId,
    required this.rarity,
    required this.type,
    required this.affiliation,
    required this.printing,
    required this.propertyLogo,
    required this.lore,
    required this.gameText,
    required this.characteristics,
    required this.legalCardPools,
    required this.legalRulesSets,
    required this.characters,
    required this.actors,
    required this.externalLinks,
    required this.wikiUrl,
    required this.imageUrl,
  });

  factory TrekCard.fromJson(Map<String, dynamic> json) => TrekCard(
        id: json['id'] as String,
        pageTitle: json['page_title'] as String,
        name: json['name'] as String,
        baseName: json['base_name'] as String? ?? json['name'] as String,
        setId: json['set_id'] as String,
        rarity: json['rarity'] as String?,
        type: json['type'] as String?,
        affiliation: json['affiliation'] as String?,
        printing: json['printing'] as String?,
        propertyLogo: json['property_logo'] as String?,
        lore: json['lore'] as String?,
        gameText: json['game_text'] as String?,
        characteristics: (json['characteristics'] as List?)?.cast<String>() ?? const [],
        legalCardPools: (json['legal_card_pools'] as List?)?.cast<String>() ?? const [],
        legalRulesSets: (json['legal_rules_sets'] as List?)?.cast<String>() ?? const [],
        characters: (json['characters'] as List?)?.cast<String>() ?? const [],
        actors: (json['actors'] as List?)?.cast<String>() ?? const [],
        externalLinks: (json['external_links'] as List?)?.cast<String>() ?? const [],
        wikiUrl: json['wiki_url'] as String,
        imageUrl: json['image_url'] as String?,
      );

  factory TrekCard.fromRow(Map<String, Object?> row) => TrekCard(
        id: row['id'] as String,
        pageTitle: row['page_title'] as String,
        name: row['name'] as String,
        baseName: row['base_name'] as String,
        setId: row['set_id'] as String,
        rarity: row['rarity'] as String?,
        type: row['type'] as String?,
        affiliation: row['affiliation'] as String?,
        printing: row['printing'] as String?,
        propertyLogo: row['property_logo'] as String?,
        lore: row['lore'] as String?,
        gameText: row['game_text'] as String?,
        characteristics: _decodeList(row['characteristics']),
        legalCardPools: _decodeList(row['legal_card_pools']),
        legalRulesSets: _decodeList(row['legal_rules_sets']),
        characters: _decodeList(row['characters']),
        actors: _decodeList(row['actors']),
        externalLinks: _decodeList(row['external_links']),
        wikiUrl: row['wiki_url'] as String,
        imageUrl: row['image_url'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'page_title': pageTitle,
        'name': name,
        'base_name': baseName,
        'set_id': setId,
        'rarity': rarity,
        'type': type,
        'affiliation': affiliation,
        'printing': printing,
        'property_logo': propertyLogo,
        'lore': lore,
        'game_text': gameText,
        'characteristics': jsonEncode(characteristics),
        'legal_card_pools': jsonEncode(legalCardPools),
        'legal_rules_sets': jsonEncode(legalRulesSets),
        'characters': jsonEncode(characters),
        'actors': jsonEncode(actors),
        'external_links': jsonEncode(externalLinks),
        'wiki_url': wikiUrl,
        'image_url': imageUrl,
      };

  static List<String> _decodeList(Object? raw) {
    if (raw == null) return const [];
    final decoded = jsonDecode(raw as String) as List;
    return decoded.cast<String>();
  }
}
