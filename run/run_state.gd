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

const REST_HEAL := 24
const REWARD_CHOICES := 3
## How many of a reward's choices come from the character's own cards (the rest are neutral).
const REWARD_CLASS_CHOICES := 2

## One stop on the line. `enemy_count` only matters for COMBAT stops and
## `beat_index` (into StoryContent) only for STORY stops. A COMBAT stop with
## `boss` set fights StarterContent.boss_encounter() instead of a random pack,
## and winning it ends the run with no gold and no card reward.
class Stop:
	var type: StopType
	var enemy_count: int
	var beat_index: int
	var boss: bool

	func _init(stop_type: StopType, count: int = 0, beat: int = 0, is_boss: bool = false) -> void:
		type = stop_type
		enemy_count = count
		beat_index = beat
		boss = is_boss

	func describe() -> String:
		match type:
			StopType.COMBAT:
				if boss:
					return "Boss"
				return "Combat (%d enem%s)" % [enemy_count, "y" if enemy_count == 1 else "ies"]
			StopType.REST:
				return "Rest"
			StopType.STORY:
				return "Story"
			StopType.VENDOR:
				return "Vendor"
		return "?"

## Who is playing: sets the starting HP and deck and which cards the run can offer.
var character: Character
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
var _active_combat: Combat = null
var _rng := RandomNumberGenerator.new()
var _reward_choices: Array[CardData] = []
var _reward_pending: bool = false


func _init(rng_seed: int = 0, character_id: StringName = StarterContent.DEFAULT_CHARACTER_ID) -> void:
	_rng.seed = rng_seed
	character = StarterContent.character(character_id)
	if character == null:
		# The cause is logged; an empty character keeps the run constructible, and its first
		# fight then fails cleanly because Combat rejects an empty deck.
		character = Character.new()
	player = Combatant.new(character.display_name, character.max_hp)
	deck.assign(character.starting_deck)
	stops = _default_line()


## The stop the player is at, or null once the run is finished.
func current_stop() -> Stop:
	return null if finished else stops[stop_index]


func reward_pending() -> bool:
	return _reward_pending


## True between stops: nothing is in flight (no fight, reward or vendor visit), so
## the run can be saved and restored exactly (see run/run_save.gd).
func at_stop_boundary() -> bool:
	return not finished and not _reward_pending and _vendor == null and _active_combat == null


## The run RNG's position, for saving. Restoring it makes the future identical.
func rng_state() -> int:
	return _rng.state


func restore_rng_state(state: int) -> void:
	_rng.state = state


## Builds the fight for the current COMBAT stop, or null (after logging why) if
## this is not a combat stop or the content failed to load. Asking again at the
## same stop abandons the previous fight (releasing its link to the player) and
## builds a new one, which re-rolls the encounter.
func start_combat() -> Combat:
	var stop := current_stop()
	if stop == null or stop.type != StopType.COMBAT or _reward_pending:
		push_error("RunState.start_combat: not at a fresh combat stop")
		return null
	if _active_combat != null:
		_active_combat.abandon()
		_active_combat = null
	var enemies := StarterContent.boss_encounter() if stop.boss else StarterContent.varied_encounter(stop.enemy_count, _rng)
	_active_combat = Combat.create(player, deck, enemies, _rng.randi())
	return _active_combat


## Records how the current fight ended. A defeat ends the run; a victory pays
## gold and offers a reward that must be taken or skipped before the line moves
## on. Beating the boss stop is the exception: it pays nothing (no later stop could
## spend it), offers no reward and ends the run as an escape. Only valid at a COMBAT stop that has no reward pending and is not finished
## (anything else is a caller bug: it is logged and changes nothing).
func complete_combat(victory: bool) -> void:
	var stop := current_stop()
	if finished or _reward_pending or stop == null or stop.type != StopType.COMBAT:
		push_error("RunState.complete_combat: not at a combat stop awaiting a result")
		return
	_active_combat = null
	if not victory:
		finished = true
		escaped = false
		return
	if stop.boss:
		# The boss ends the line: no gold (nothing left to spend it on), no card to pick.
		_advance()
		return
	gold += Vendor.gold_for_win(stop.enemy_count)
	_roll_rewards()
	_reward_pending = true


