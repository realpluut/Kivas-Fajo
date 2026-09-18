/// Builds outbound search URLs for marketplaces that don't offer a public
/// API. We never scrape these sites -- the app just opens their own search
/// results page for the card name, same as a user typing it in themselves.
class MarketplaceLink {
  final String label;
  final String url;
  const MarketplaceLink(this.label, this.url);
}

List<MarketplaceLink> marketplaceLinksFor(String cardName) {
  final q = Uri.encodeComponent('Star Trek CCG $cardName');
  final qPlus = Uri.encodeComponent('Star Trek CCG $cardName').replaceAll('%20', '+');
  return [
    MarketplaceLink('eBay', 'https://www.ebay.com/sch/i.html?_nkw=$q'),
    MarketplaceLink('Catawiki', 'https://www.catawiki.com/en/s?q=$q'),
    MarketplaceLink('Marktplaats', 'https://www.marktplaats.nl/q/$qPlus/'),
    // phoenixcards.com runs WooCommerce, whose built-in product search is ?s=...&post_type=product
    MarketplaceLink('Phoenixcards', 'https://phoenixcards.com/?s=$q&post_type=product'),
    // wholesalegaming.com (Hill's Wholesale Gaming) has no on-site text search --
    // it's pure category browsing -- so a site-scoped Google search is the
    // honest equivalent of "search this store for a card name".
    MarketplaceLink("Hill's Wholesale Gaming", 'https://www.google.com/search?q=site:wholesalegaming.com+$q'),
  ];
}
