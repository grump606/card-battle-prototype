extends RefCounted
## Tests for tools/smart_policy.gd (the run sim's --policy smart player).
## run() returns the failure count and prints a "FAIL: ..." line per failure.

var _failures := 0


func run() -> int:
	_failures = 0
	_test_takes_the_killing_blow()
	_test_exposes_before_damage()
	_test_plays_whole_runs_without_illegal_moves()
	_test_card_scoring_order()
	return _failures


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _card(id: StringName, cost: int, kind: CardEffect.Kind, amount: int) -> CardData:
	var effects: Array[CardEffect] = [CardEffect.make(kind, amount)]
	return CardData.make(id, String(id), cost, effects)


func _enemy(hp: int, damage: int) -> EnemyData:
	var intents: Array[CardEffect] = [CardEffect.make(CardEffect.Kind.DAMAGE, damage)]
	return EnemyData.make("e", hp, intents)


func _combat(hand_cards: Array[CardData], enemies: Array[EnemyData]) -> Combat:
	# A deck of at most HAND_SIZE cards is drawn whole into the opening hand.
	var combat := Combat.new(Combatant.new("p", 40), hand_cards, enemies, 1)
	combat.start()
	return combat


func _test_takes_the_killing_blow() -> void:
	var small := _card(&"small", 1, CardEffect.Kind.DAMAGE, 4)
	var enemies: Array[EnemyData] = [_enemy(30, 3), _enemy(4, 3)]
	var combat := _combat([small], enemies)
	_check(SmartPolicy.play_turn(combat), "smart policy plays a turn")
	_check(combat.enemies[1].is_dead() and combat.enemies[0].hp == 30, "the killing blow goes to the enemy it kills")


func _test_exposes_before_damage() -> void:
	var mark := _card(&"mark", 1, CardEffect.Kind.EXPOSE, 2)
	var hit := _card(&"hit", 1, CardEffect.Kind.DAMAGE, 8)
	var enemies: Array[EnemyData] = [_enemy(40, 1)]
	var combat := _combat([hit, mark], enemies)
	SmartPolicy.play_turn(combat)
	# Expose first: 8 x 3/2 = 12 damage; damage first would leave the Expose with nothing to boost.
	_check(combat.enemies[0].hp == 28, "expose is played before the damage card (hp %d)" % combat.enemies[0].hp)


func _test_plays_whole_runs_without_illegal_moves() -> void:
	for seed_value in 5:
		var run := RunState.new(seed_value)
		while not run.finished:
			match run.current_stop().type:
				RunState.StopType.COMBAT:
					var combat := run.start_combat()
					combat.start()
					var guard := 0
					while combat.phase == Combat.Phase.PLAYER_TURN and guard < 60:
						_check(SmartPolicy.play_turn(combat), "smart turn is legal (seed %d)" % seed_value)
						guard += 1
					run.complete_combat(combat.living_enemies().is_empty())
					if run.reward_pending():
						_check(run.resolve_reward(SmartPolicy.pick_reward(run)), "smart reward pick is accepted")
				RunState.StopType.REST:
					run.rest()
				RunState.StopType.STORY:
					run.read_story()
				RunState.StopType.VENDOR:
					_check(SmartPolicy.shop(run), "smart vendor visit succeeds")
		_check(run.finished, "run finished (seed %d)" % seed_value)


func _test_card_scoring_order() -> void:
	var run := RunState.new(1)
	var weak := _card(&"weak", 2, CardEffect.Kind.DAMAGE, 1)
	var strong := _card(&"strong", 1, CardEffect.Kind.DAMAGE, 30)
	var weights := SmartPolicy._weights(run.deck)
	_check(SmartPolicy.card_score(weak, weights) < SmartPolicy.card_score(strong, weights), "scoring ranks a stronger card higher")
