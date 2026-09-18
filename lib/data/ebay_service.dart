import 'dart:convert';

import 'package:http/http.dart' as http;

class EbayListing {
  final String id;
  final String title;
  final String? price;
  final String? currency;
  final String? condition;
  final String url;
  final String? imageUrl;

  const EbayListing({
    required this.id,
    required this.title,
    required this.price,
    required this.currency,
    required this.condition,
    required this.url,
    required this.imageUrl,
  });

  factory EbayListing.fromJson(Map<String, dynamic> json) => EbayListing(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        price: json['price']?.toString(),
        currency: json['currency'] as String?,
        condition: json['condition'] as String?,
        url: json['url'] as String? ?? '',
        imageUrl: json['image_url'] as String?,
      );
}

/// Talks to our own backend proxy (see /backend), never to eBay directly --
/// the app must never hold eBay API credentials.
class EbayService {
  EbayService({required this.backendBaseUrl});

  /// Set this to your deployed backend URL, e.g. via --dart-define at build time:
  ///   flutter build apk --dart-define=BACKEND_URL=https://your-backend.example.com
  final String backendBaseUrl;

  Future<List<EbayListing>> search(String cardName) async {
    if (backendBaseUrl.isEmpty) return [];
    final uri = Uri.parse('$backendBaseUrl/ebay-search').replace(
      queryParameters: {'q': 'Star Trek CCG $cardName', 'limit': '10'},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('eBay lookup failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['items'] as List?) ?? const [];
    return items.map((e) => EbayListing.fromJson(e as Map<String, dynamic>)).toList();
  }
}
