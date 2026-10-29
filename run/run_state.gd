class_name RunState
extends RefCounted
## One escape attempt: a fixed line of stops the player passes through, carrying
## HP and the deck from stop to stop. Pure logic with no nodes, so the run screen
## is only a view over it. Combat itself is untouched: a combat stop just builds
## a Combat from this state (see docs/RUN_INTEGRATION.md).
##
## New stop kinds (vendor, cutscene) become new StopType values plus one branch
## in the screen; the stop line and the persistent player/deck stay as they are.

enum StopType { COMBAT, REST, STORY, VENDOR }

const START_HP := 50
const REST_HEAL := 24
const REWARD_CHOICES := 3

## One stop on the line. `enemy_count` only matters for COMBAT stops and
## `beat_index` (into StoryContent) only for STORY stops.
class Stop:
	var type: StopType
	var enemy_count: int
	var beat_index: int

	func _init(stop_type: StopType, count: int = 0, beat: int = 0) -> void:
		type = stop_type
		enemy_count = count
		beat_index = beat

	func describe() -> String:
		match type:
			StopType.COMBAT:
				return "Combat (%d enem%s)" % [enemy_count, "y" if enemy_count == 1 else "ies"]
			StopType.REST:
				return "Rest"
			StopType.STORY:
				return "Story"
			StopType.VENDOR:
				return "Vendor"
		return "?"

var player: Combatant
var deck: Array[CardData]
var stops: Array[Stop] = []
var stop_index: int = 0
## True once the line is finished, by reaching the end or by losing a fight.
var finished: bool = false
## Only meaningful when `finished`: true if the player reached the last stop alive.
var escaped: bool = false
## Earned by winning fights (Vendor.gold_for_win), spent at VENDOR stops. The
## vendor tracks gold during a visit; the purchase methods below copy it back so
## this is always current.
var gold: int = 0

var _vendor: Vendor = null
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


## Records how a fight ended. A defeat ends the run; a victory pays gold and
## offers a reward that must be taken or skipped before the line moves on.
func complete_combat(victory: bool) -> void:
	if not victory:
		finished = true
		escaped = false
		return
	var stop := current_stop()
	if stop != null and stop.type == StopType.COMBAT:
		gold += Vendor.gold_for_win(stop.enemy_count)
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


## The beat to show at a STORY stop, or null if not at one or it failed to load
## (logged); the stop can still be passed with read_story().
func current_beat() -> StoryBeat:
	var stop := current_stop()
	if stop == null or stop.type != StopType.STORY:
		return null
	return StoryContent.beat(stop.beat_index)


## Moves past a STORY stop. Returns false if not at one.
func read_story() -> bool:
	var stop := current_stop()
	if stop == null or stop.type != StopType.STORY:
		return false
	_advance()
	return true


## The vendor for the current VENDOR stop (created on first call, so asking again
## does not re-roll the stock), or null if not at a vendor stop.
func vendor() -> Vendor:
	var stop := current_stop()
	if stop == null or stop.type != StopType.VENDOR:
		return null
	if _vendor == null:
		_vendor = Vendor.new(deck, _rng, gold)
	return _vendor


## Vendor purchases: each forwards to the Vendor, then copies its gold back. A
## failed purchase changes nothing; when not at a vendor stop they fail.
func vendor_buy_card(offer_index: int) -> Vendor.Result:
	var v := vendor()
	if v == null:
		return Vendor.Result.fail("not at a vendor")
	var result := v.buy_card(offer_index)
	gold = v.gold
	return result


func vendor_remove_card(deck_index: int) -> Vendor.Result:
	var v := vendor()
	if v == null:
		return Vendor.Result.fail("not at a vendor")
	var result := v.remove_card(deck_index)
	gold = v.gold
	return result


func vendor_buy_heal() -> Vendor.Result:
	var v := vendor()
	if v == null:
		return Vendor.Result.fail("not at a vendor")
	var result := v.buy_heal(player)
	gold = v.gold
	return result


## Leaves the vendor and moves on. False if not at a vendor stop.
func leave_vendor() -> bool:
	if vendor() == null:
		return false
	_vendor = null
	_advance()
	return true


func _advance() -> void:
	stop_index += 1
	if stop_index >= stops.size():
		finished = true
		escaped = true


## The placeholder train line: boarding, small fights early, a vendor before the
## first trio, rests between, a last-light beat, then a final trio.
func _default_line() -> Array[Stop]:
	return [
		Stop.new(StopType.STORY, 0, 0),
		Stop.new(StopType.COMBAT, 1),
		Stop.new(StopType.COMBAT, 2),
		Stop.new(StopType.REST),
		Stop.new(StopType.COMBAT, 2),
		Stop.new(StopType.VENDOR),
		Stop.new(StopType.COMBAT, 3),
		Stop.new(StopType.REST),
		Stop.new(StopType.STORY, 0, 3),
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
