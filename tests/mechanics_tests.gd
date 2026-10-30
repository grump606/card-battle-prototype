extends RefCounted
## Card mechanics beyond plain damage and block: Hold, damage from Block, thorns.
## Registered by run_tests.gd. Each test builds tiny hand-made cards so the numbers
## checked here are the rules themselves, not the tuning of any real card.

var _failures := 0


func run() -> int:
	_failures = 0
	_test_hold_carries_block()
	_test_damage_from_block()
	_test_conditional_damage_from_block()
	_test_thorns()
	_test_describe()
	_test_real_cards()
	return _failures


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _fx(kind: CardEffect.Kind, amount: int, bonus: int = 0, threshold: int = 0) -> CardEffect:
	return CardEffect.make(kind, amount, bonus, threshold)


func _self_card(cost: int, effects: Array[CardEffect]) -> CardData:
	return CardData.make(&"t", "T", cost, effects, CardData.TargetMode.SELF)


func _attack_card(cost: int, effects: Array[CardEffect]) -> CardData:
	return CardData.make(&"t", "T", cost, effects)


func _enemies(count: int, hp: int, intents: Array[CardEffect]) -> Array[EnemyData]:
	var list: Array[EnemyData] = []
	for i in count:
		list.append(EnemyData.make("E%d" % i, hp, intents))
	return list


## A started fight whose opening hand is `hand` (a deck no bigger than the hand size is dealt whole).
func _fight(hand: Array[CardData], enemy_hp: int = 100, intents: Array[CardEffect] = [], enemy_count: int = 1) -> Combat:
	var combat := Combat.new(Combatant.new("p", 40), hand, _enemies(enemy_count, enemy_hp, intents))
	combat.start()
	return combat


func _play(combat: Combat, card: CardData, target: int = 0) -> bool:
	return combat.play_card(combat.piles.hand.find(card), target)


func _test_hold_carries_block() -> void:
	var hold_card := _self_card(0, [_fx(CardEffect.Kind.BLOCK, 6), _fx(CardEffect.Kind.HOLD, 3)])
	var combat := _fight([hold_card])
	_play(combat, hold_card)
	_check(combat.player.block == 6 and combat.player.hold == 3, "Hold is recorded alongside the Block")
	combat.end_player_turn()
	_check(combat.player.block == 3 and combat.player.hold == 0, "only the held 3 of 6 Block carries into the next turn, and Hold resets")

	var other := _self_card(0, [_fx(CardEffect.Kind.BLOCK, 6), _fx(CardEffect.Kind.HOLD, 3)])
	var two := _fight([hold_card, other])
	_play(two, hold_card)
	_play(two, other)
	two.end_player_turn()
	_check(two.player.block == 6, "two Hold cards keep 3 + 3 = 6 Block")

	# An attack eats Block first: 6 Block less 4 damage leaves 2, so only 2 of the Hold 3 survives.
	var hit := _fight([hold_card], 100, [_fx(CardEffect.Kind.DAMAGE, 4)])
	_play(hit, hold_card)
	hit.end_player_turn()
	_check(hit.player.block == 2 and hit.player.hp == 40, "Hold keeps at most the Block that survived the enemy phase")

	var crushed := _fight([hold_card], 100, [_fx(CardEffect.Kind.DAMAGE, 20)])
	_play(crushed, hold_card)
	crushed.end_player_turn()
	_check(crushed.player.block == 0, "when the attack breaks through, nothing is left to hold")

	var big_hold := _self_card(0, [_fx(CardEffect.Kind.BLOCK, 2), _fx(CardEffect.Kind.HOLD, 9)])
	var capped := _fight([big_hold])
	_play(capped, big_hold)
	capped.end_player_turn()
	_check(capped.player.block == 2, "Hold never keeps more Block than there is")

	var plain := _self_card(0, [_fx(CardEffect.Kind.BLOCK, 5)])
	var reset := _fight([plain])
	_play(reset, plain)
	reset.end_player_turn()
	_check(reset.player.block == 0, "Block without Hold still resets each turn")

	var once := _fight([hold_card])
	_play(once, hold_card)
	once.end_player_turn()
	once.end_player_turn()
	_check(once.player.block == 0, "held Block is kept for one turn, not forever")

	var ending := _fight([hold_card], 1)
	_play(ending, hold_card)
	_check(ending.player.hold == 3, "setup: Hold is pending mid-fight")
	ending.abandon()
	_check(ending.player.hold == 0 and ending.player.thorns == 0, "abandoning a fight clears Hold and Thorns")


