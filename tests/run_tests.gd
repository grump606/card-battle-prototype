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
