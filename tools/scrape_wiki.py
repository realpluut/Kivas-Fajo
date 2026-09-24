"""
Pulls the Star Trek CCG 1st Edition card database out of cardguide.fandom.com
via the site's MediaWiki API (api.php) -- no HTML scraping.

Output: ../assets/sets.json, ../assets/cards.json

Fandom wiki text is CC BY-SA -- the app must credit cardguide.fandom.com and
link back to it (see the About screen).

Usage: python3 scrape_wiki.py [--limit-sets N] [--no-cache]
"""
import argparse
import hashlib
import json
import re
import sys
import time
from pathlib import Path

import mwparserfromhell as mwp
import requests

API = "https://cardguide.fandom.com/api.php"
BASE = "https://cardguide.fandom.com/wiki/"
CACHE_DIR = Path(__file__).parent / "cache"
ASSETS_DIR = Path(__file__).parent.parent / "assets"
SESSION = requests.Session()
SESSION.headers.update({"User-Agent": "StarTrekCCGCollector/1.0 (data pipeline; contact via app store listing)"})

USE_CACHE = True


def _cache_path(key: str) -> Path:
    h = hashlib.sha1(key.encode("utf-8")).hexdigest()
    return CACHE_DIR / f"{h}.json"


def api_get(params: dict) -> dict:
    key = json.dumps(params, sort_keys=True)
    cp = _cache_path(key)
    if USE_CACHE and cp.exists():
        return json.loads(cp.read_text(encoding="utf-8"))
    for attempt in range(5):
        try:
            resp = SESSION.get(API, params={**params, "format": "json"}, timeout=30)
            resp.raise_for_status()
            data = resp.json()
            break
        except (requests.RequestException, ValueError) as e:
            wait = 2 ** attempt
            print(f"  ! request failed ({e}), retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)
    else:
        raise RuntimeError(f"API call failed after retries: {params}")
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cp.write_text(json.dumps(data), encoding="utf-8")
    return data


def get_wikitext(page_title: str) -> str | None:
    data = api_get({"action": "parse", "page": page_title, "prop": "wikitext", "redirects": 1})
    if "error" in data:
        return None
    return data["parse"]["wikitext"]["*"]


def get_wikitext_batch(titles: list[str]) -> dict[str, str]:
    """Batch fetch raw wikitext for up to 50 pages per call via prop=revisions."""
    out: dict[str, str] = {}
    for i in range(0, len(titles), 50):
        chunk = titles[i : i + 50]
        data = api_get(
            {
                "action": "query",
                "titles": "|".join(chunk),
                "prop": "revisions",
                "rvprop": "content",
                "rvslots": "main",
                "redirects": 1,
            }
        )
        pages = data.get("query", {}).get("pages", {})
        normalized = {n["from"]: n["to"] for n in data.get("query", {}).get("normalized", [])}
        redirects = {r["from"]: r["to"] for r in data.get("query", {}).get("redirects", [])}
        title_by_pageid = {}
        for _pid, p in pages.items():
            title_by_pageid[p["title"]] = p
            rev = p.get("revisions", [{}])[0]
            content = rev.get("slots", {}).get("main", {}).get("*", "")
            out[p["title"]] = content
        # map original requested titles (through normalization/redirects) back to content
        for orig in chunk:
            resolved = redirects.get(normalized.get(orig, orig), normalized.get(orig, orig))
            if orig not in out and resolved in out:
                out[orig] = out[resolved]
    return out


def resolve_image_urls(filenames: list[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    uniq = sorted(set(f for f in filenames if f))
    for i in range(0, len(uniq), 50):
        chunk = uniq[i : i + 50]
        titles = [f"File:{f}" for f in chunk]
        data = api_get(
            {
                "action": "query",
                "titles": "|".join(titles),
                "prop": "imageinfo",
                "iiprop": "url",
            }
        )
        pages = data.get("query", {}).get("pages", {})
        normalized = {n["from"]: n["to"] for n in data.get("query", {}).get("normalized", [])}
        title_to_url = {}
        for _pid, p in pages.items():
            info = p.get("imageinfo")
            if info:
                title_to_url[p["title"]] = info[0]["url"]
        for orig_fn, orig_title in zip(chunk, titles):
            resolved = normalized.get(orig_title, orig_title)
            if resolved in title_to_url:
                out[orig_fn] = title_to_url[resolved]
    return out


_FILE_PARAM_RE = re.compile(
    r"^(\d+x?\d*px|left|right|center|centre|none|thumb|thumbnail|frame|framed|border|top|bottom|middle)$",
    re.IGNORECASE,
)


def plain_text(wikitext_fragment: str) -> str:
    if not wikitext_fragment:
        return ""
    code = mwp.parse(wikitext_fragment)
    # File/Image links (e.g. "[[File:Qicon.jpg|Q icon|16px]]") are inline
    # icons -- mwparserfromhell doesn't know their pipe-separated params are
    # size/caption, so strip_code() would render the raw "Q icon|16px" text.
    # Keep whichever param looks like a caption (not a size/alignment
    # keyword) and drop the rest.
    for link in code.filter_wikilinks():
        if not str(link.title).strip().lower().startswith(("file:", "image:")):
            continue
        caption = ""
        if link.text is not None:
            parts = [p.strip() for p in str(link.text).split("|")]
            captions = [p for p in parts if p and not _FILE_PARAM_RE.match(p)]
            caption = captions[-1] if captions else ""
        code.replace(link, caption)
    text = code.strip_code(normalize=True, collapse=True)
    text = re.sub(r"\s+", " ", text).strip()
    # Icon captions are often immediately followed by a separate wikilink
    # spelling out the same word (e.g. "Federation" icon + [[Federation]]).
    text = re.sub(r"\b(\w[\w\s]{0,30}?)\s+\1\b", r"\1", text)
    return text


def first_wikilink_target(wikitext_fragment: str, prefix: str) -> str | None:
    code = mwp.parse(wikitext_fragment or "")
    for link in code.filter_wikilinks():
        target = str(link.title).strip()
        if target.lower().startswith(prefix.lower()):
            return target[len(prefix):].strip()
    return None


def wikilink_texts(wikitext_fragment: str, prefix_exclude: tuple[str, ...] = ("File:", "Image:", "Category:")) -> list[str]:
    code = mwp.parse(wikitext_fragment or "")
    out = []
    for link in code.filter_wikilinks():
        target = str(link.title).strip()
        if any(target.lower().startswith(p.lower()) for p in prefix_exclude):
            continue
        display = str(link.text).strip() if link.text else target
        out.append(display)
    return out


def category_link_texts(wikitext_fragment: str) -> list[str]:
    code = mwp.parse(wikitext_fragment or "")
    out = []
    for link in code.filter_wikilinks():
        target = str(link.title).strip()
        if target.lower().startswith("category:"):
            display = str(link.text).strip() if link.text else target[len("Category:"):]
            out.append(display)
    return out


def external_links(wikitext_fragment: str) -> list[str]:
    code = mwp.parse(wikitext_fragment or "")
    return [str(l.url).strip() for l in code.filter_external_links()]


ATTR_PREFIX_RE = re.compile(
    r"^\s*(?:[a-zA-Z][\w-]*\s*=\s*(?:\"[^\"]*\"|'[^']*'|[^\s|]+)\s*)+\|(?!\|)(.*)$",
    re.S,
)


def _strip_cell_attrs(cell: str) -> str:
    m = ATTR_PREFIX_RE.match(cell)
    return m.group(1) if m else cell


def extract_all_tables(wikitext: str) -> list[str]:
    """Return every top-level {| ... |} block found anywhere in the page."""
    tables = []
    i = 0
    n = len(wikitext)
    while True:
        start = wikitext.find("{|", i)
        if start == -1:
            break
        depth = 0
        j = start
        while j < n:
            if wikitext.startswith("{|", j):
                depth += 1
                j += 2
                continue
            if wikitext.startswith("|}", j):
                depth -= 1
                j += 2
                if depth == 0:
                    tables.append(wikitext[start:j])
                    break
                continue
            j += 1
        else:
            break
        i = j
    return tables


def extract_table(wikitext: str, after_marker: str | None = None) -> str | None:
    """Return the raw {| ... |} block for the first wikitable found after
    after_marker (or anywhere if after_marker is None)."""
    start_search = 0
    if after_marker:
        idx = wikitext.find(after_marker)
        if idx == -1:
            return None
        start_search = idx
    start = wikitext.find("{|", start_search)
    if start == -1:
        return None
    depth = 0
    i = start
    while i < len(wikitext):
        if wikitext.startswith("{|", i):
            depth += 1
            i += 2
            continue
        if wikitext.startswith("|}", i):
            depth -= 1
            i += 2
            if depth == 0:
                return wikitext[start:i]
            continue
        i += 1
    return None


def parse_table_rows(table_block: str) -> list[list[str]]:
    """Very small pipe-table parser tuned to this wiki's table style.
    Returns a list of rows; each row is a list of cell wikitext strings."""
    if not table_block:
        return []
    # drop the opening "{|...\n" line and closing "|}"
    body = table_block
    first_nl = body.find("\n")
    body = body[first_nl + 1 :] if first_nl != -1 else ""
    body = body.rsplit("|}", 1)[0]

    rows: list[list[str]] = []
    current_cells: list[str] = []
    current_cell_lines: list[str] = []
    mode = None  # "header" or "data"

    def flush_cell():
        nonlocal current_cell_lines, mode
        if current_cell_lines:
            raw = "\n".join(current_cell_lines)
            sep = "!!" if mode == "header" else "||"
            for part in raw.split(sep):
                current_cells.append(_strip_cell_attrs(part.strip()).strip())
            current_cell_lines = []

    def flush_row():
        nonlocal current_cells
        flush_cell()
        if current_cells:
            rows.append(current_cells)
        current_cells = []

    for line in body.split("\n"):
        stripped = line.strip()
        if stripped.startswith("|-"):
            flush_row()
            mode = None
        elif stripped.startswith("|+"):
            # Table caption syntax (e.g. a bare "|+" with no caption text).
            # Not a cell -- if left to fall through to the generic "|" branch
            # below it gets absorbed as a phantom leading cell, shifting
            # every column index in the table by one and silently
            # corrupting every row (a card's title cell gets read from the
            # RARITY column instead, etc).
            continue
        elif stripped.startswith("!"):
            flush_cell()
            mode = "header"
            current_cell_lines.append(stripped[1:])
        elif stripped.startswith("|"):
            flush_cell()
            mode = "data"
            current_cell_lines.append(stripped[1:])
        else:
            if current_cell_lines:
                current_cell_lines.append(stripped)
    flush_row()
    return rows


def slugify(title: str) -> str:
    s = title.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")


# ---------------------------------------------------------------------------
# Step 1: parse the top-level page's Expansions + Virtual Expansions tables
# ---------------------------------------------------------------------------

_BORDER_COLOR_PATTERNS = [
    re.compile(r"consists of [\d,]+\s*(\w+)[- ]bordered?\s+cards", re.IGNORECASE),
    re.compile(r"all\b[^.]*?cards are\s*(\w+)[- ]?bordered", re.IGNORECASE),
    re.compile(r"(?:is|are) the (\w+) borders?\s+on the cards", re.IGNORECASE),
    re.compile(r"has a (\w+) border on the cards", re.IGNORECASE),
    re.compile(r"(\w+) border(?:ed)? premium cards", re.IGNORECASE),
]
_BORDER_COLORS = {"black", "white", "silver", "gold"}

# Border colors confirmed against physical cards but not stated anywhere on
# the wiki page text, so extract_border_color() can't find them. Keyed by
# page_title. Add to this as more get confirmed.
_BORDER_COLOR_OVERRIDES = {
    "Alternate Universe": "black",
    "Warp Pack (expansion)": "white",
}


def extract_border_color(wikitext: str) -> str | None:
    """Star Trek CCG 1st Edition's base set was reprinted several times with
    the *same* 363 card names but a different border color per printing
    (Premiere Limited = black, Unlimited '94/'95 = white, Collector's Tin =
    silver) -- a much stronger disambiguator for those printings than year,
    since e.g. Collector's Tin cards are physically dated 1994 despite
    releasing in 1995. Only a handful of set pages state this outright, in a
    small number of consistent sentence patterns; match those precisely
    rather than "nearest color word to 'border'", which false-matches on
    sets that merely mention another set's border color in passing."""
    intro = wikitext.split("==", 1)[0]
    for pat in _BORDER_COLOR_PATTERNS:
        for m in pat.finditer(intro):
            word = m.group(1).lower()
            if word in _BORDER_COLORS:
                return word
    return None


def parse_sets() -> list[dict]:
    wt = get_wikitext("Star Trek CCG 1st Edition")
    assert wt, "could not fetch top-level page"
    sets = []

    def parse_expansion_table(marker: str, category: str):
        table = extract_table(wt, after_marker=marker)
        if not table:
            print(f"  ! no table found after marker {marker!r}", file=sys.stderr)
            return
        rows = parse_table_rows(table)
        order = 0
        for row in rows:
            if len(row) < 4:
                continue
            # header row detection: contains literal column names
            joined = " ".join(row).upper()
            if "EXPANSION" in joined and "CARDS" in joined:
                continue
            # columns: ICON | # | EXPANSION | YEAR,DATE | #CARDS [| BLOCK]
            icon_cell, num_cell, name_cell, date_cell, count_cell = row[0], row[1], row[2], row[3], row[4]
            block_cell = row[5] if len(row) > 5 else ""
            name_plain = plain_text(name_cell)
            if not name_plain or "TOTAL NUMBER OF CARDS" in name_plain.upper():
                continue
            code = mwp.parse(name_cell)
            links = code.filter_wikilinks()
            page_title = str(links[0].title).strip() if links else name_plain
            icon_files = [
                str(l.title)[len("File:") :].strip()
                for l in mwp.parse(icon_cell).filter_wikilinks()
                if str(l.title).lower().startswith("file:")
            ]
            order += 1
            sets.append(
                {
                    "id": slugify(page_title),
                    "name": name_plain,
                    "page_title": page_title,
                    "category": category,
                    "order": order,
                    "date": plain_text(date_cell),
                    "card_count_hint": plain_text(count_cell),
                    "block": plain_text(block_cell) or None,
                    "icon_files": icon_files,
                }
            )

    parse_expansion_table("==Expansions==", "physical")
    parse_expansion_table("==Virtual Expansions==", "virtual")

    # The wiki's top-level Expansions table used to list "Blaze of Glory Foil
    # Cards" as its own row (anchor-linked to a "#Foil_Set" section of the
    # Blaze of Glory page); the current table no longer has that row, so
    # those 18 cards would otherwise just merge into the base "Blaze of
    # Glory" set's card list. Collectors track the foil printing separately
    # from the base set, so keep it a set of its own here -- the actual foil
    # cards get pulled back out of the merged card-list rows in main(), by
    # page_title suffix ("(Foil)"), a real and stable naming pattern used on
    # every foil card's own wiki page title.
    base = next((s for s in sets if s["id"] == "blaze-of-glory-expansion"), None)
    if base:
        sets.append(
            {
                "id": "blaze-of-glory-foil-cards",
                "name": "Blaze of Glory Foil Cards",
                "page_title": base["page_title"],
                "category": base["category"],
                "order": base["order"] + 1,
                "date": base["date"],
                "card_count_hint": "18",
                "block": base["block"],
                "icon_files": list(base.get("icon_files", [])),
            }
        )

    return sets


# ---------------------------------------------------------------------------
# Step 2: parse each set's "Card List" table -> one row per printing
# ---------------------------------------------------------------------------

def parse_card_list(set_page_title: str) -> list[dict]:
    """Card-list tables are NOT consistently laid out across the wiki: column
    order, count, and even spelling ("AFFILATION" vs "AFFILIATION") vary by
    page, and some pages split the list across multiple tables. So: scan
    every table on the page, keep the ones whose header row contains TITLE,
    and map columns by header name rather than position."""
    wt = get_wikitext(set_page_title)
    if not wt:
        print(f"  ! could not fetch set page {set_page_title!r}", file=sys.stderr)
        return []
    out = []
    seen_page_titles = set()
    for table in extract_all_tables(wt):
        rows = parse_table_rows(table)
        if not rows:
            continue
        header = [c.strip().upper() for c in rows[0]]
        col = {name: i for i, name in enumerate(header)}
        title_i = col.get("TITLE")
        if title_i is None:
            # A few pages mislabel the title column's header (e.g. a
            # duplicated "TYPE"). Fall back to whichever column is a
            # wikilink in most data rows -- that's the card link.
            best_i, best_count = None, 0
            for ci in range(len(header)):
                cnt = sum(1 for row in rows[1:] if ci < len(row) and "[[" in row[ci])
                if cnt > best_count:
                    best_i, best_count = ci, cnt
            if best_count >= max(1, (len(rows) - 1) // 2):
                title_i = best_i
        if title_i is None:
            continue
        rarity_i = col.get("RARITY")
        type_i = col.get("TYPE")
        affil_i = col.get("AFFILIATION", col.get("AFFILATION"))

        def cell(row, i):
            return row[i] if i is not None and i < len(row) else ""

        for row in rows[1:]:
            title_cell = cell(row, title_i)
            if not title_cell.strip():
                continue
            code = mwp.parse(title_cell)
            links = code.filter_wikilinks()
            if links:
                page_title = str(links[0].title).strip()
                display = str(links[0].text).strip() if links[0].text else page_title
            else:
                page_title = display = plain_text(title_cell)
            if not page_title or page_title in seen_page_titles:
                continue
            seen_page_titles.add(page_title)
            out.append(
                {
                    "page_title": page_title,
                    "display_name": display,
                    "rarity": plain_text(cell(row, rarity_i)),
                    "type": plain_text(cell(row, type_i)),
                    "affiliation": plain_text(cell(row, affil_i)),
                }
            )
    return out


# ---------------------------------------------------------------------------
# Step 3: parse each card page's stats infobox table
# ---------------------------------------------------------------------------

LABEL_MAP = {
    "rarity": "rarity",
    "printing": "printing",
    "type": "type",
    "property logo": "property_logo",
    "icons": "icons_raw",
    "lore": "lore",
    "game text": "game_text",
    "versions": "versions_raw",
    "characteristics": "characteristics",
    "legal card pools": "legal_card_pools",
    "legal rules sets": "legal_rules_sets",
    "characters": "characters",
    "actors": "actors",
    "external links": "external_links_raw",
    "affiliation": "affiliation",
}


def parse_card_infobox(wt: str) -> dict:
    result: dict = {}
    table = extract_table(wt, after_marker="Statistics")
    if not table:
        table = extract_table(wt)
    if not table:
        return result
    rows = parse_table_rows(table)
    for row in rows:
        if len(row) != 2:
            continue
        label = plain_text(row[0]).strip().lower()
        key = LABEL_MAP.get(label)
        if not key:
            continue
        raw_val = row[1]
        if key in ("lore", "game_text"):
            result[key] = plain_text(raw_val)
        elif key == "external_links_raw":
            result["external_links"] = external_links(raw_val)
        elif key in ("property_logo", "printing", "rarity", "type", "affiliation"):
            txt = plain_text(raw_val)
            result[key] = None if txt.lower() == "none" else txt
        elif key in ("characteristics", "characters", "actors", "legal_card_pools", "legal_rules_sets"):
            vals = category_link_texts(raw_val) or wikilink_texts(raw_val)
            if not vals:
                txt = plain_text(raw_val)
                vals = [] if txt.lower() == "none" else [v.strip() for v in txt.split(",") if v.strip()]
            result[key] = vals
        elif key == "versions_raw":
            pass  # not needed: set membership already comes from the set's Card List table
        elif key == "icons_raw":
            pass
    # first image on the page (usually the card image, appears before the infobox)
    code = mwp.parse(wt)
    for link in code.filter_wikilinks():
        target = str(link.title).strip()
        if target.lower().startswith(("file:", "image:")):
            result["image_file"] = target.split(":", 1)[1].strip()
            break
    return result


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def main():
    global USE_CACHE
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit-sets", type=int, default=None, help="only process first N sets (debugging)")
    ap.add_argument("--no-cache", action="store_true")
    args = ap.parse_args()
    if args.no_cache:
        USE_CACHE = False

    print("Fetching set list from top-level page...")
    sets = parse_sets()
    if args.limit_sets:
        sets = sets[: args.limit_sets]
    print(f"Found {len(sets)} sets.")

    all_card_rows: list[dict] = []  # from card-list tables, tagged with set id
    for s in sets:
        if s["id"] == "blaze-of-glory-foil-cards":
            # Shares a page_title with blaze-of-glory-expansion (see
            # parse_sets) -- its cards get split out of that set's rows
            # below instead of parsing the same page a second time. Same
            # physical border color as the base set (foil is a finish, not
            # a different border scheme); that set is processed earlier in
            # this loop, so its border_color is already known here.
            base = next((x for x in sets if x["id"] == "blaze-of-glory-expansion"), None)
            s["border_color"] = base["border_color"] if base else None
            continue
        set_wikitext = get_wikitext(s["page_title"]) or ""
        s["border_color"] = _BORDER_COLOR_OVERRIDES.get(s["page_title"]) or extract_border_color(set_wikitext)
        rows = parse_card_list(s["page_title"])
        print(f"  {s['name']!r}: {len(rows)} card rows" + (f" [{s['border_color']} border]" if s["border_color"] else ""))
        for r in rows:
            r["set_id"] = s["id"]
        all_card_rows.extend(rows)
        time.sleep(0.05)

    # Split the Blaze of Glory foil printings back out into their own set
    # (see parse_sets) -- every foil card's own wiki page title ends in
    # "(Foil)", a real and stable naming pattern.
    foil_count = 0
    for r in all_card_rows:
        if r["set_id"] == "blaze-of-glory-expansion" and r["page_title"].endswith("(Foil)"):
            r["set_id"] = "blaze-of-glory-foil-cards"
            foil_count += 1
    if foil_count:
        print(f"  Split {foil_count} foil printings into 'blaze-of-glory-foil-cards'")

    print(f"Total card printings across all sets: {len(all_card_rows)}")

    unique_page_titles = sorted({r["page_title"] for r in all_card_rows})
    print(f"Fetching wikitext for {len(unique_page_titles)} unique card pages (batched)...")
    wikitext_by_title: dict[str, str] = {}
    for i in range(0, len(unique_page_titles), 50):
        chunk = unique_page_titles[i : i + 50]
        wikitext_by_title.update(get_wikitext_batch(chunk))
        print(f"  fetched {min(i+50, len(unique_page_titles))}/{len(unique_page_titles)}")

    print("Parsing card infoboxes...")
    cards = []
    image_files_needed = []
    for r in all_card_rows:
        wt = wikitext_by_title.get(r["page_title"], "")
        infobox = parse_card_infobox(wt) if wt else {}
        image_file = infobox.get("image_file")
        if image_file:
            image_files_needed.append(image_file)
        card_id = slugify(r["page_title"])
        base_name = re.sub(r"\s*\([^)]*\)\s*$", "", r["display_name"]).strip()
        cards.append(
            {
                "id": card_id,
                "page_title": r["page_title"],
                "name": r["display_name"],
                "base_name": base_name or r["display_name"],
                "set_id": r["set_id"],
                "rarity": infobox.get("rarity") or r["rarity"] or None,
                "type": infobox.get("type") or r["type"] or None,
                "affiliation": infobox.get("affiliation") or r["affiliation"] or None,
                "printing": infobox.get("printing"),
                "property_logo": infobox.get("property_logo"),
                "lore": infobox.get("lore"),
                "game_text": infobox.get("game_text"),
                "characteristics": infobox.get("characteristics") or [],
                "legal_card_pools": infobox.get("legal_card_pools") or [],
                "legal_rules_sets": infobox.get("legal_rules_sets") or [],
                "characters": infobox.get("characters") or [],
                "actors": infobox.get("actors") or [],
                "external_links": infobox.get("external_links") or [],
                "wiki_url": BASE + r["page_title"].replace(" ", "_"),
                "image_file": image_file,
                "image_url": None,  # filled in below
            }
        )

    # Disambiguate id collisions: distinct names can slugify the same way
    # (e.g. "Rare" / "Rare+"), and a handful of pages are listed in more than
    # one set's checklist. Keep ids stable for the common case and only
    # append the set id where a real collision happens.
    seen_ids: dict[str, int] = {}
    for c in cards:
        base_id = c["id"]
        seen_ids[base_id] = seen_ids.get(base_id, 0) + 1
        if seen_ids[base_id] > 1:
            c["id"] = f"{base_id}--{c['set_id']}"

    print(f"Resolving {len(set(image_files_needed))} unique image URLs (batched)...")
    url_by_file = resolve_image_urls(image_files_needed)
    for c in cards:
        if c["image_file"]:
            c["image_url"] = url_by_file.get(c["image_file"])

    print(f"Resolving set icon URLs...")
    all_icon_files = [f for s in sets for f in s.get("icon_files", [])]
    icon_url_by_file = resolve_image_urls(all_icon_files)
    for s in sets:
        s["icon_urls"] = [icon_url_by_file[f] for f in s.get("icon_files", []) if f in icon_url_by_file]
        s.pop("icon_files", None)
        s["wiki_url"] = BASE + s["page_title"].replace(" ", "_")
        if s["id"] == "blaze-of-glory-foil-cards":
            s["wiki_url"] += "#Foil_Set"

    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    (ASSETS_DIR / "sets.json").write_text(json.dumps(sets, indent=2, ensure_ascii=False), encoding="utf-8")
    (ASSETS_DIR / "cards.json").write_text(json.dumps(cards, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Wrote {len(sets)} sets and {len(cards)} cards to {ASSETS_DIR}")


if __name__ == "__main__":
    main()
