class CollectionEntry {
  final String cardId;
  final bool owned;
  final bool wanted;
  final int quantity;
  final String? condition;
  final String? notes;

  const CollectionEntry({
    required this.cardId,
    this.owned = false,
    this.wanted = false,
    this.quantity = 0,
    this.condition,
    this.notes,
  });

  static const empty = CollectionEntry(cardId: '');

  factory CollectionEntry.fromRow(Map<String, Object?> row) => CollectionEntry(
        cardId: row['card_id'] as String,
        owned: (row['owned'] as int) == 1,
        wanted: (row['wanted'] as int) == 1,
        quantity: row['quantity'] as int,
        condition: row['condition'] as String?,
        notes: row['notes'] as String?,
      );

  Map<String, Object?> toRow() => {
        'card_id': cardId,
        'owned': owned ? 1 : 0,
        'wanted': wanted ? 1 : 0,
        'quantity': quantity,
        'condition': condition,
        'notes': notes,
        'updated_at': DateTime.now().toIso8601String(),
      };

  CollectionEntry copyWith({
    bool? owned,
    bool? wanted,
    int? quantity,
    String? condition,
    String? notes,
  }) =>
      CollectionEntry(
        cardId: cardId,
        owned: owned ?? this.owned,
        wanted: wanted ?? this.wanted,
        quantity: quantity ?? this.quantity,
        condition: condition ?? this.condition,
        notes: notes ?? this.notes,
      );
}
