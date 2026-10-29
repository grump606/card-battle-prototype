extends SceneTree
## Headless tests. Run: godot --headless --path . -s res://tests/run_tests.gd

var _failures := 0


func _initialize() -> void:
	_test_damage_and_block()
	_test_draw_reshuffles_discard()
	_test_play_card_costs_energy()
	_test_rejects_unaffordable_and_invalid_plays()
	_test_enemy_intents_cycle_and_block_clears()
	_test_victory()
	_test_defeat()
	_test_same_seed_same_hand()
	_test_targeting_hits_chosen_enemy()
	_test_dead_or_invalid_target_rejected()
	_test_victory_needs_all_enemies_dead()
	_test_every_living_enemy_acts()
	_test_early_encounter_sizes()
	_test_draw_on_empty_piles()
	_test_block_does_not_outlast_a_turn()
	_test_zero_cost_cards()
	_test_enemy_without_intents()
	_test_multi_effect_card()
	_test_end_turn_after_combat_ended_is_noop()
	_test_constructor_limits()
	_test_content_loaders_reject_bad_resources()
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _dmg(amount: int) -> Array[CardEffect]:
	return [CardEffect.make(CardEffect.Kind.DAMAGE, amount)]


func _card(cost: int, effects: Array[CardEffect]) -> CardData:
	return CardData.make(&"t", "T", cost, effects)


func _deck(count: int, card: CardData) -> Array[CardData]:
	var deck: Array[CardData] = []
	for i in count:
		deck.append(card)
	return deck


func _enemies(count: int, hp: int, intents: Array[CardEffect]) -> Array[EnemyData]:
	var list: Array[EnemyData] = []
	for i in count:
		list.append(EnemyData.make("E%d" % i, hp, intents))
	return list


func _test_damage_and_block() -> void:
	var c := Combatant.new("c", 20)
	c.gain_block(5)
	_check(c.take_damage(8) == 3, "damage returns HP lost after block")
	_check(c.hp == 17 and c.block == 0, "block absorbed then HP reduced")
	c.take_damage(100)
	_check(c.hp == 0 and c.is_dead(), "HP never goes below zero")


func _test_draw_reshuffles_discard() -> void:
	var piles := CardPiles.new(_deck(3, _card(1, _dmg(1))), RandomNumberGenerator.new())
	piles.draw(3)
	piles.discard_hand()
	_check(piles.draw(2) == 2 and piles.hand.size() == 2, "draw reshuffles discard when pile is empty")
	_check(piles.draw(10) == 1, "draw stops when no cards remain")


func _test_play_card_costs_energy() -> void:
	var combat := Combat.new(Combatant.new("p", 20), _deck(10, _card(1, _dmg(4))), _enemies(1, 30, []))
	combat.start()
	_check(combat.energy == Combat.ENERGY_PER_TURN and combat.piles.hand.size() == Combat.HAND_SIZE, "turn start: energy and hand")
	_check(combat.play_card(0), "affordable card plays")
	_check(combat.energy == 2 and combat.enemies[0].hp == 26 and combat.piles.discard_pile.size() == 1, "play spends energy, damages, discards")


func _test_rejects_unaffordable_and_invalid_plays() -> void:
	var combat := Combat.new(Combatant.new("p", 20), _deck(10, _card(4, _dmg(4))), _enemies(1, 30, []))
	combat.start()
	_check(not combat.play_card(0), "cost above energy is rejected")
	_check(not combat.play_card(99) and not combat.play_card(-1), "out-of-range hand index rejected")
	_check(combat.enemies[0].hp == 30 and combat.piles.hand.size() == Combat.HAND_SIZE, "rejected play changes nothing")


func _test_enemy_intents_cycle_and_block_clears() -> void:
	var intents: Array[CardEffect] = [CardEffect.make(CardEffect.Kind.DAMAGE, 5), CardEffect.make(CardEffect.Kind.BLOCK, 7)]
	var combat := Combat.new(Combatant.new("p", 40), _deck(10, _card(1, _dmg(1))), _enemies(1, 30, intents))
	combat.start()
	combat.end_player_turn()
	_check(combat.player.hp == 35 and combat.turn == 2, "first intent hits, next turn begins")
	combat.end_player_turn()
	_check(combat.enemies[0].block == 7, "second intent grants block")
	combat.end_player_turn()
	_check(combat.enemies[0].block == 0 and combat.player.hp == 30, "enemy block clears on its turn; intents wrap")


func _test_victory() -> void:
	var combat := Combat.new(Combatant.new("p", 20), _deck(10, _card(1, _dmg(50))), _enemies(1, 30, []))
	var result: Array = []
	combat.combat_ended.connect(result.append)
	combat.start()
	combat.play_card(0)
	_check(result == [true] and combat.phase == Combat.Phase.ENDED, "killing enemy ends combat in victory")
	_check(not combat.play_card(0), "no plays after combat ends")


