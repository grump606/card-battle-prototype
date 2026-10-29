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
const WISP_PATH := "res://data/enemies/skittering_wisp.tres"
const COLOSSUS_PATH := "res://data/enemies/hollow_colossus.tres"
const WHISPERER_PATH := "res://data/enemies/pale_whisperer.tres"
const EXTENDED_DECK_SIZE := 14
## Fixed order: warden, lost shade, wisp, colossus, whisperer. The colossus is a solo-only
## elite (it was unwinnable next to a second enemy in the balance sim); the
## warden can share a pair; small enemies are what packs are made of.
const ALL_ENEMY_PATHS: Array[String] = [WARDEN_PATH, LOST_SHADE_PATH, WISP_PATH, COLOSSUS_PATH, WHISPERER_PATH]
const PAIR_BIG_ENEMY_PATHS: Array[String] = [WARDEN_PATH]
const SMALL_ENEMY_PATHS: Array[String] = [LOST_SHADE_PATH, WISP_PATH, WHISPERER_PATH]
## Chance that a two-enemy encounter is a big plus a small enemy rather than two small ones.
const BIG_PAIR_CHANCE := 0.35


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


## Balance-testing deck of EXTENDED_DECK_SIZE (14) cards: 4 Shove, 3 Slip Past,
## 1 Glimpse the Exit, 2 Heavy Blow, 1 Brace, 1 Steady Breath, 1 Shoulder Charge,
## 1 Mark the Weak.
## Returns an empty deck (and logs the cause) if any card resource fails to load.
static func extended_deck() -> Array[CardData]:
	var cards: Array[CardData] = []
	var plan: Array = [
		[SHOVE_PATH, 4], [SLIP_PAST_PATH, 3], [GLIMPSE_EXIT_PATH, 1],
		[HEAVY_BLOW_PATH, 2], [BRACE_PATH, 1], [STEADY_BREATH_PATH, 1], [SHOULDER_CHARGE_PATH, 1],
		[MARK_THE_WEAK_PATH, 1],
	]
	for entry in plan:
		var card := _load_card(entry[0] as String)
		if card == null:
			var empty: Array[CardData] = []
			return empty
		for i in (entry[1] as int):
			cards.append(card)
	return cards


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


## All enemy types in a fixed order: warden, lost shade, wisp, colossus.
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
				paths.append(_pick_path(SMALL_ENEMY_PATHS, rng))
	var enemies: Array[EnemyData] = []
	for path in paths:
		var enemy := _load_enemy(path)
		if enemy != null:
			enemies.append(enemy)
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
