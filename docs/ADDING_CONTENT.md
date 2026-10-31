# Adding content

Content is data (`.tres` under `data/`) plus explicit, ordered registries in `combat/starter_content.gd`. Order matters: shuffles and encounter draws depend on list order, so seeded sim output changes if a list is reordered or a new entry is inserted in the middle. Append new entries at the end unless you want to change the balance on purpose. `tests/content_tests.gd` scans `data/` and fails when a file is missing from its registry, a registry path does not load, or an enemy has no portrait entry.

## A card
1. Add `data/cards/<name>.tres` (copy a similar one). Set `character` to a class id, or leave it empty for the neutral pool.
2. Add a `<NAME>_PATH` constant and append it to `ALL_CARD_PATHS` in `starter_content.gd`.
3. Optionally add it to a character's `starting_deck`.

## A relic
1. Add `data/relics/<name>.tres` with a unique `id` (and `character` if class-bound).
2. Append its path to `RELIC_PATHS`. Implement the effect where the hook lives (see `docs/RELICS_DESIGN.md`), and add a badge in the relic art if it needs a new one.

## An enemy
1. Add `data/enemies/<name>.tres`.
2. Add a `<NAME>_PATH` constant. Regular enemy: append to `ALL_ENEMY_PATHS`, then put it in `SMALL_ENEMY_PATHS` (joins pairs and trios; also add to `TRIO_EXCLUDED_PATHS` to keep it out of trios), `PAIR_BIG_ENEMY_PATHS` or `SOLO_ONLY_ENEMY_PATHS`, and optionally `TIER1_SINGLE_PATHS`. Boss: add to `BOSS_ENEMY_PATHS` and give it its own encounter function.
3. Add its display name to `EnemyView.ART_KEYS` (`run/enemy_view.gd`), with an `ART_COLORS` entry and a drawing for the key. Art is keyed by display name, so display names must be unique.

## A character
1. Add `data/characters/<id>.tres` (`id` must equal the file name and registry key) with a starting deck.
2. Add it to `CHARACTER_PATHS` (the order is the select screen order).
3. Add class cards and relics tagged with the id, per-character story beats under `data/story/<id>/`, and a palette in the card and select art.

Then run `powershell -ExecutionPolicy Bypass -File scripts/check.ps1`.
