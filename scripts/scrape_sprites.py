#!/usr/bin/env python3
"""Scrape Pokémon sprites from pokemondb.net for use as game assets.

Preferring Gen 5 Black/White art, this downloads two variants per Pokémon:

  * static  -> https://img.pokemondb.net/sprites/black-white/normal/<slug>.png
  * animated -> https://img.pokemondb.net/sprites/black-white/anim/normal/<slug>.gif

The authoritative slug list (in National Dex order) is scraped from
https://pokemondb.net/sprites, so names like ``nidoran-f`` / ``farfetchd`` are
handled correctly. By default it fetches all 151 Generation 1 Pokémon.

Stdlib-only (matches the rest of this repo). Idempotent: existing files are
skipped unless ``--overwrite`` is passed.

Examples
--------
    python scripts/scrape_sprites.py                 # all Gen 1
    python scripts/scrape_sprites.py --generation 1  # explicit
    python scripts/scrape_sprites.py --count 9       # first 9 (starters)
    python scripts/scrape_sprites.py --out assets/sprites --overwrite
"""
from __future__ import annotations

import argparse
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

INDEX_URL = "https://pokemondb.net/sprites"
IMG_BASE = "https://img.pokemondb.net/sprites"
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) pokemon-crawlers-sprite-scraper/1.0 "
    "(+https://github.com/danielbussone/pokemon-crawlers)"
)

# Last National Dex number for each generation.
GEN_LAST_DEX = {
    1: 151,
    2: 251,
    3: 386,
    4: 493,
    5: 649,
    6: 721,
    7: 809,
    8: 905,
    9: 1025,
}

# name -> (remote subpath, file extension). Preference order: Black/White.
VARIANTS: dict[str, tuple[str, str]] = {
    "black-white static": ("black-white/normal", "png"),
    "black-white animated": ("black-white/anim/normal", "gif"),
}

SLUG_RE = re.compile(r'href="/sprites/([a-z0-9][a-z0-9-]*)"')


def fetch(url: str, *, retries: int = 4, backoff: float = 2.0) -> bytes:
    """GET ``url`` returning raw bytes, retrying transient failures."""
    last_err: Exception | None = None
    for attempt in range(retries):
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.read()
        except urllib.error.HTTPError as err:
            # 404 is a definitive "not found" — don't waste retries on it.
            if err.code == 404:
                raise
            last_err = err
        except (urllib.error.URLError, TimeoutError) as err:
            last_err = err
        if attempt < retries - 1:
            time.sleep(backoff * (2**attempt))
    assert last_err is not None
    raise last_err


def get_slugs(limit: int) -> list[str]:
    """Return the first ``limit`` sprite slugs in National Dex order."""
    html = fetch(INDEX_URL).decode("utf-8", "replace")
    seen: set[str] = set()
    slugs: list[str] = []
    for match in SLUG_RE.finditer(html):
        slug = match.group(1)
        if slug not in seen:
            seen.add(slug)
            slugs.append(slug)
        if len(slugs) >= limit:
            break
    if len(slugs) < limit:
        raise RuntimeError(
            f"Only found {len(slugs)} slugs on {INDEX_URL}, expected {limit}."
        )
    return slugs[:limit]


def download_variant(
    slug: str, subpath: str, ext: str, out_root: Path, *, overwrite: bool
) -> str:
    """Download one sprite variant. Returns 'saved' | 'skipped' | 'missing'."""
    dest = out_root / subpath / f"{slug}.{ext}"
    if dest.exists() and not overwrite:
        return "skipped"
    url = f"{IMG_BASE}/{subpath}/{slug}.{ext}"
    try:
        data = fetch(url)
    except urllib.error.HTTPError as err:
        if err.code == 404:
            return "missing"
        raise
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    return "saved"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--generation",
        type=int,
        choices=sorted(GEN_LAST_DEX),
        default=1,
        help="Cumulative generation to fetch through (default: 1 = Gen 1).",
    )
    group.add_argument(
        "--count",
        type=int,
        help="Fetch exactly this many Pokémon from Dex #1 (overrides --generation).",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("assets/sprites"),
        help="Output root directory (default: assets/sprites).",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Re-download and overwrite sprites that already exist.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    limit = args.count if args.count is not None else GEN_LAST_DEX[args.generation]

    scope = f"first {limit}" if args.count is not None else f"Gen 1..{args.generation}"
    print(f"Fetching sprite list ({scope}, {limit} Pokémon) from {INDEX_URL} ...")
    slugs = get_slugs(limit)

    totals = {"saved": 0, "skipped": 0, "missing": 0}
    missing: list[str] = []
    for i, slug in enumerate(slugs, start=1):
        results = []
        for label, (subpath, ext) in VARIANTS.items():
            status = download_variant(
                slug, subpath, ext, args.out, overwrite=args.overwrite
            )
            totals[status] += 1
            results.append(f"{label}={status}")
            if status == "missing":
                missing.append(f"{slug} ({label})")
        print(f"[{i:>3}/{limit}] {slug:<14} " + "  ".join(results))

    print(
        "\nDone. "
        f"saved={totals['saved']} skipped={totals['skipped']} "
        f"missing={totals['missing']}  ->  {args.out}"
    )
    if missing:
        print("Missing variants:")
        for item in missing:
            print(f"  - {item}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
