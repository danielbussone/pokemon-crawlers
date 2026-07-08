#!/usr/bin/env python3
"""Download Gen 1 Pokémon sprites from PokémonDB (Gen 5 Black/White).

Fetches static PNG and animated GIF sprites for all 151 Kanto Pokémon from:
  https://img.pokemondb.net/sprites/black-white/normal/{slug}.png
  https://img.pokemondb.net/sprites/black-white/anim/normal/{slug}.gif

Output goes to godot/art/creatures/ using game-friendly ids (hyphens → underscores).
A manifest is written to data/sprites/gen1_manifest.json.

Usage:
    python tools/scrape_gen1_sprites.py
    python tools/scrape_gen1_sprites.py --dry-run
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "godot" / "art" / "creatures"
MANIFEST_PATH = ROOT / "data" / "sprites" / "gen1_manifest.json"
SPRITES_INDEX_URL = "https://pokemondb.net/sprites"
BASE_IMG_URL = "https://img.pokemondb.net/sprites/black-white"
USER_AGENT = "PokemonCrawlers-SpriteScraper/1.0 (personal project; local asset download)"
REQUEST_DELAY_S = 0.15


def fetch_text(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8", errors="replace")


def download_file(url: str, dest: Path, dry_run: bool) -> bool:
    if dry_run:
        print(f"  [dry-run] would download {url} -> {dest}")
        return True

    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()
    except urllib.error.HTTPError as exc:
        print(f"  FAIL {url}: HTTP {exc.code}", file=sys.stderr)
        return False

    dest.write_bytes(data)
    return True


def pokemondb_slug_to_game_id(slug: str) -> str:
    """Convert PokémonDB URL slug to this project's creature id convention."""
    return slug.replace("-", "_")


def parse_gen1_slugs(html: str) -> list[str]:
    links = re.findall(r'href="/sprites/([^"]+)"', html)
    gen1: list[str] = []
    for slug in links:
        if slug == "chikorita":
            break
        gen1.append(slug)
    return gen1


def scrape_gen1(*, dry_run: bool = False, delay: float = REQUEST_DELAY_S) -> dict:
    print(f"Fetching Gen 1 list from {SPRITES_INDEX_URL} ...")
    html = fetch_text(SPRITES_INDEX_URL)
    slugs = parse_gen1_slugs(html)
    if len(slugs) != 151:
        print(f"Warning: expected 151 Gen 1 Pokémon, got {len(slugs)}", file=sys.stderr)

    manifest = {
        "source": "https://pokemondb.net/sprites",
        "generation": 5,
        "game": "black-white",
        "variant": "normal",
        "count": len(slugs),
        "sprites": [],
    }

    ok_static = 0
    ok_anim = 0
    fail_static = 0
    fail_anim = 0

    for i, slug in enumerate(slugs, start=1):
        game_id = pokemondb_slug_to_game_id(slug)
        static_url = f"{BASE_IMG_URL}/normal/{slug}.png"
        anim_url = f"{BASE_IMG_URL}/anim/normal/{slug}.gif"
        static_path = OUTPUT_DIR / f"{game_id}.png"
        anim_path = OUTPUT_DIR / f"{game_id}.gif"

        print(f"[{i:03d}/151] {game_id} ({slug})")

        static_ok = download_file(static_url, static_path, dry_run)
        anim_ok = download_file(anim_url, anim_path, dry_run)

        if static_ok:
            ok_static += 1
        else:
            fail_static += 1
        if anim_ok:
            ok_anim += 1
        else:
            fail_anim += 1

        entry = {
            "dex": i,
            "slug": slug,
            "id": game_id,
            "static": {
                "url": static_url,
                "path": str(static_path.relative_to(ROOT)),
                "ok": static_ok,
            },
            "animated": {
                "url": anim_url,
                "path": str(anim_path.relative_to(ROOT)),
                "ok": anim_ok,
            },
        }
        manifest["sprites"].append(entry)

        if delay > 0 and not dry_run:
            time.sleep(delay)

    manifest["summary"] = {
        "static_ok": ok_static,
        "static_fail": fail_static,
        "animated_ok": ok_anim,
        "animated_fail": fail_anim,
    }

    if not dry_run:
        MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(f"\nManifest written to {MANIFEST_PATH}")

    print(
        f"\nDone: {ok_static}/{len(slugs)} static, {ok_anim}/{len(slugs)} animated"
        + (f" ({fail_static} static / {fail_anim} animated failures)" if fail_static or fail_anim else "")
    )
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="Print URLs without downloading")
    parser.add_argument(
        "--delay",
        type=float,
        default=REQUEST_DELAY_S,
        help=f"Seconds between requests (default: {REQUEST_DELAY_S})",
    )
    args = parser.parse_args()

    manifest = scrape_gen1(dry_run=args.dry_run, delay=args.delay)
    summary = manifest.get("summary", {})
    if summary.get("static_fail") or summary.get("animated_fail"):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
