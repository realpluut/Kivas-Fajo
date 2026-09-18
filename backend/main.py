"""
Backend proxy for eBay pricing lookups.

Why this exists: eBay API credentials must never ship inside the Android
APK (trivially extracted by decompiling it). This tiny service holds the
credentials, talks to eBay's Browse API, and returns normalized results to
the app. It also caches responses briefly and rate-limits per IP so a single
app doesn't burn through eBay's API quota.

Run locally:
    uvicorn main:app --reload --port 8080

Required env vars:
    EBAY_CLIENT_ID, EBAY_CLIENT_SECRET  -- from an eBay Developer account
                                            (developer.ebay.com), production keys
    EBAY_MARKETPLACE_ID                -- optional, default EBAY_US (e.g. EBAY_NL, EBAY_GB)
"""
import os
import time
from collections import defaultdict, deque

import httpx
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware

EBAY_CLIENT_ID = os.environ.get("EBAY_CLIENT_ID", "")
EBAY_CLIENT_SECRET = os.environ.get("EBAY_CLIENT_SECRET", "")
EBAY_MARKETPLACE_ID = os.environ.get("EBAY_MARKETPLACE_ID", "EBAY_US")
EBAY_ENV = os.environ.get("EBAY_ENV", "production")  # "production" or "sandbox"

EBAY_HOST = "api.sandbox.ebay.com" if EBAY_ENV == "sandbox" else "api.ebay.com"
TOKEN_URL = f"https://{EBAY_HOST}/identity/v1/oauth2/token"
SEARCH_URL = f"https://{EBAY_HOST}/buy/browse/v1/item_summary/search"

CACHE_TTL_SECONDS = 30 * 60
RATE_LIMIT_MAX_REQUESTS = 30
RATE_LIMIT_WINDOW_SECONDS = 60

app = FastAPI(title="Star Trek CCG Collector - eBay proxy")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)

_token_cache: dict = {"access_token": None, "expires_at": 0}
_search_cache: dict[str, tuple[float, dict]] = {}
_rate_limit_hits: dict[str, deque] = defaultdict(deque)


def _check_rate_limit(client_ip: str):
    now = time.monotonic()
    hits = _rate_limit_hits[client_ip]
    while hits and now - hits[0] > RATE_LIMIT_WINDOW_SECONDS:
        hits.popleft()
    if len(hits) >= RATE_LIMIT_MAX_REQUESTS:
        raise HTTPException(status_code=429, detail="Too many requests, slow down.")
    hits.append(now)


async def _get_access_token(client: httpx.AsyncClient) -> str:
    if _token_cache["access_token"] and time.time() < _token_cache["expires_at"] - 60:
        return _token_cache["access_token"]
    if not EBAY_CLIENT_ID or not EBAY_CLIENT_SECRET:
        raise HTTPException(status_code=500, detail="Server is missing eBay API credentials.")
    resp = await client.post(
        TOKEN_URL,
        data={"grant_type": "client_credentials", "scope": "https://api.ebay.com/oauth/api_scope"},
        auth=(EBAY_CLIENT_ID, EBAY_CLIENT_SECRET),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail=f"eBay auth failed: {resp.text}")
    data = resp.json()
    _token_cache["access_token"] = data["access_token"]
    _token_cache["expires_at"] = time.time() + data.get("expires_in", 7200)
    return _token_cache["access_token"]


def _normalize_item(item: dict) -> dict:
    price = item.get("price", {})
    image = item.get("image", {}) or item.get("thumbnailImages", [{}])[0]
    return {
        "id": item.get("itemId"),
        "title": item.get("title"),
        "price": price.get("value"),
        "currency": price.get("currency"),
        "condition": item.get("condition"),
        "url": item.get("itemWebUrl"),
        "image_url": image.get("imageUrl"),
        "seller": (item.get("seller") or {}).get("username"),
        "location": (item.get("itemLocation") or {}).get("country"),
    }


@app.get("/ebay-search")
async def ebay_search(request: Request, q: str = Query(..., min_length=2, max_length=200), limit: int = 20):
    client_ip = request.client.host if request.client else "unknown"
    _check_rate_limit(client_ip)

    limit = max(1, min(limit, 50))
    cache_key = f"{q.lower().strip()}::{limit}"
    cached = _search_cache.get(cache_key)
    if cached and time.time() - cached[0] < CACHE_TTL_SECONDS:
        return {**cached[1], "cached": True}

    async with httpx.AsyncClient(timeout=15) as client:
        token = await _get_access_token(client)
        resp = await client.get(
            SEARCH_URL,
            params={"q": q, "limit": limit},
            headers={
                "Authorization": f"Bearer {token}",
                "X-EBAY-C-MARKETPLACE-ID": EBAY_MARKETPLACE_ID,
            },
        )
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail=f"eBay search failed: {resp.text}")

    data = resp.json()
    result = {
        "query": q,
        "total": data.get("total", 0),
        "items": [_normalize_item(i) for i in data.get("itemSummaries", [])],
        "cached": False,
    }
    _search_cache[cache_key] = (time.time(), result)
    return result


@app.get("/healthz")
async def healthz():
    return {"ok": True}