func _test_defeat() -> void:
	var intents: Array[CardEffect] = [CardEffect.make(CardEffect.Kind.DAMAGE, 99)]
	var combat := Combat.new(Combatant.new("p", 20), _deck(10, _card(1, _dmg(1))), _enemies(1, 30, intents))
	var result: Array = []
	combat.combat_ended.connect(result.append)
	combat.start()
	combat.end_player_turn()
	_check(result == [false] and combat.phase == Combat.Phase.ENDED, "dying ends combat in defeat")


func _test_same_seed_same_hand() -> void:
	var deck := StarterContent.deck()
	var a := Combat.new(Combatant.new("p", 20), deck, StarterContent.early_encounter(2), 42)
	var b := Combat.new(Combatant.new("p", 20), deck, StarterContent.early_encounter(2), 42)
	a.start()
	b.start()
	var same := true
	for i in a.piles.hand.size():
		same = same and a.piles.hand[i] == b.piles.hand[i]
	_check(same, "same seed gives the same opening hand")


func _test_targeting_hits_chosen_enemy() -> void:
	var combat := Combat.new(Combatant.new("p", 20), _deck(10, _card(1, _dmg(4))), _enemies(3, 30, []))
	combat.start()
	_check(combat.play_card(0, 2), "play on third enemy")
	_check(combat.enemies[2].hp == 26 and combat.enemies[0].hp == 30 and combat.enemies[1].hp == 30, "only the chosen enemy is damaged")
	combat.play_card(0)
	_check(combat.enemies[0].hp == 26, "default target is first living enemy")


func _test_dead_or_invalid_target_rejected() -> void:
	var combat := Combat.new(Combatant.new("p", 20), _deck(10, _card(0, _dmg(50))), _enemies(2, 30, []))
	combat.start()
	combat.play_card(0, 0)
	var hand_size := combat.piles.hand.size()
	_check(not combat.play_card(0, 0), "defeated target rejected")
	_check(not combat.play_card(0, 5) and not combat.play_card(0, -2), "out-of-range target rejected")
	_check(combat.piles.hand.size() == hand_size, "rejected target leaves hand untouched")


func _test_victory_needs_all_enemies_dead() -> void:
	var combat := Combat.new(Combatant.new("p", 20), _deck(10, _card(0, _dmg(50))), _enemies(2, 30, []))
	var result: Array = []
	combat.combat_ended.connect(result.append)
	combat.start()
	combat.play_card(0, 0)
	_check(result.is_empty() and combat.phase == Combat.Phase.PLAYER_TURN, "one enemy left: fight continues")
	combat.play_card(0, 1)
	_check(result == [true], "last enemy down: victory")


func _test_every_living_enemy_acts() -> void:
	var intents: Array[CardEffect] = [CardEffect.make(CardEffect.Kind.DAMAGE, 5)]
	var combat := Combat.new(Combatant.new("p", 40), _deck(10, _card(0, _dmg(50))), _enemies(3, 30, intents))
	combat.start()
	combat.play_card(0, 1)
	combat.end_player_turn()
	_check(combat.player.hp == 30, "two living enemies hit; the defeated one does not")


func _test_early_encounter_sizes() -> void:
	_check(StarterContent.early_encounter(0).size() == 1, "encounter size clamps up to 1")
	_check(StarterContent.early_encounter(2).size() == 2, "encounter of 2")
	_check(StarterContent.early_encounter(9).size() == Combat.MAX_ENEMIES, "encounter size clamps down to max")


func _test_draw_on_empty_piles() -> void:
	var draw_card := _card(0, [CardEffect.make(CardEffect.Kind.DRAW, 3)])
	var empty := CardPiles.new(_deck(0, draw_card), RandomNumberGenerator.new())
	_check(empty.draw(5) == 0 and empty.hand.is_empty(), "drawing from a fully empty deck draws nothing")
	var combat := Combat.new(Combatant.new("p", 20), _deck(1, draw_card), _enemies(1, 30, []))
	combat.start()
	_check(combat.piles.hand.size() == 1 and combat.piles.draw_pile.is_empty(), "short deck: hand holds the whole deck")
	_check(combat.play_card(0), "DRAW card plays with empty piles")
	_check(combat.piles.hand.size() + combat.piles.draw_pile.size() + combat.piles.discard_pile.size() == 1, "no cards created or lost by DRAW on thin piles")


