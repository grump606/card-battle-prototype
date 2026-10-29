class_name RunState
extends RefCounted
## One escape attempt: a fixed line of stops the player passes through, carrying
## HP and the deck from stop to stop. Pure logic with no nodes, so the run screen
## is only a view over it. Combat itself is untouched: a combat stop just builds
## a Combat from this state (see docs/RUN_INTEGRATION.md).
##
## New stop kinds (vendor, cutscene) become new StopType values plus one branch
## in the screen; the stop line and the persistent player/deck stay as they are.

enum StopType { COMBAT, REST }

const START_HP := 40
const REST_HEAL := 14
const REWARD_CHOICES := 3

## One stop on the line. `enemy_count` only matters for COMBAT stops.
class Stop:
	var type: StopType
	var enemy_count: int

	func _init(stop_type: StopType, count: int = 0) -> void:
		type = stop_type
		enemy_count = count

	func describe() -> String:
		match type:
			StopType.COMBAT:
				return "Combat (%d enem%s)" % [enemy_count, "y" if enemy_count == 1 else "ies"]
			StopType.REST:
				return "Rest"
		return "?"

var player: Combatant
var deck: Array[CardData]
var stops: Array[Stop] = []
var stop_index: int = 0
## True once the line is finished, by reaching the end or by losing a fight.
var finished: bool = false
## Only meaningful when `finished`: true if the player reached the last stop alive.
var escaped: bool = false

var _rng := RandomNumberGenerator.new()
var _reward_choices: Array[CardData] = []
var _reward_pending: bool = false


func _init(rng_seed: int = 0) -> void:
	_rng.seed = rng_seed
	player = Combatant.new("Wanderer", START_HP)
	deck = StarterContent.extended_deck()
	stops = _default_line()


## The stop the player is at, or null once the run is finished.
func current_stop() -> Stop:
	return null if finished else stops[stop_index]


func reward_pending() -> bool:
	return _reward_pending


## Builds the fight for the current COMBAT stop, or null (after logging why) if
## this is not a combat stop or the content failed to load.
func start_combat() -> Combat:
	var stop := current_stop()
	if stop == null or stop.type != StopType.COMBAT or _reward_pending:
		push_error("RunState.start_combat: not at a fresh combat stop")
		return null
	var enemies := StarterContent.varied_encounter(stop.enemy_count, _rng)
	return Combat.create(player, deck, enemies, _rng.randi())


## Records how a fight ended. A defeat ends the run; a victory offers a reward
## that must be taken or skipped before the line moves on.
func complete_combat(victory: bool) -> void:
	if not victory:
		finished = true
		escaped = false
		return
	_reward_pending = true


## Up to REWARD_CHOICES distinct cards to pick from, stable until the reward is
## taken or skipped (asking again does not re-roll).
func reward_choices() -> Array[CardData]:
	if _reward_pending and _reward_choices.is_empty():
		var pool := _distinct_cards(StarterContent.extended_deck())
		_shuffle(pool)
		_reward_choices.assign(pool.slice(0, REWARD_CHOICES))
	return _reward_choices


## Adds `card` to the deck (null skips the reward) and moves to the next stop.
## Rejects a card that was not offered.
func resolve_reward(card: CardData) -> bool:
	if not _reward_pending:
		return false
	if card != null:
		if not reward_choices().has(card):
			push_error("RunState.resolve_reward: card was not offered")
			return false
		deck.append(card)
	_reward_pending = false
	_reward_choices = []
	_advance()
	return true


## Heals at a REST stop and moves on. Returns HP restored, or -1 if not at a rest stop.
func rest() -> int:
	var stop := current_stop()
	if stop == null or stop.type != StopType.REST:
		return -1
	var restored := player.heal(REST_HEAL)
	_advance()
	return restored


func _advance() -> void:
	stop_index += 1
	if stop_index >= stops.size():
		finished = true
		escaped = true


## The placeholder train line: small fights early, rests between, a trio last.
func _default_line() -> Array[Stop]:
	return [
		Stop.new(StopType.COMBAT, 1),
		Stop.new(StopType.COMBAT, 2),
		Stop.new(StopType.REST),
		Stop.new(StopType.COMBAT, 2),
		Stop.new(StopType.COMBAT, 3),
		Stop.new(StopType.REST),
		Stop.new(StopType.COMBAT, 3),
	]


func _distinct_cards(cards: Array[CardData]) -> Array[CardData]:
	var seen := {}
	var distinct: Array[CardData] = []
	for card in cards:
		if not seen.has(card.id):
			seen[card.id] = true
			distinct.append(card)
	return distinct


## Fisher-Yates with the run RNG, so a seeded run offers the same rewards.
func _shuffle(cards: Array[CardData]) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
