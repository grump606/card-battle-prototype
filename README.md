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

In `combat/starter_content.gd`, append to `deck()`:

```gdscript
cards.append(CardData.make(&"my_card", "My Card", 1, [
	CardEffect.make(CardEffect.Kind.DAMAGE, 4),
	CardEffect.make(CardEffect.Kind.BLOCK, 2),
]))
```

Effect kinds: `DAMAGE`, `BLOCK`, `DRAW`. A card may have several effects; cost 0 is allowed.

## Add an enemy

Add a static function to `combat/starter_content.gd` returning `EnemyData.make(name, max_hp, intents)`, where `intents` is an `Array[CardEffect]` the enemy cycles through one per turn (empty means it does nothing). Then include it in an encounter such as `early_encounter()`. An encounter must have 1 to `Combat.MAX_ENEMIES` (3) enemies.

Add a test in `tests/run_tests.gd` (a `_test_*` function plus a call in `_initialize`) for any new rule.

## Card target modes and statuses

A card's `target_mode` (in its `.tres`) is `0` single enemy (default, the selected enemy), `1` all enemies, or `2` self. Block- and draw-only cards should use self so they never need or name a target. An `EXPOSE` effect (`kind = 3`, `amount` = turns) makes the target take 1.5x damage, rounded down, applied before block.

## Balance simulation

`godot --headless --path . -s res://tools/balance_sim.gd -- --fights 500 --seed 1` plays N seeded fights (default 500, seed 1) for each early encounter size (1 to 3 enemies) with a deterministic greedy policy (0-cost cards first, block when enemy intents out-damage current block, otherwise damage the lowest-HP enemy). It prints win rate, average turns, average player HP left on wins and stalls (fights over 50 turns) per size. Output is identical for identical arguments; invalid arguments print usage and exit with code 2. The sim's player HP constant is copied from `battle.gd`, so keep them in sync. It uses `extended_deck()` and `varied_encounter()` (the same content as the game): a lone enemy can be any type, a pair is one big plus one small enemy (35% of pairs) or two small ones, and a trio is all small enemies. Tuning target (untuned guess, adjust freely): roughly 90-97% wins with 1 enemy, 80-90% with 2, 60-75% with 3.