func _test_block_does_not_outlast_a_turn() -> void:
	var block_card := _card(1, [CardEffect.make(CardEffect.Kind.BLOCK, 5)])
	var intents: Array[CardEffect] = [CardEffect.make(CardEffect.Kind.DAMAGE, 8)]
	var combat := Combat.new(Combatant.new("p", 40), _deck(10, block_card), _enemies(1, 30, intents))
	combat.start()
	combat.play_card(0)
	_check(combat.player.block == 5, "block gained on the player's turn")
	combat.end_player_turn()
	_check(combat.player.hp == 37 and combat.player.block == 0, "block absorbs the enemy hit, then clears at the next turn start")
	combat.end_player_turn()
	_check(combat.player.hp == 29, "no block carried into the following enemy turn")


func _test_zero_cost_cards() -> void:
	var combat := Combat.new(Combatant.new("p", 20), _deck(10, _card(0, _dmg(1))), _enemies(1, 30, []))
	combat.start()
	for i in Combat.HAND_SIZE:
		_check(combat.play_card(0), "free card %d plays" % i)
	_check(combat.energy == Combat.ENERGY_PER_TURN and combat.enemies[0].hp == 25, "0-cost cards spend no energy")
	_check(combat.piles.hand.is_empty() and not combat.play_card(0), "empty hand rejects plays")


func _test_enemy_without_intents() -> void:
	var combat := Combat.new(Combatant.new("p", 20), _deck(10, _card(1, _dmg(1))), _enemies(1, 30, []))
	var acted: Array = []
	combat.enemy_acted.connect(func(_e, _i): acted.append(true))
	combat.start()
	combat.end_player_turn()
	combat.end_player_turn()
	_check(acted.is_empty() and combat.player.hp == 20, "enemy with no intents never acts")
	_check(combat.turn == 3 and combat.phase == Combat.Phase.PLAYER_TURN, "turns still advance")
	_check(combat.enemies[0].current_intent() == null, "current_intent is null without intents")


func _test_multi_effect_card() -> void:
	var effects: Array[CardEffect] = [
		CardEffect.make(CardEffect.Kind.DAMAGE, 3),
		CardEffect.make(CardEffect.Kind.BLOCK, 2),
		CardEffect.make(CardEffect.Kind.DRAW, 1),
	]
	var combat := Combat.new(Combatant.new("p", 20), _deck(10, _card(2, effects)), _enemies(1, 30, []))
	combat.start()
	combat.play_card(0)
	_check(combat.enemies[0].hp == 27 and combat.player.block == 2, "damage and block both applied")
	_check(combat.piles.hand.size() == Combat.HAND_SIZE and combat.energy == 1, "draw applied after playing: hand back to full, cost paid once")


func _test_end_turn_after_combat_ended_is_noop() -> void:
	var intents: Array[CardEffect] = [CardEffect.make(CardEffect.Kind.DAMAGE, 5)]
	var combat := Combat.new(Combatant.new("p", 20), _deck(10, _card(1, _dmg(50))), _enemies(1, 30, intents))
	var result: Array = []
	combat.combat_ended.connect(result.append)
	combat.start()
	combat.play_card(0)
	var turn := combat.turn
	var hp := combat.player.hp
	combat.end_player_turn()
	_check(result == [true] and combat.turn == turn and combat.player.hp == hp and combat.phase == Combat.Phase.ENDED, "end_player_turn after the end changes nothing and does not re-emit")
	var fresh := Combat.new(Combatant.new("p", 20), _deck(10, _card(1, _dmg(1))), _enemies(1, 30, []))
	fresh.end_player_turn()
	_check(fresh.phase == Combat.Phase.NOT_STARTED and fresh.turn == 0, "end_player_turn before start is a no-op")


func _test_constructor_limits() -> void:
	var full := Combat.new(Combatant.new("p", 20), _deck(5, _card(1, _dmg(1))), _enemies(Combat.MAX_ENEMIES, 10, []))
	_check(full.enemies.size() == Combat.MAX_ENEMIES, "MAX_ENEMIES enemies accepted")
	var clamped := Combatant.new("p", 20, 50)
	_check(clamped.hp == 20, "starting HP above max is clamped")
	var half := Combatant.new("p", 20, 7)
	_check(half.hp == 7 and half.max_hp == 20, "explicit starting HP honoured")
	half.gain_block(-4)
	_check(half.block == 0, "negative block ignored")
	_check(half.take_damage(-5) == 0 and half.hp == 7, "negative damage ignored")


# The loaders log an error for each bad path; that output is expected here.
func _test_content_loaders_reject_bad_resources() -> void:
	_check(StarterContent._load_card("res://data/cards/nope.tres") == null, "missing card resource returns null")
	_check(StarterContent._load_enemy("res://data/enemies/nope.tres") == null, "missing enemy resource returns null")
	_check(StarterContent._load_card(StarterContent.WARDEN_PATH) == null, "enemy resource is not accepted as a card")
	_check(StarterContent._load_enemy(StarterContent.SHOVE_PATH) == null, "card resource is not accepted as an enemy")
	_check(StarterContent._load_card(StarterContent.SHOVE_PATH) != null, "valid card resource loads")