func _test_damage_from_block() -> void:
	var block_card := _self_card(0, [_fx(CardEffect.Kind.BLOCK, 7)])
	var bash := _attack_card(0, [_fx(CardEffect.Kind.DAMAGE_PER_BLOCK, 1)])
	var cold := _fight([bash])
	_play(cold, bash)
	_check(cold.enemies[0].hp == 100, "with no Block it deals nothing")

	var combat := _fight([block_card, bash])
	_play(combat, block_card)
	_play(combat, bash)
	_check(combat.enemies[0].hp == 93 and combat.player.block == 7, "it deals damage equal to current Block and spends none of it")

	var doubled := _attack_card(0, [_fx(CardEffect.Kind.DAMAGE_PER_BLOCK, 2)])
	var twice := _fight([block_card, doubled])
	_play(twice, block_card)
	_play(twice, doubled)
	_check(twice.enemies[0].hp == 86, "a multiplier of 2 doubles the Block into damage")

	# It hits every target of an all-enemies card.
	var sweep := CardData.make(&"s", "S", 0, [_fx(CardEffect.Kind.DAMAGE_PER_BLOCK, 1)], CardData.TargetMode.ALL_ENEMIES)
	var spread := _fight([block_card, sweep], 100, [], 2)
	_play(spread, block_card)
	_play(spread, sweep)
	_check(spread.enemies[0].hp == 93 and spread.enemies[1].hp == 93, "an all-enemies Block-damage card hits each enemy")


func _test_conditional_damage_from_block() -> void:
	var steel := _attack_card(0, [_fx(CardEffect.Kind.DAMAGE_IF_BLOCK, 5, 10, 10)])
	var below := _fight([steel])
	_play(below, steel)
	_check(below.enemies[0].hp == 95, "below the threshold the base damage applies")

	var ten := _self_card(0, [_fx(CardEffect.Kind.BLOCK, 10)])
	var at := _fight([ten, steel])
	_play(at, ten)
	_play(at, steel)
	_check(at.enemies[0].hp == 90, "at exactly the threshold the bonus damage applies")

	var nine := _self_card(0, [_fx(CardEffect.Kind.BLOCK, 9)])
	var under := _fight([nine, steel])
	_play(under, nine)
	_play(under, steel)
	_check(under.enemies[0].hp == 95, "one short of the threshold still deals the base damage")


func _test_thorns() -> void:
	var stance := _self_card(0, [_fx(CardEffect.Kind.BLOCK, 8), _fx(CardEffect.Kind.THORNS, 4)])
	var attack := [_fx(CardEffect.Kind.DAMAGE, 5)] as Array[CardEffect]

	var combat := _fight([stance], 50, attack)
	_play(combat, stance)
	combat.end_player_turn()
	_check(combat.enemies[0].hp == 46 and combat.player.hp == 40, "a fully blocked attack still triggers thorns")
	_check(combat.player.thorns == 0, "thorns end with the enemy phase")

	var multi := _fight([stance], 50, [_fx(CardEffect.Kind.DAMAGE, 1)], 3)
	_play(multi, stance)
	multi.end_player_turn()
	var all_hit := true
	for enemy in multi.enemies:
		all_hit = all_hit and enemy.hp == 46
	_check(all_hit, "each attacker takes the thorns damage")

	var other := _self_card(0, [_fx(CardEffect.Kind.BLOCK, 8), _fx(CardEffect.Kind.THORNS, 4)])
	var stacked := _fight([stance, other], 50, [_fx(CardEffect.Kind.DAMAGE, 1)])
	_play(stacked, stance)
	_play(stacked, other)
	stacked.end_player_turn()
	_check(stacked.enemies[0].hp == 42, "two thorns cards stack: 4 + 4")

	var finishing := _fight([stance], 4, [_fx(CardEffect.Kind.DAMAGE, 1)])
	var won := [false]
	finishing.combat_ended.connect(func(victory: bool) -> void: won[0] = victory)
	_play(finishing, stance)
	finishing.end_player_turn()
	_check(won[0] and finishing.phase == Combat.Phase.ENDED, "thorns that kill the last enemy win the fight")

	var passive := _fight([stance], 50, [_fx(CardEffect.Kind.BLOCK, 3)])
	_play(passive, stance)
	passive.end_player_turn()
	_check(passive.enemies[0].hp == 50, "an enemy that does not attack takes no thorns damage")

	var none := _fight([stance], 50, [_fx(CardEffect.Kind.DAMAGE, 1)])
	none.end_player_turn()
	_check(none.enemies[0].hp == 50, "no thorns played, no thorns damage")

	# Exposed attackers take thorns damage like any other hit.
	var expose := _attack_card(0, [_fx(CardEffect.Kind.EXPOSE, 2)])
	var exposed := _fight([stance, expose], 50, [_fx(CardEffect.Kind.DAMAGE, 1)])
	_play(exposed, expose)
	_play(exposed, stance)
	exposed.end_player_turn()
	_check(exposed.enemies[0].hp == 44, "thorns damage on an Exposed attacker is scaled like any hit (4 x 1.5 = 6)")


