# Card Battle Prototype

A small turn-based card battler (afterlife-escape theme) built with Godot 4.7, GDScript, targeting Windows PC. The player fights 1 to 3 enemies with a deck of cards; enemies repeat a fixed cycle of intents.

## Layout

- `combat/` - rules only: no nodes, no scenes. `Combat` drives turns and emits signals; `CardPiles`, `Combatant`, `EnemyUnit`, `CardData`, `CardEffect`, `EnemyData` are the building blocks. `starter_content.gd` holds placeholder cards and enemies.
- `battle.gd` / `battle.tscn` - the UI (main scene). It observes `Combat` signals and calls `play_card` / `end_player_turn`; it contains no rules.
- `tests/run_tests.gd` - headless rules tests. `tests/smoke_main.gd` - loads and instantiates the main scene.
- `scripts/check.ps1` - full validation.

## Run

Open the project in Godot 4.7 and press F5, or:

```powershell
& $env:GODOT --path .
```

## Test

Full validation (import, tests, main-scene smoke load; nonzero exit on any failure):

```powershell
$env:GODOT = 'path\to\Godot_v4.7.2-stable_win64_console.exe'   # optional
powershell -File scripts\check.ps1
```

If `GODOT` is unset the script uses `Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` in the repo root.

Tests only:

```powershell
& $env:GODOT --headless --path . -s res://tests/run_tests.gd
```

Expect `FAILURES: 0`.

## Add a card

Cards are `.tres` resources under `data/cards/` (copy an existing one, e.g. `shove.tres`, and keep its script `ext_resource` lines). Set `id`, `display_name`, `cost` (0 is allowed), `effects`, and `target_mode` (see below). Effect `kind` values: `0` DAMAGE, `1` BLOCK, `2` DRAW, `3` EXPOSE; a card may have several effects, applied in order. Then in `combat/starter_content.gd` add a path constant and put the card in `deck()` / `extended_deck()`. Open the project once (or run `--import`) so Godot registers the new file.

## Add an enemy

Enemies are `.tres` resources under `data/enemies/` (copy e.g. `lost_shade.tres`): `display_name`, `max_hp`, and `intents`, a list of effects the enemy cycles through one per turn (empty means it does nothing; DAMAGE and BLOCK act on the enemy's turn, EXPOSE exposes the player). In `combat/starter_content.gd` add a path constant and include it in `ALL_ENEMY_PATHS` and, if it should appear in packs, `SMALL_ENEMY_PATHS`. An encounter must have 1 to `Combat.MAX_ENEMIES` (3) enemies.

Add a test in `tests/run_tests.gd` (a `_test_*` function plus a call in `_initialize`) for any new rule, and check the sim (below) for balance.

## Card target modes and statuses

A card's `target_mode` (in its `.tres`) is `0` single enemy (default, the selected enemy), `1` all enemies, or `2` self. Block- and draw-only cards should use self so they never need or name a target. An `EXPOSE` effect (`kind = 3`, `amount` = turns) makes the target take 1.5x damage, rounded down, applied before block.

## Balance simulation

`godot --headless --path . -s res://tools/balance_sim.gd -- --fights 500 --seed 1` plays N seeded fights (default 500, seed 1) for each early encounter size (1 to 3 enemies) with a deterministic greedy policy (0-cost cards first, block when enemy intents out-damage current block, otherwise damage the lowest-HP enemy). It prints win rate, average turns, average player HP left on wins and stalls (fights over 50 turns) per size. Output is identical for identical arguments; invalid arguments print usage and exit with code 2. The sim's player HP constant is copied from `battle.gd`, so keep them in sync. It uses `extended_deck()` and `varied_encounter()` (the same content as the game): a lone enemy can be any type, a pair is the Gate Warden plus one small enemy (35% of pairs) or two small ones, and a trio is all small enemies. The Hollow Colossus only appears alone (it was unwinnable next to a second enemy in the sim). Tuning target (untuned guess, adjust freely): roughly 90-97% wins with 1 enemy, 80-90% with 2, 60-75% with 3.

The sim's policy plays an Expose card first when a damage card in hand can benefit, and prints a second table ("Win rate by enemy type": fights in which each enemy appeared, per encounter size) to show which enemy is over- or under-tuned. `--help` prints usage.

## Run-layer contract

How a later run layer (map, vendors, rest sites, cutscenes) drives combat without changing it: `docs/RUN_INTEGRATION.md`. Throwaway demo: `godot --headless --path . -s res://tools/run_stub.gd -- --seed 1`.
