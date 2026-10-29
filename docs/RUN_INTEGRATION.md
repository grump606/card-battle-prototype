# Run-layer integration contract

How a future run layer (map, vendors, rest sites, cutscenes) drives `combat/` without changing it. `tools/run_stub.gd` is a throwaway run layer that exercises exactly this contract.

## Starting a fight

```gdscript
var combat := Combat.new(player, deck, enemy_datas, rng_seed)
combat.combat_ended.connect(on_ended)   # connect BEFORE start()
combat.start()
```

- `player: Combatant` - the caller's persistent instance (see ownership).
- `deck: Array[CardData]` - the full deck for this fight. `CardPiles` copies the array, so later edits to the caller's array do not affect a running fight.
- `enemy_datas: Array[EnemyData]` - 1 to `Combat.MAX_ENEMIES` (3) entries. `StarterContent.varied_encounter(count, rng)` and `early_encounter(count)` build them; the loaders return smaller or empty arrays if a resource fails to load, so check `size()`.
- `rng_seed: int` - seeds shuffling only. Same seed + same deck + same inputs => same fight.

Drive it with `can_play(i)`, `play_card(i, target_index := -1)` and `end_player_turn()` while `phase == Combat.Phase.PLAYER_TURN`. `play_card` returns false (changing nothing) for illegal plays. `-1` targets the first living enemy; SELF and ALL_ENEMIES cards ignore the target.

## Ownership

| Caller owns | Combat owns |
|---|---|
| player `Combatant` (HP, max HP, name), carried between fights | `piles`, `energy`, `turn`, `phase` |
| the deck array (add/remove cards between fights) | `enemies` (`EnemyUnit`s built from the `EnemyData`) |
| the seed(s); derive each fight's seed from a run RNG | its internal RNG |

`CardData`, `CardEffect` and `EnemyData` are shared immutable definitions; never mutate them (copy with `duplicate(true)` first, as the loaders do for enemies).

## Outputs

- `combat_ended(victory: bool)` fires exactly once, when the last enemy dies (true) or the player's HP reaches 0 (false). It fires synchronously inside `play_card` or `end_player_turn`.
- After it fires, `combat.phase == Phase.ENDED` and `player.hp` is the HP to carry forward. Nothing is written back for you: the `Combatant` you passed in is already the result.
- `state_changed`, `card_played`, `enemy_acted` are for UIs; a run layer does not need them.

## Reset per fight

- Statuses: `Combat.new` calls `player.clear_statuses()`, so EXPOSED never leaks into the next fight.
- Block: cleared when the fight ends and again at the start of turn 1, so `player.block` is 0 between fights.
- Piles, hand, energy, turn count: new `Combat` => new `CardPiles`; every deck card starts in the draw pile, shuffled.
- Enemy HP, intents, statuses: fresh `EnemyUnit`s per fight.
- NOT reset: `player.hp` and `player.max_hp`.

## A run layer must NOT assume

- That a `Combat` can be restarted or reused: `start()` asserts `NOT_STARTED`. Make a new `Combat` per fight.
- That fights terminate: nothing caps turns (a defensive deck can stall). The caller needs its own turn cap (the stub uses 50 and counts it as a loss).
- That HP is healed for you: call `player.heal(amount)` (clamped to max HP, returns HP restored) for rest sites and vendors.
- That `combat_ended` can be read late: connect before `start()` (it is a signal, there is no `victory` property; afterwards use `player.is_dead()`).
- That `Combat.new` validates the enemy count in release builds: it only asserts. Use `Combat.create(...)`, which returns null (after logging) for fewer than 1 or more than `MAX_ENEMIES` enemies.
- That `Combat.new` leaves `player` untouched: it clears the player's statuses and, while the fight runs, links the player's `changed` signal to its own `state_changed`. The link is removed when the fight ends.

## API gaps

Fixed after the stub exposed them: `Combatant.heal()`, the player signal link now removed when a fight ends, block cleared at fight end, and `Combat.create()` for validated construction (bad enemy count or an already-dead player returns null). A fight you give up on (for example a stall cap) must be released with `combat.abandon()`, which removes the player link without emitting `combat_ended`; otherwise the link stays on the persistent player.

Still open (minor, caller-side workarounds below):

1. No outcome query besides the signal (`combat.victory` or similar). Capture it with a lambda before `start()`, as the stub does, or use `player.is_dead()` afterwards.
2. No turn cap or stall detection in `Combat`; every caller (the stub, `balance_sim.gd`) keeps its own. Proposal if it spreads: an optional `max_turns` that ends the fight as a defeat.

## How the stub demonstrates the seam

`godot --headless --path . -s res://tools/run_stub.gd -- --seed 1` builds one `Combatant` (40 HP) and the extended deck, then chains fights with 1, 2 and 3 enemies from `varied_encounter`, using one run RNG for encounters, per-fight combat seeds and rewards. Between fights it heals 8 (clamped) and appends one reward card (a random distinct card type from the extended deck). It stops on a loss or a stall. Per-fight lines show HP in and out, and the next fight's "HP before" equals the previous line's post-rest HP (compare consecutive lines of the output). After `start()` the stub asserts block is 0 and EXPOSED is 0, failing with exit 1 if state leaked. Same seed gives identical output; a bad `--seed` prints usage and exits 2.

## Status

`tools/run_stub.gd` was the throwaway stand-in for the run layer; the real one is now `run/run_state.gd` (see `run.gd` for how a screen drives it). The stub still runs and is kept as a minimal example of the public API.
