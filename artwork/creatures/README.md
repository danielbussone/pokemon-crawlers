# Pokémon sprites

Sprite assets for future levels, scraped from [pokemondb.net](https://pokemondb.net/sprites).

Preference: **Generation 5 Black/White** art (static + animated).

## Layout

```
artwork/creatures/
├── black-white/normal/<slug>.png        # static sprites (Gen 5 B/W)
└── black-white/anim/normal/<slug>.gif   # animated sprites (Gen 5 B/W)
```

`<slug>` is the pokemondb name slug (e.g. `bulbasaur`, `nidoran-f`, `nidoran-m`,
`mr-mime`, `farfetchd`). Files are in National Dex order by slug.

Current coverage: **all 151 Generation 1 Pokémon** (Bulbasaur #1 → Mew #151),
2 files each (static PNG + animated GIF).

## Regenerating / extending

Use the stdlib-only scraper. It is idempotent (skips existing files):

```bash
python scripts/scrape_sprites.py                 # all Gen 1 (default)
python scripts/scrape_sprites.py --generation 2  # cumulative through Gen 2
python scripts/scrape_sprites.py --count 9       # just the first 9 (starters)
python scripts/scrape_sprites.py --overwrite     # force re-download
```

Sprites are sourced from `https://img.pokemondb.net/sprites/black-white/...`.
See pokemondb.net for their usage terms.
