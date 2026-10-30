extends RefCounted
## Content tests for the extra balance-testing cards and enemies.
## run() returns the failure count and prints a "FAIL: ..." line per failure.

var _failures := 0


func run() -> int:
	_failures = 0
	_test_new_cards_load()
	_test_new_enemies_load()
	_test_small_enemies_in_trios()
	_test_extended_deck()
	_test_existing_content_unchanged()
	_test_varied_encounter()
	_test_encounter_composition()
	_test_colossus_never_in_pairs_or_trios()
	_test_boss_encounter()
	return _failures


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _test_new_cards_load() -> void:
	var expected := {
		StarterContent.HEAVY_BLOW_PATH: [2, [CardEffect.Kind.DAMAGE]],
		StarterContent.BRACE_PATH: [0, [CardEffect.Kind.BLOCK]],
		StarterContent.STEADY_BREATH_PATH: [1, [CardEffect.Kind.DRAW, CardEffect.Kind.BLOCK]],
		StarterContent.SHOULDER_CHARGE_PATH: [2, [CardEffect.Kind.DAMAGE, CardEffect.Kind.BLOCK]],
		StarterContent.HAMSTRING_PATH: [2, [CardEffect.Kind.DAMAGE, CardEffect.Kind.EXPOSE]],
		StarterContent.IRON_RESOLVE_PATH: [2, [CardEffect.Kind.BLOCK]],
		StarterContent.FLURRY_PATH: [0, [CardEffect.Kind.DAMAGE]],
		StarterContent.GUARDED_STRIKE_PATH: [1, [CardEffect.Kind.DAMAGE, CardEffect.Kind.BLOCK]],
	}
	var ids := {}
	for path in [StarterContent.HAMSTRING_PATH, StarterContent.IRON_RESOLVE_PATH, StarterContent.FLURRY_PATH, StarterContent.GUARDED_STRIKE_PATH]:
		var added := load(path) as CardData
		if added != null:
			_check(not ids.has(added.id), "new card id unique: %s" % path)
			ids[added.id] = true
			var price := Vendor.card_price(added)
			_check(price == Vendor.PRICE_CHEAP or price == Vendor.PRICE_MID or price == Vendor.PRICE_PRICEY, "vendor prices new card: %s" % path)
	for path in expected:
		var card := load(path) as CardData
		_check(card != null, "card loads as CardData: %s" % path)
		if card == null:
			continue
		_check(card.cost == expected[path][0], "card cost: %s" % path)
		var kinds: Array = expected[path][1]
		_check(card.effects.size() == kinds.size(), "card effect count: %s" % path)
		if card.effects.size() == kinds.size():
			for i in kinds.size():
				_check(card.effects[i].kind == kinds[i] and card.effects[i].amount > 0, "card effect %d: %s" % [i, path])


func _test_new_enemies_load() -> void:
	for path in [StarterContent.WISP_PATH, StarterContent.COLOSSUS_PATH, StarterContent.CINDER_HOUND_PATH, StarterContent.MOURNING_CROW_PATH]:
		var enemy := load(path) as EnemyData
		_check(enemy != null, "enemy loads as EnemyData: %s" % path)
		if enemy != null:
			_check(enemy.max_hp > 0 and not enemy.intents.is_empty(), "enemy has hp and intents: %s" % path)
	var wisp := StarterContent._load_enemy(StarterContent.WISP_PATH)
	var colossus := StarterContent._load_enemy(StarterContent.COLOSSUS_PATH)
	var shade := StarterContent.lost_shade()
	var warden := StarterContent.warden()
	_check(wisp != null and colossus != null and shade != null and warden != null, "all four enemies used for the role checks loaded")
	if wisp != null and colossus != null and shade != null and warden != null:
		# Relative, so retuning numbers does not break the test; the roles must hold.
		_check(wisp.max_hp < shade.max_hp, "wisp is the most fragile small enemy")
		_check(colossus.max_hp > warden.max_hp, "colossus is tankier than the warden")
		_check(wisp.intents.size() != colossus.intents.size(), "distinct intent cycle lengths")


