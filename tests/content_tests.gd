extends RefCounted
## Content tests for the extra balance-testing cards and enemies.
## run() returns the failure count and prints a "FAIL: ..." line per failure.

var _failures := 0


func run() -> int:
	_failures = 0
	_test_new_cards_load()
	_test_new_enemies_load()
	_test_extended_deck()
	_test_existing_content_unchanged()
	_test_varied_encounter()
	_test_encounter_composition()
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
	}
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
	for path in [StarterContent.WISP_PATH, StarterContent.COLOSSUS_PATH]:
		var enemy := load(path) as EnemyData
		_check(enemy != null, "enemy loads as EnemyData: %s" % path)
		if enemy != null:
			_check(enemy.max_hp > 0 and not enemy.intents.is_empty(), "enemy has hp and intents: %s" % path)
	var wisp := StarterContent._load_enemy(StarterContent.WISP_PATH)
	var colossus := StarterContent._load_enemy(StarterContent.COLOSSUS_PATH)
	var shade := StarterContent.lost_shade()
	var warden := StarterContent.warden()
	if wisp != null and colossus != null and shade != null and warden != null:
		# Relative, so retuning numbers does not break the test; the roles must hold.
		_check(wisp.max_hp < shade.max_hp, "wisp is the most fragile small enemy")
		_check(colossus.max_hp > warden.max_hp, "colossus is tankier than the warden")
		_check(wisp.intents.size() != colossus.intents.size(), "distinct intent cycle lengths")


func _test_extended_deck() -> void:
	var deck := StarterContent.extended_deck()
	_check(deck.size() == StarterContent.EXTENDED_DECK_SIZE and deck.size() == 14, "extended deck has 14 cards")
	var counts := {}
	for card in deck:
		counts[card.id] = counts.get(card.id, 0) + 1
		_check(card.cost >= 0 and card.cost <= 3, "extended card playable: %s" % card.id)
	var want := {&"shove": 4, &"slip_past": 3, &"glimpse_exit": 1, &"heavy_blow": 2, &"brace": 1, &"steady_breath": 1, &"shoulder_charge": 1, &"mark_the_weak": 1}
	_check(counts == want, "extended deck composition: %s" % str(counts))


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
	_check(StarterContent.enemy_pool().size() == 4, "enemy pool has 4 enemies")
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
	for expected_name in ["Gate Warden", "Lost Shade", "Skittering Wisp", "Hollow Colossus"]:
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
		var pair := StarterContent.varied_encounter(2, rng)
		var big_count := 0
		for enemy in pair:
			if big_names.has(enemy.display_name):
				big_count += 1
		_check(big_count <= 1, "pair has at most one big enemy (seed %d)" % seed_value)
		saw_big_pair = saw_big_pair or big_count == 1
		saw_small_pair = saw_small_pair or big_count == 0
	_check(saw_big_pair and saw_small_pair, "both pair compositions occur across seeds")
