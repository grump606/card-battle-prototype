class_name StarterContent
extends RefCounted
## Placeholder content for the afterlife-escape theme. Card and enemy numbers
## live in .tres resources under res://data/ so they can be tuned in the editor;
## only the starting deck composition is defined here. Numbers are untuned.

const SHOVE_PATH := "res://data/cards/shove.tres"
const SLIP_PAST_PATH := "res://data/cards/slip_past.tres"
const GLIMPSE_EXIT_PATH := "res://data/cards/glimpse_exit.tres"
const WARDEN_PATH := "res://data/enemies/gate_warden.tres"
const LOST_SHADE_PATH := "res://data/enemies/lost_shade.tres"
const HEAVY_BLOW_PATH := "res://data/cards/heavy_blow.tres"
const BRACE_PATH := "res://data/cards/brace.tres"
const STEADY_BREATH_PATH := "res://data/cards/steady_breath.tres"
const SHOULDER_CHARGE_PATH := "res://data/cards/shoulder_charge.tres"
const MARK_THE_WEAK_PATH := "res://data/cards/mark_the_weak.tres"
const SWEEP_PATH := "res://data/cards/sweep.tres"
const CUTTING_WORD_PATH := "res://data/cards/cutting_word.tres"
const SECOND_WIND_PATH := "res://data/cards/second_wind.tres"
const HAMSTRING_PATH := "res://data/cards/hamstring.tres"
const IRON_RESOLVE_PATH := "res://data/cards/iron_resolve.tres"
const FLURRY_PATH := "res://data/cards/flurry.tres"
const GUARDED_STRIKE_PATH := "res://data/cards/guarded_strike.tres"
const HOLD_THE_LINE_PATH := "res://data/cards/hold_the_line.tres"
const BASH_PATH := "res://data/cards/bash.tres"
const DIG_IN_PATH := "res://data/cards/dig_in.tres"
const COLD_STEEL_PATH := "res://data/cards/cold_steel.tres"
const COUNTER_STANCE_PATH := "res://data/cards/counter_stance.tres"
const LAST_STAND_PATH := "res://data/cards/last_stand.tres"
const CINDER_HOUND_PATH := "res://data/enemies/cinder_hound.tres"
const MOURNING_CROW_PATH := "res://data/enemies/mourning_crow.tres"
const WISP_PATH := "res://data/enemies/skittering_wisp.tres"
const COLOSSUS_PATH := "res://data/enemies/hollow_colossus.tres"
const WHISPERER_PATH := "res://data/enemies/pale_whisperer.tres"
## The run's boss. Deliberately not in ALL_ENEMY_PATHS: it only appears via boss_encounter().
const CONDUCTOR_PATH := "res://data/enemies/the_conductor.tres"
const EXTENDED_DECK_SIZE := 14
## Every card, in a fixed order. A card's `character` tag says who may take it (empty = everyone).
const ALL_CARD_PATHS: Array[String] = [
	SHOVE_PATH, SLIP_PAST_PATH, GLIMPSE_EXIT_PATH, BRACE_PATH, FLURRY_PATH, SWEEP_PATH,
	HEAVY_BLOW_PATH, STEADY_BREATH_PATH, SHOULDER_CHARGE_PATH, IRON_RESOLVE_PATH, GUARDED_STRIKE_PATH,
	HOLD_THE_LINE_PATH, BASH_PATH, DIG_IN_PATH, COLD_STEEL_PATH, COUNTER_STANCE_PATH, LAST_STAND_PATH,
	MARK_THE_WEAK_PATH, CUTTING_WORD_PATH, HAMSTRING_PATH, SECOND_WIND_PATH,
]
## Playable characters, in the order a selection screen lists them.
const CHARACTER_PATHS := {
	&"deserter": "res://data/characters/deserter.tres",
	&"pickpocket": "res://data/characters/pickpocket.tres",
	&"medium": "res://data/characters/medium.tres",
}
const DEFAULT_CHARACTER_ID := &"deserter"
## The regular enemy types in a fixed order (the boss is separate, see CONDUCTOR_PATH): warden,
## lost shade, wisp, colossus, whisperer, cinder hound, mourning crow. The colossus is a solo-only
## elite (it was unwinnable next to a second enemy in the balance sim); the
## warden can share a pair; small enemies are what packs are made of.
const ALL_ENEMY_PATHS: Array[String] = [WARDEN_PATH, LOST_SHADE_PATH, WISP_PATH, COLOSSUS_PATH, WHISPERER_PATH, CINDER_HOUND_PATH, MOURNING_CROW_PATH]
const PAIR_BIG_ENEMY_PATHS: Array[String] = [WARDEN_PATH]
const SMALL_ENEMY_PATHS: Array[String] = [LOST_SHADE_PATH, WISP_PATH, WHISPERER_PATH, CINDER_HOUND_PATH, MOURNING_CROW_PATH]
## Chance that a two-enemy encounter is a big plus a small enemy rather than two small ones.
const BIG_PAIR_CHANCE := 0.15
## Trios leave out the Lost Shade (the sturdiest small enemy): three of them out-damaged the
## run mid-line, and the fragile wisps and whisperers keep a three-way fight winnable.
const TRIO_EXCLUDED_PATHS: Array[String] = [LOST_SHADE_PATH]