func _test_describe() -> void:
	_check(_fx(CardEffect.Kind.HOLD, 3).describe() == "Hold 3", "Hold describes itself")
	_check(_fx(CardEffect.Kind.THORNS, 4).describe() == "Thorns 4", "Thorns describes itself")
	_check(_fx(CardEffect.Kind.DAMAGE_PER_BLOCK, 1).describe() == "Deal damage equal to your Block", "Block damage describes itself")
	_check(_fx(CardEffect.Kind.DAMAGE_PER_BLOCK, 2).describe() == "Deal 2x your Block", "a multiplied Block damage describes the multiplier")
	_check(_fx(CardEffect.Kind.DAMAGE_IF_BLOCK, 5, 10, 10).describe() == "Deal 5 (10 with 10+ Block)", "conditional damage describes both numbers")
	# The pre-existing kinds keep their stored integer values (.tres files hold the number).
	_check(CardEffect.Kind.DAMAGE == 0 and CardEffect.Kind.BLOCK == 1 and CardEffect.Kind.DRAW == 2 and CardEffect.Kind.EXPOSE == 3, "existing effect kinds keep their integer values")


## The real Deserter cards, loaded from data, do what their text says.
func _test_real_cards() -> void:
	var cards := {}
	for path in StarterContent.ALL_CARD_PATHS:
		var card := load(path) as CardData
		cards[card.id] = card
	for id in [&"hold_the_line", &"bash", &"dig_in", &"cold_steel", &"counter_stance", &"last_stand"]:
		_check(cards.has(id) and (cards[id] as CardData).character == &"deserter", "%s is a Deserter card" % id)
	_check(cards[&"hold_the_line"].describe() == "Block 6, Hold 3", "Hold the Line text")
	_check(cards[&"last_stand"].cost == 3 and cards[&"last_stand"].describe() == "Block 16, Hold 16", "Last Stand keeps all its Block")
	_check(cards[&"counter_stance"].describe() == "Block 8, Thorns 4", "Counter-Stance text")
	_check(cards[&"cold_steel"].describe() == "Deal 5 (10 with 10+ Block)", "Cold Steel text")

	# Last Stand: Block 16, all of it survives an empty enemy phase.
	var last_stand: CardData = cards[&"last_stand"]
	var fight := Combat.new(Combatant.new("p", 40), [last_stand] as Array[CardData], _enemies(1, 100, []))
	fight.start()
	fight.play_card(0)
	fight.end_player_turn()
	_check(fight.player.block == 16, "Last Stand carries all 16 Block")

	# Bash after Hold the Line: 6 Block, 6 damage.
	var hold_line: CardData = cards[&"hold_the_line"]
	var bash: CardData = cards[&"bash"]
	var combo := Combat.new(Combatant.new("p", 40), [hold_line, bash] as Array[CardData], _enemies(1, 100, []))
	combo.start()
	combo.play_card(combo.piles.hand.find(hold_line))
	combo.play_card(combo.piles.hand.find(bash), 0)
	_check(combo.enemies[0].hp == 94, "Hold the Line then Bash deals 6")
