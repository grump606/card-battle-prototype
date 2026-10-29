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