## Card definitions are immutable data, so deck slots of the same card share one instance.
## Returns an empty deck (and logs the cause) if any card resource fails to load.
static func deck() -> Array[CardData]:
	var cards: Array[CardData] = []
	var shove := _load_card(SHOVE_PATH)
	var slip_past := _load_card(SLIP_PAST_PATH)
	var glimpse_exit := _load_card(GLIMPSE_EXIT_PATH)
	if shove == null or slip_past == null or glimpse_exit == null:
		return cards
	for i in 5:
		cards.append(shove)
	for i in 4:
		cards.append(slip_past)
	cards.append(glimpse_exit)
	return cards


## Balance-testing deck of EXTENDED_DECK_SIZE (14) cards: 3 Shove, 2 Slip Past,
## 1 Glimpse the Exit, 1 Heavy Blow, 1 Brace, 1 Steady Breath, 1 Shoulder Charge,
## 1 Mark the Weak, 1 Sweep, 1 Cutting Word, 1 Second Wind.
## Returns an empty deck (and logs the cause) if any card resource fails to load.
static func extended_deck() -> Array[CardData]:
	var cards: Array[CardData] = []
	var plan: Array = [
		[SHOVE_PATH, 3], [SLIP_PAST_PATH, 2], [GLIMPSE_EXIT_PATH, 1],
		[HEAVY_BLOW_PATH, 1], [BRACE_PATH, 1], [STEADY_BREATH_PATH, 1], [SHOULDER_CHARGE_PATH, 1],
		[MARK_THE_WEAK_PATH, 1], [SWEEP_PATH, 1], [CUTTING_WORD_PATH, 1], [SECOND_WIND_PATH, 1],
	]
	for entry in plan:
		var card := _load_card(entry[0] as String)
		if card == null:
			var empty: Array[CardData] = []
			return empty
		for i in (entry[1] as int):
			cards.append(card)
	return cards


## Every card that loads, in ALL_CARD_PATHS order. Empty (cause logged) if any fails to load.
static func all_cards() -> Array[CardData]:
	var cards: Array[CardData] = []
	for path in ALL_CARD_PATHS:
		var card := _load_card(path)
		if card == null:
			var empty: Array[CardData] = []
			return empty
		cards.append(card)
	return cards


## The distinct cards a character can be offered as rewards or sell at a vendor: every neutral
## card plus the cards tagged for `character_id`. Empty (cause logged) if any card fails to load.
static func reward_pool(character_id: StringName) -> Array[CardData]:
	var pool: Array[CardData] = []
	for card in all_cards():
		if card.character == &"" or card.character == character_id:
			pool.append(card)
	return pool


static func character_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in CHARACTER_PATHS:
		ids.append(id)
	return ids


## The character with this id, or null (cause logged) for an unknown id or a resource that fails to load.
static func character(character_id: StringName) -> Character:
	if not CHARACTER_PATHS.has(character_id):
		push_error("StarterContent.character: unknown character '%s'" % character_id)
		return null
	var path: String = CHARACTER_PATHS[character_id]
	var loaded: Character = null
	if ResourceLoader.exists(path):
		loaded = load(path) as Character
	if loaded == null:
		push_error("StarterContent: missing or non-Character resource: %s" % path)
	return loaded


