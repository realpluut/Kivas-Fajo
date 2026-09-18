# Star Trek CCG Collector

An unofficial fan-made Android (and later iOS) app for collectors of the Star
Trek Customizable Card Game, 1st Edition. Browse the full card database, track
what you own/want, and check prices across eBay and other marketplaces. Not
affiliated with CBS, Paramount, Decipher, or The Continuing Committee.

## Layout

- `tools/scrape_wiki.py` — offline data pipeline. Pulls sets and cards from
  cardguide.fandom.com's MediaWiki API (`api.php`) and writes
  `assets/sets.json` / `assets/cards.json`. Re-run it whenever the wiki
  changes; results are cached under `tools/cache/` so re-runs are cheap.
  Card text on that wiki is CC BY-SA — the app's About screen credits it.
- `assets/` — bundled card database (98 sets, ~8,660 card printings), imported
  into a local SQLite DB on first launch.
- `lib/` — the Flutter app (Riverpod + sqflite). See `lib/data/` for the
  repositories/DB layer and `lib/features/` for the screens.
- `backend/` — a small FastAPI proxy that holds eBay API credentials
  server-side and returns normalized search results. The app never talks to
  eBay directly (an embedded API key in the APK would be trivially
  extractable).

## Running the app

Requires Flutter (stable), a JDK, and the Android SDK — `flutter doctor`
should report everything green.

```
flutter pub get
flutter run
```

By default the app has no eBay backend configured and just shows the
marketplace search-link buttons. To point it at a deployed backend:

```
flutter build apk --dart-define=BACKEND_URL=https://your-backend.example.com
```

## Running the backend

```
cd backend
pip install -r requirements.txt
export EBAY_CLIENT_ID=...      # from an eBay Developer account (developer.ebay.com)
export EBAY_CLIENT_SECRET=...
uvicorn main:app --reload --port 8080
```

Deploy anywhere that runs a container (Cloud Run, Fly.io, etc.) — see
`backend/Dockerfile`.

## Known gaps / next steps

- **eBay credentials**: you need to register an eBay Developer account and
  get production API keys before the price lookups do anything.
- **Marketplace links**: Catawiki, Marktplaats, and Phoenixcards have real
  on-site search; Hill's Wholesale Gaming has no text search on their site,
  so that button falls back to a site-scoped Google search.
- **iOS**: the app was built Android-first but avoids Android-only APIs, so
  adding the iOS platform later (`flutter create --platforms ios .`) should
  mostly be packaging/signing, not a rewrite.
- **Branding**: pick a real app name/icon before a Play Store submission —
  avoid using "Star Trek" as the primary app name for trademark reasons.
- **Data refresh**: bump `kCurrentDataVersion` in `lib/data/db.dart` whenever
  you regenerate `assets/*.json`, so existing installs reseed their local DB.
