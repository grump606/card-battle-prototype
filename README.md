# Card Battle Prototype

A small turn-based card battler (afterlife-escape theme) built with Godot 4.7, GDScript, targeting Windows PC. The player fights 1 to 3 enemies with a deck of cards; enemies repeat a fixed cycle of intents.

## Layout

- `combat/` - rules only: no nodes, no scenes. `Combat` drives turns and emits signals; `CardPiles`, `Combatant`, `EnemyUnit`, `CardData`, `CardEffect`, `EnemyData` are the building blocks. `starter_content.gd` holds placeholder cards and enemies.
- `battle.gd` / `battle.tscn` - the combat UI. It observes `Combat` signals and calls `play_card` / `end_player_turn`; it contains no rules. Run on its own (F6 on `battle.tscn`) it plays a random fight with a New Fight button; embedded by the run screen it shows a fight the run built and ends with Continue.
- `run/run_state.gd` - the run layer, rules only: a fixed 12-stop line (story, combat, rest, vendor, and a Conductor boss fight at the end) with the player's HP and deck carried from stop to stop. Wins pay gold and offer a pick-one-of-three card reward (the boss pays no gold and offers none); rests heal 24; a defeat ends the run; passing the last stop escapes. The run uses 51 max HP (combat on its own, and the combat sim, use 40). `run/vendor.gd` is the vendor visit (3 cards for sale, remove a card, heal; placeholder prices), `run/story_beat.gd` / `run/story_content.gd` + `data/story/` are the cutscene beats (four are written; the line uses "boarding", "conductor" and "last light", and "empty platform" is a spare beat for a future stop). New stop kinds are new `StopType` values plus one branch in `run.gd`.
- `run.gd` / `run.tscn` - the run screen (main scene, F5): a thin view over `RunState` that embeds `battle.tscn` for combat stops and shows small panels for story beats, rewards, the vendor, rests and the end card.
- `tests/run_tests.gd` - headless rules tests (also runs `content_tests.gd` and `run_state_tests.gd`). `tests/smoke_main.gd` - loads and instantiates the main scene.
- `tests/ui_battle_test.gd` / `tests/ui_flow_test.gd` - headless UI tests: the battle screen (pile counts, tooltips, damage preview, keys) and whole runs driven through the real `run.tscn` buttons.
- `scripts/check.ps1` - full validation: import, rules tests, smoke load, both UI tests. Each step has a timeout (300 s, `CHECK_STEP_TIMEOUT_MS` to change) so a hang fails instead of blocking.

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

Cards are `.tres` resources under `data/cards/` (copy an existing one, e.g. `shove.tres`, and keep its script `ext_resource` lines). Set `id`, `display_name`, `cost` (0 is allowed), `effects`, and `target_mode` (see below). Effect `kind` values: `0` DAMAGE, `1` BLOCK, `2` DRAW, `3` EXPOSE; a card may have several effects, applied in order. Then in `combat/starter_content.gd` add a path constant and put the card in `deck()` / `extended_deck()`. Open the project once (or run `--import`) so Godot registers the new file. Two things to know: the **card reward pool and the vendor stock are built only from `extended_deck()`**, so a card must be in that deck to ever be offered (and every offered card is therefore also a starting-deck card); and `tests/content_tests.gd` deliberately pins the exact extended-deck composition and size, so update its `want` table (and `EXTENDED_DECK_SIZE`) when you add or remove a copy. Price is set by `Vendor.card_value` / `card_price`.

## Add an enemy

Enemies are `.tres` resources under `data/enemies/` (copy e.g. `lost_shade.tres`): `display_name`, `max_hp`, and `intents`, a list of effects the enemy cycles through one per turn (empty means it does nothing; DAMAGE and BLOCK act on the enemy's turn, EXPOSE exposes the player). In `combat/starter_content.gd` add a path constant and include it in `ALL_ENEMY_PATHS` and, if it should appear in packs, `SMALL_ENEMY_PATHS`. An encounter must have 1 to `Combat.MAX_ENEMIES` (3) enemies. `tests/content_tests.gd` pins the enemy pool size and the list of enemies that must appear, so update those when you add one. The Hollow Colossus is deliberately solo-only (see `varied_encounter`).

Add a test in `tests/run_tests.gd` (a `_test_*` function plus a call in `_initialize`) for any new rule, and check the sim (below) for balance.

## Card target modes and statuses

A card's `target_mode` (in its `.tres`) is `0` single enemy (default, the selected enemy), `1` all enemies, or `2` self. Block- and draw-only cards should use self so they never need or name a target. An `EXPOSE` effect (`kind = 3`, `amount` = turns) makes the target take 1.5x damage, rounded down, applied before block.

## Balance simulation

`godot --headless --path . -s res://tools/balance_sim.gd -- --fights 500 --seed 1` plays N seeded fights (default 500, seed 1) for each early encounter size (1 to 3 enemies) with a deterministic greedy policy (0-cost cards first, block when enemy intents out-damage current block, otherwise damage the lowest-HP enemy). It prints win rate, average turns, average player HP left on wins and stalls (fights over 50 turns) per size. Output is identical for identical arguments; invalid arguments print usage and exit with code 2. The sim's player HP constant is copied from `battle.gd`, so keep them in sync. It uses `extended_deck()` and `varied_encounter()` (the same content as the game): a lone enemy can be any type, a pair is the Gate Warden plus one small enemy (15% of pairs) or two small ones, and a trio is wisps and whisperers only. The Hollow Colossus only appears alone (it was unwinnable next to a second enemy in the sim). Tuning target (untuned guess, adjust freely): roughly 90-97% wins with 1 enemy, 80-90% with 2, 60-75% with 3.

The sim's policy plays an Expose card first when a damage card in hand can benefit, and prints a second table ("Win rate by enemy type": fights in which each enemy appeared, per encounter size) to show which enemy is over- or under-tuned. `--help` prints usage.

## Run-layer contract

How a later run layer (map, vendors, rest sites, cutscenes) drives combat without changing it: `docs/RUN_INTEGRATION.md`. Throwaway demo: `godot --headless --path . -s res://tools/run_stub.gd -- --seed 1`.

## Run simulation

`tools/run_sim.gd` plays many whole seeded runs through `RunState` and reports how winnable a run is: escape rate, where runs die (by stop index and description), average HP on arrival at each stop, and final HP and deck size on escapes. Run it with `godot --headless --path . -s res://tools/run_sim.gd -- --runs 300 --seed 1` (`--help` for usage; bad arguments exit 2; output is deterministic for equal arguments). Fights use the same Expose-aware greedy policy as `balance_sim.gd`, shared in `tools/sim_policy.gd`. After each win it takes the offered card that best fills what the deck lacks (damage or block) and never skips; at the vendor it heals if at least half a heal is missing, then buys the best-scoring cards it can afford and leaves. A fight past 50 turns is abandoned and counted as a stall. The policy is simple, so treat the escape rate as a lower bound for a human; the current line (51 HP, rest +24, Conductor boss) escapes about 48% of runs, and the boss kills roughly 30% of the runs that reach it.
