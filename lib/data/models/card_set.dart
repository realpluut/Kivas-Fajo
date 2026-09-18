class CardSet {
  final String id;
  final String name;
  final String pageTitle;
  final String category; // "physical" or "virtual"
  final int order;
  final String date;
  final String cardCountHint;
  final String? block;
  final String? iconUrl;
  final String wikiUrl;

  /// "black" | "white" | "silver" | "gold" | null. Only set for the handful
  /// of printings where the wiki states it outright (mainly the Premiere
  /// base-set reprints) -- see tools/scrape_wiki.py's extract_border_color.
  /// A much stronger scanner disambiguator than year for those printings,
  /// since e.g. Collector's Tin cards are physically dated 1994 despite
  /// releasing in 1995.
  final String? borderColor;

  /// First 4-digit year found in [date] (e.g. "1994, November 10" -> 1994).
  /// Used as a proxy for the copyright year printed on a card, to help the
  /// scanner disambiguate which printing/set a physical card belongs to.
  int? get year {
    final m = RegExp(r'\d{4}').firstMatch(date);
    return m == null ? null : int.tryParse(m.group(0)!);
  }

  const CardSet({
    required this.id,
    required this.name,
    required this.pageTitle,
    required this.category,
    required this.order,
    required this.date,
    required this.cardCountHint,
    required this.block,
    required this.iconUrl,
    required this.wikiUrl,
    this.borderColor,
  });

  factory CardSet.fromJson(Map<String, dynamic> json) {
    final icons = (json['icon_urls'] as List?)?.cast<String>() ?? const [];
    return CardSet(
      id: json['id'] as String,
      name: json['name'] as String,
      pageTitle: json['page_title'] as String,
      category: json['category'] as String,
      order: json['order'] as int,
      date: json['date'] as String? ?? '',
      cardCountHint: json['card_count_hint'] as String? ?? '',
      block: json['block'] as String?,
      iconUrl: icons.isNotEmpty ? icons.first : null,
      wikiUrl: json['wiki_url'] as String,
      borderColor: json['border_color'] as String?,
    );
  }

  factory CardSet.fromRow(Map<String, Object?> row) => CardSet(
        id: row['id'] as String,
        name: row['name'] as String,
        pageTitle: row['page_title'] as String,
        category: row['category'] as String,
        order: row['order_index'] as int,
        date: row['date'] as String? ?? '',
        cardCountHint: row['card_count_hint'] as String? ?? '',
        block: row['block'] as String?,
        iconUrl: row['icon_url'] as String?,
        wikiUrl: row['wiki_url'] as String,
        borderColor: row['border_color'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'page_title': pageTitle,
        'category': category,
        'order_index': order,
        'date': date,
        'card_count_hint': cardCountHint,
        'block': block,
        'icon_url': iconUrl,
        'wiki_url': wikiUrl,
        'border_color': borderColor,
      };
}