static func warden() -> EnemyData:
	return _load_enemy(WARDEN_PATH)


static func lost_shade() -> EnemyData:
	return _load_enemy(LOST_SHADE_PATH)


## An early-run encounter with `enemy_count` enemies (clamped to 1..MAX_ENEMIES).
## Enemies whose resource fails to load are left out (the cause is logged), so
## the result can be empty; Combat requires at least one enemy.
static func early_encounter(enemy_count: int) -> Array[EnemyData]:
	var count := clampi(enemy_count, 1, Combat.MAX_ENEMIES)
	var enemies: Array[EnemyData] = []
	for i in count:
		var enemy := warden() if count == 1 else lost_shade()
		if enemy != null:
			enemies.append(enemy)
	return enemies


## All enemy types in a fixed order: warden, lost shade, wisp, colossus, whisperer, cinder hound, mourning crow.
## Enemies that fail to load are left out (the cause is logged).
static func enemy_pool() -> Array[EnemyData]:
	var pool: Array[EnemyData] = []
	for path in ALL_ENEMY_PATHS:
		var enemy := _load_enemy(path)
		if enemy != null:
			pool.append(enemy)
	return pool


## An encounter of `enemy_count` (clamped to 1..MAX_ENEMIES) enemies, chosen
## with `rng` so a seeded rng reproduces it. Composition keeps danger roughly
## level as the count grows: a lone enemy can be any type, a pair is either the
## warden plus a small enemy or two small ones, and a trio is all small enemies.
## Enemies whose resource fails to load are left out (the cause is logged), so
## the result can be smaller than requested or empty.
static func varied_encounter(enemy_count: int, rng: RandomNumberGenerator) -> Array[EnemyData]:
	var count := clampi(enemy_count, 1, Combat.MAX_ENEMIES)
	var paths: Array[String] = []
	match count:
		1:
			paths.append(_pick_path(ALL_ENEMY_PATHS, rng))
		2:
			if rng.randf() < BIG_PAIR_CHANCE:
				paths.append(_pick_path(PAIR_BIG_ENEMY_PATHS, rng))
				paths.append(_pick_path(SMALL_ENEMY_PATHS, rng))
			else:
				paths.append(_pick_path(SMALL_ENEMY_PATHS, rng))
				paths.append(_pick_path(SMALL_ENEMY_PATHS, rng))
		_:
			for i in count:
				paths.append(_pick_path(_trio_paths(), rng))
	var enemies: Array[EnemyData] = []
	for path in paths:
		var enemy := _load_enemy(path)
		if enemy != null:
			enemies.append(enemy)
	return enemies


## SMALL_ENEMY_PATHS minus TRIO_EXCLUDED_PATHS, so a new small enemy joins trios by default.
static func _trio_paths() -> Array[String]:
	var paths: Array[String] = []
	for path in SMALL_ENEMY_PATHS:
		if not TRIO_EXCLUDED_PATHS.has(path):
			paths.append(path)
	return paths


## The boss fight: the Conductor alone. Empty (cause logged) if it fails to load,
## and Combat needs at least one enemy, so callers must check.
static func boss_encounter() -> Array[EnemyData]:
	var enemies: Array[EnemyData] = []
	var boss := _load_enemy(CONDUCTOR_PATH)
	if boss != null:
		enemies.append(boss)
	return enemies


static func _pick_path(paths: Array[String], rng: RandomNumberGenerator) -> String:
	return paths[rng.randi_range(0, paths.size() - 1)]


## Returns null (after logging an error) if the resource is missing or not a
## CardData. Checked explicitly rather than with assert so debug and release
## builds behave the same.
static func _load_card(path: String) -> CardData:
	var card: CardData = null
	if ResourceLoader.exists(path):
		card = load(path) as CardData
	if card == null:
		push_error("StarterContent: missing or non-CardData resource: %s" % path)
	return card


## Enemies are deep-copied so each encounter slot owns its data, as before.
## Returns null (after logging an error) if the resource is missing or not an EnemyData.
static func _load_enemy(path: String) -> EnemyData:
	var template: EnemyData = null
	if ResourceLoader.exists(path):
		template = load(path) as EnemyData
	if template == null:
		push_error("StarterContent: missing or non-EnemyData resource: %s" % path)
		return null
	return template.duplicate(true) as EnemyData