## Up to REWARD_CHOICES distinct cards to pick from, stable until the reward is
## taken or skipped. Rolled when the fight is won, so a seed plays out the same
## whether or not the reward screen is shown. Returns a copy.
func reward_choices() -> Array[CardData]:
	var copy: Array[CardData] = []
	copy.assign(_reward_choices)
	return copy


## Adds `card` to the deck (null skips the reward) and moves to the next stop.
## Rejects a card that was not offered, or any call once the run is finished.
func resolve_reward(card: CardData) -> bool:
	if finished or not _reward_pending:
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
	return StoryContent.beat(stop.beat_index, character.id)


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
		_vendor = Vendor.new(deck, _rng, gold, StarterContent.reward_pool(character.id))
	return _vendor


## Vendor purchases: RunState owns gold, so each pushes the run's gold into the
## Vendor before acting and copies it back after. A failed purchase changes
## nothing; when not at a vendor stop they fail.
func vendor_buy_card(offer_index: int) -> Vendor.Result:
	var v := _vendor_with_run_gold()
	if v == null:
		return Vendor.Result.fail("not at a vendor")
	var result := v.buy_card(offer_index)
	gold = v.gold
	return result


func vendor_remove_card(deck_index: int) -> Vendor.Result:
	var v := _vendor_with_run_gold()
	if v == null:
		return Vendor.Result.fail("not at a vendor")
	var result := v.remove_card(deck_index)
	gold = v.gold
	return result


func vendor_buy_heal() -> Vendor.Result:
	var v := _vendor_with_run_gold()
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


func _vendor_with_run_gold() -> Vendor:
	var v := vendor()
	if v != null:
		v.gold = gold
	return v


func _advance() -> void:
	_vendor = null
	stop_index += 1
	if stop_index >= stops.size():
		finished = true
		escaped = true


## The placeholder train line: boarding, small fights early with the Conductor
## glimpsed mid-run, a vendor before the first trio, rests between, a second
## vendor and the last-light beat, then the Conductor as boss.
func _default_line() -> Array[Stop]:
	return [
		Stop.new(StopType.STORY, 0, 0),
		Stop.new(StopType.COMBAT, 1),
		Stop.new(StopType.COMBAT, 2),
		Stop.new(StopType.REST),
		Stop.new(StopType.STORY, 0, 1),
		Stop.new(StopType.COMBAT, 2),
		Stop.new(StopType.VENDOR),
		Stop.new(StopType.COMBAT, 3),
		Stop.new(StopType.REST),
		Stop.new(StopType.VENDOR),
		Stop.new(StopType.STORY, 0, 3),
		Stop.new(StopType.COMBAT, 1, 0, true),
	]


func _roll_rewards() -> void:
	# Mostly the character's own cards, with a neutral one mixed in: up to REWARD_CLASS_CHOICES
	# class cards, then neutral cards to fill, then any class cards left over.
	var class_cards: Array[CardData] = []
	var neutral_cards: Array[CardData] = []
	for card in _distinct_cards(StarterContent.reward_pool(character.id)):
		if card.character == &"":
			neutral_cards.append(card)
		else:
			class_cards.append(card)
	_shuffle(class_cards)
	_shuffle(neutral_cards)
	var picks: Array[CardData] = []
	picks.append_array(class_cards.slice(0, REWARD_CLASS_CHOICES))
	picks.append_array(neutral_cards.slice(0, REWARD_CHOICES - picks.size()))
	picks.append_array(class_cards.slice(REWARD_CLASS_CHOICES, REWARD_CLASS_CHOICES + REWARD_CHOICES - picks.size()))
	_reward_choices.assign(picks)


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
