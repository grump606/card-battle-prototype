extends RefCounted
## Tests for the run layer (run/run_state.gd). Returns the failure count; the
## suite in run_tests.gd adds it to its own.

var _failures := 0


func run() -> int:
	_failures = 0
	_test_fresh_state()
	_test_default_line()
	_test_start_combat_builds_fight_with_persistent_player()
	_test_start_combat_rejected_off_combat_stop()
	_test_defeat_ends_run()
	_test_reward_flow()
	_test_rest()
	_test_full_run_escapes()
	_test_seed_determinism()
	return _failures


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


## Wins the current combat stop and skips the reward, moving the run on.
func _win_and_skip(state: RunState) -> void:
	state.complete_combat(true)
	state.resolve_reward(null)


func _test_fresh_state() -> void:
	var state := RunState.new(1)
	_check(state.player.hp == RunState.START_HP and state.player.max_hp == RunState.START_HP, "run starts at full HP")
	_check(state.deck.size() == StarterContent.EXTENDED_DECK_SIZE, "run starts with the extended deck")
	_check(not state.finished and state.stop_index == 0 and not state.reward_pending(), "run starts unfinished at stop 0")


func _test_default_line() -> void:
	var state := RunState.new(1)
	_check(state.stops.size() == 7, "default line has 7 stops")
	_check(state.stops[0].type == RunState.StopType.COMBAT and state.stops[0].enemy_count == 1, "first stop is a solo fight")
	_check(state.stops[2].type == RunState.StopType.REST and state.stops[5].type == RunState.StopType.REST, "rests sit at stops 3 and 6")
	_check(state.stops[6].type == RunState.StopType.COMBAT and state.stops[6].enemy_count == Combat.MAX_ENEMIES, "final stop is a full pack")


func _test_start_combat_builds_fight_with_persistent_player() -> void:
	var state := RunState.new(2)
	state.player.take_damage(15)
	var combat := state.start_combat()
	_check(combat != null, "combat stop builds a fight")
	if combat == null:
		return
	_check(combat.player == state.player and combat.player.hp == RunState.START_HP - 15, "fight uses the run's player with carried-over HP")
	_check(combat.enemies.size() == 1, "stop 1 fight has the stop's enemy count")
	_check(combat.piles.draw_pile.size() + combat.piles.hand.size() == state.deck.size() or combat.phase == Combat.Phase.NOT_STARTED, "fight is built from the run's deck")
	combat.abandon()


# These push_error on purpose; that output is expected here.
func _test_start_combat_rejected_off_combat_stop() -> void:
	var state := RunState.new(3)
	_win_and_skip(state)
	_win_and_skip(state)
	_check(state.current_stop().type == RunState.StopType.REST, "setup: now at the rest stop")
	_check(state.start_combat() == null, "no fight can start at a rest stop")
	var other := RunState.new(3)
	other.complete_combat(true)
	_check(other.reward_pending() and other.start_combat() == null, "no fight can start while a reward is pending")


func _test_defeat_ends_run() -> void:
	var state := RunState.new(4)
	state.complete_combat(false)
	_check(state.finished and not state.escaped, "defeat ends the run without escape")
	_check(state.current_stop() == null and not state.reward_pending(), "no stop or reward after defeat")


func _test_reward_flow() -> void:
	var state := RunState.new(5)
	state.complete_combat(true)
	var choices := state.reward_choices()
	_check(state.reward_pending() and choices.size() == RunState.REWARD_CHOICES, "victory offers %d reward cards" % RunState.REWARD_CHOICES)
	var ids := {}
	for card in choices:
		ids[card.id] = true
	_check(ids.size() == choices.size(), "reward cards are distinct")
	_check(state.reward_choices() == choices, "asking again does not re-roll the choices")
	var deck_before := state.deck.size()
	var stranger := CardData.make(&"not_offered", "Nope", 1, [CardEffect.make(CardEffect.Kind.DAMAGE, 1)])
	_check(not state.resolve_reward(stranger), "a card that was not offered is rejected")
	_check(state.reward_pending() and state.deck.size() == deck_before and state.stop_index == 0, "rejected reward changes nothing")
	_check(state.resolve_reward(choices[0]), "an offered card is accepted")
	_check(state.deck.size() == deck_before + 1 and state.deck.back() == choices[0], "taken reward is added to the deck")
	_check(not state.reward_pending() and state.stop_index == 1, "taking the reward moves to the next stop")
	_check(not state.resolve_reward(null), "no reward to resolve when none is pending")

	var skipper := RunState.new(5)
	skipper.complete_combat(true)
	var size := skipper.deck.size()
	_check(skipper.resolve_reward(null) and skipper.deck.size() == size and skipper.stop_index == 1, "skipping adds nothing and moves on")


func _test_rest() -> void:
	var state := RunState.new(6)
	_check(state.rest() == -1 and state.stop_index == 0, "rest does nothing at a combat stop")
	_win_and_skip(state)
	_win_and_skip(state)
	state.player.take_damage(30)
	var hp_before := state.player.hp
	_check(state.rest() == RunState.REST_HEAL and state.player.hp == hp_before + RunState.REST_HEAL, "rest heals and reports HP restored")
	_check(state.stop_index == 3, "rest moves to the next stop")

	var full := RunState.new(6)
	_win_and_skip(full)
	_win_and_skip(full)
	_check(full.rest() == 0 and full.player.hp == full.player.max_hp, "rest at full HP restores nothing and never overheals")


func _test_full_run_escapes() -> void:
	var state := RunState.new(7)
	var guard := 0
	while not state.finished and guard < 50:
		guard += 1
		if state.current_stop().type == RunState.StopType.COMBAT:
			_win_and_skip(state)
		else:
			state.rest()
	_check(state.finished and state.escaped and state.stop_index == state.stops.size(), "winning every fight reaches the end and escapes")
	_check(state.current_stop() == null, "no current stop after the run is finished")


func _test_seed_determinism() -> void:
	var a := RunState.new(99)
	var b := RunState.new(99)
	var fight_a := a.start_combat()
	var fight_b := b.start_combat()
	var same_enemies := fight_a != null and fight_b != null and fight_a.enemies.size() == fight_b.enemies.size()
	if same_enemies:
		for i in fight_a.enemies.size():
			same_enemies = same_enemies and fight_a.enemies[i].display_name == fight_b.enemies[i].display_name
	_check(same_enemies, "same seed builds the same first fight")
	if fight_a != null:
		fight_a.abandon()
	if fight_b != null:
		fight_b.abandon()
	a.complete_combat(true)
	b.complete_combat(true)
	var ids_a: Array = a.reward_choices().map(func(c: CardData) -> StringName: return c.id)
	var ids_b: Array = b.reward_choices().map(func(c: CardData) -> StringName: return c.id)
	_check(ids_a == ids_b, "same seed offers the same rewards")
