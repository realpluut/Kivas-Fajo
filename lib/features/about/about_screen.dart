import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('About', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text(
          'This is an unofficial fan-made collector\'s companion for the '
          'Star Trek Customizable Card Game, 1st Edition. It is not affiliated '
          'with, endorsed by, or sponsored by CBS, Paramount, Decipher, or '
          'The Continuing Committee. "Star Trek" is a trademark of CBS Studios Inc.',
        ),
        const SizedBox(height: 20),
        Text('Card data', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'Card and set information is sourced from the Star Trek CCG wiki at '
          'cardguide.fandom.com, licensed under Creative Commons '
          'Attribution-Share Alike (CC BY-SA).',
        ),
        TextButton.icon(
          onPressed: () => launchUrl(
            Uri.parse('https://cardguide.fandom.com/wiki/Star_Trek_CCG_1st_Edition'),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('cardguide.fandom.com'),
        ),
        const SizedBox(height: 20),
        Text('Pricing', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'Live prices are pulled from eBay\'s official API. Catawiki, '
          'Marktplaats, Phoenixcards, and Hill\'s Wholesale Gaming are linked '
          'out to their own search results -- this app does not scrape or '
          'store data from those sites.',
        ),
      ],
    );
  }
}