func _test_small_enemies_in_trios() -> void:
	var small: Array[String] = [StarterContent.CINDER_HOUND_PATH, StarterContent.MOURNING_CROW_PATH]
	for path in small:
		_check(StarterContent.SMALL_ENEMY_PATHS.has(path) and StarterContent.ALL_ENEMY_PATHS.has(path), "new small enemy is registered: %s" % path)
		_check(StarterContent._trio_paths().has(path), "new small enemy may appear in trios: %s" % path)
	var hound := StarterContent._load_enemy(StarterContent.CINDER_HOUND_PATH)
	var crow := StarterContent._load_enemy(StarterContent.MOURNING_CROW_PATH)
	if hound != null and crow != null:
		_check(hound.max_hp != crow.max_hp and hound.intents.size() != crow.intents.size(), "new enemies are distinct")
		_check(hound.max_hp >= 16 and hound.max_hp <= 24 and crow.max_hp >= 16 and crow.max_hp <= 24, "new enemies are small")


func _test_extended_deck() -> void:
	var deck := StarterContent.extended_deck()
	_check(deck.size() == StarterContent.EXTENDED_DECK_SIZE and deck.size() == 14, "extended deck has 14 cards")
	var counts := {}
	for card in deck:
		counts[card.id] = counts.get(card.id, 0) + 1
		_check(card.cost >= 0 and card.cost <= 3, "extended card playable: %s" % card.id)
	var want := {&"shove": 3, &"slip_past": 2, &"glimpse_exit": 1, &"heavy_blow": 1, &"brace": 1, &"steady_breath": 1, &"shoulder_charge": 1, &"mark_the_weak": 1, &"sweep": 1, &"cutting_word": 1, &"second_wind": 1}
	_check(counts == want, "extended deck composition: %s" % str(counts))

	_test_characters_and_pools()


func _test_existing_content_unchanged() -> void:
	var deck := StarterContent.deck()
	_check(deck.size() == 10, "starter deck still 10 cards")
	_check(StarterContent.warden().display_name == "Gate Warden", "warden unchanged")
	_check(StarterContent.lost_shade().display_name == "Lost Shade", "lost shade unchanged")
	_check(StarterContent.early_encounter(1)[0].display_name == "Gate Warden", "early_encounter(1) unchanged")
	_check(StarterContent.early_encounter(3).size() == 3, "early_encounter(3) unchanged")


func _names(enemies: Array[EnemyData]) -> Array:
	var names: Array = []
	for enemy in enemies:
		names.append(enemy.display_name)
	return names


func _test_varied_encounter() -> void:
	_check(StarterContent.enemy_pool().size() == 7, "enemy pool has 7 enemies")
	var seen := {}
	for seed_value in 60:
		for requested in [-2, 0, 1, 2, 3, 9]:
			var a := RandomNumberGenerator.new()
			a.seed = seed_value
			var b := RandomNumberGenerator.new()
			b.seed = seed_value
			var first := StarterContent.varied_encounter(requested, a)
			var second := StarterContent.varied_encounter(requested, b)
			var expected_count := clampi(requested, 1, Combat.MAX_ENEMIES)
			_check(first.size() == expected_count, "varied_encounter(%d) size %d" % [requested, first.size()])
			_check(_names(first) == _names(second), "varied_encounter deterministic for seed %d" % seed_value)
			for enemy in first:
				seen[enemy.display_name] = true
	for expected_name in ["Gate Warden", "Lost Shade", "Skittering Wisp", "Hollow Colossus", "Pale Whisperer", "Cinder Hound", "Mourning Crow"]:
		_check(seen.has(expected_name), "varied_encounter uses enemy: %s" % expected_name)
	var one_rng := RandomNumberGenerator.new()
	one_rng.seed = 1
	var duplicate_check := StarterContent.varied_encounter(3, one_rng)
	for i in duplicate_check.size():
		for j in range(i + 1, duplicate_check.size()):
			_check(duplicate_check[i] != duplicate_check[j], "encounter slots own separate EnemyData")


## Packs must stay survivable: trios are all small enemies, pairs have at most one big one.
func _test_encounter_composition() -> void:
	var big_names := [StarterContent.warden().display_name, (StarterContent._load_enemy(StarterContent.COLOSSUS_PATH)).display_name]
	var saw_big_pair := false
	var saw_small_pair := false
	for seed_value in 100:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var trio := StarterContent.varied_encounter(3, rng)
		for enemy in trio:
			_check(not big_names.has(enemy.display_name), "trio has no big enemy (seed %d)" % seed_value)
			_check(enemy.display_name != StarterContent.lost_shade().display_name, "trio has no Lost Shade (seed %d)" % seed_value)
		var pair := StarterContent.varied_encounter(2, rng)
		var big_count := 0
		for enemy in pair:
			if big_names.has(enemy.display_name):
				big_count += 1
		_check(big_count <= 1, "pair has at most one big enemy (seed %d)" % seed_value)
		saw_big_pair = saw_big_pair or big_count == 1
		saw_small_pair = saw_small_pair or big_count == 0
	_check(saw_big_pair and saw_small_pair, "both pair compositions occur across seeds")


## The Colossus is a solo-only elite: it was unwinnable beside another enemy in the sim.
func _test_colossus_never_in_pairs_or_trios() -> void:
	var colossus_name: String = StarterContent._load_enemy(StarterContent.COLOSSUS_PATH).display_name
	var solo_seen := false
	for seed_value in 300:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for count in [2, 3]:
			for enemy in StarterContent.varied_encounter(count, rng):
				_check(enemy.display_name != colossus_name, "the colossus never shares a fight (seed %d, %d enemies)" % [seed_value, count])
		for enemy in StarterContent.varied_encounter(1, rng):
			solo_seen = solo_seen or enemy.display_name == colossus_name
	_check(solo_seen, "the colossus does appear as a solo fight")


func _test_boss_encounter() -> void:
	var boss := StarterContent.boss_encounter()
	_check(boss.size() == 1 and boss[0].display_name == "The Conductor", "boss_encounter is the Conductor alone")
	_check(boss[0] != StarterContent.boss_encounter()[0], "each boss encounter owns its own copy of the data")
	var pool_names := []
	for enemy in StarterContent.enemy_pool():
		pool_names.append(enemy.display_name)
	_check(not pool_names.has("The Conductor"), "the boss is not in the random enemy pool")
	for seed_value in 100:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for count in [1, 2, 3]:
			for enemy in StarterContent.varied_encounter(count, rng):
				_check(enemy.display_name != "The Conductor", "the boss never appears in a random encounter (seed %d)" % seed_value)


## Characters own their starting decks and class cards; neutral cards are shared.
func _test_characters_and_pools() -> void:
	var all := StarterContent.all_cards()
	_check(all.size() == StarterContent.ALL_CARD_PATHS.size() and all.size() == 35, "all_cards loads all 35 cards")
	var ids := {}
	for card in all:
		_check(not ids.has(card.id), "card id is unique: %s" % card.id)
		ids[card.id] = true
		_check(card.character == &"" or StarterContent.CHARACTER_PATHS.has(card.character), "card %s is neutral or tagged for a known character" % card.id)
	var neutral_ids: Array = []
	for card in all:
		if card.character == &"":
			neutral_ids.append(String(card.id))
	neutral_ids.sort()
	_check(neutral_ids == ["brace", "flurry", "glimpse_exit", "shove", "slip_past", "sweep"], "the neutral pool is Brace, Flurry, Glimpse the Exit, Shove, Slip Past and Sweep")

	_check(StarterContent.character_ids() == [&"deserter", &"pickpocket", &"medium"], "three characters, in selection order")
	_check(StarterContent.character(&"nobody") == null, "an unknown character is null")
	var max_hp := {&"deserter": 47, &"pickpocket": 34, &"medium": 41}
	for id in StarterContent.character_ids():
		var character := StarterContent.character(id)
		_check(character != null and character.id == id and character.display_name != "" and character.pitch != "", "character %s loads with a name and pitch" % id)
		if character == null:
			continue
		_check(character.max_hp == max_hp[id], "character %s starts at %d HP" % [id, max_hp[id]])
		_check(character.starting_deck.size() == 10, "character %s starts with 10 cards" % id)
		for card in character.starting_deck:
			_check(card.character == &"" or card.character == id, "%s starting deck holds only neutral or own cards (%s)" % [id, card.id])
		var pool := StarterContent.reward_pool(id)
		var pool_ids := {}
		for card in pool:
			_check(not pool_ids.has(card.id), "%s pool card is distinct: %s" % [id, card.id])
			pool_ids[card.id] = true
			_check(card.character == &"" or card.character == id, "%s pool holds only neutral or own cards (%s)" % [id, card.id])
		for card in character.starting_deck:
			_check(pool_ids.has(card.id), "%s can be offered every card it starts with (%s)" % [id, card.id])
		_check(pool.size() >= 6, "%s pool can fill a three-card offer" % id)
	var deserter_ids := {}
	for card in StarterContent.reward_pool(&"deserter"):
		deserter_ids[card.id] = true
	_check(deserter_ids.has(&"heavy_blow") and not deserter_ids.has(&"hamstring"), "the Deserter can take Heavy Blow but not the Pickpocket's Hamstring")
