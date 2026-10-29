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
	_test_story_flow()
	_test_story_stop_with_missing_beat_is_passable()
	_test_story_content_loaders()
	_test_full_run_escapes()
	_test_seed_determinism()
	_test_gold_from_wins()
	_test_vendor_flow()
	_test_complete_combat_preconditions()
	_test_vendor_gold_and_stale_state()
	_test_start_combat_twice_releases_first()
	_test_rewards_rolled_eagerly_and_copied()
	return _failures


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


## Wins the current combat stop and skips the reward, moving the run on.
func _win_and_skip(state: RunState) -> void:
	state.complete_combat(true)
	state.resolve_reward(null)


## A run that has read the boarding beat and stands at the first fight (stop index 1).
func _at_first_fight(rng_seed: int) -> RunState:
	var state := RunState.new(rng_seed)
	state.read_story()
	return state


func _test_fresh_state() -> void:
	var state := RunState.new(1)
	_check(state.player.hp == RunState.START_HP and state.player.max_hp == RunState.START_HP, "run starts at full HP")
	_check(state.deck.size() == StarterContent.EXTENDED_DECK_SIZE, "run starts with the extended deck")
	_check(not state.finished and state.stop_index == 0 and not state.reward_pending(), "run starts unfinished at stop 0")


func _test_default_line() -> void:
	var state := RunState.new(1)
	_check(state.stops.size() == 10, "default line has 10 stops")
	_check(state.stops[0].type == RunState.StopType.STORY and state.stops[0].describe() == "Story", "the line opens with a story beat")
	_check(state.stops[1].type == RunState.StopType.COMBAT and state.stops[1].enemy_count == 1, "first fight is a solo fight")
	_check(state.stops[3].type == RunState.StopType.REST and state.stops[7].type == RunState.StopType.REST, "rests sit at stops 4 and 8")
	_check(state.stops[5].type == RunState.StopType.VENDOR and state.stops[5].describe() == "Vendor", "a vendor comes before the first trio")
	_check(state.stops[8].type == RunState.StopType.STORY, "a story beat comes just before the final fight")
	_check(state.stops[9].type == RunState.StopType.COMBAT and state.stops[9].enemy_count == Combat.MAX_ENEMIES, "final stop is a full pack")


func _test_start_combat_builds_fight_with_persistent_player() -> void:
	var state := _at_first_fight(2)
	state.player.take_damage(15)
	var combat := state.start_combat()
	_check(combat != null, "combat stop builds a fight")
	if combat == null:
		return
	_check(combat.player == state.player and combat.player.hp == RunState.START_HP - 15, "fight uses the run's player with carried-over HP")
	_check(combat.enemies.size() == 1, "first fight has the stop's enemy count")
	_check(combat.piles.draw_pile.size() + combat.piles.hand.size() == state.deck.size() or combat.phase == Combat.Phase.NOT_STARTED, "fight is built from the run's deck")
	combat.abandon()


# These push_error on purpose; that output is expected here.
func _test_start_combat_rejected_off_combat_stop() -> void:
	var state := _at_first_fight(3)
	_win_and_skip(state)
	_win_and_skip(state)
	_check(state.current_stop().type == RunState.StopType.REST, "setup: now at the rest stop")
	_check(state.start_combat() == null, "no fight can start at a rest stop")
	var other := _at_first_fight(3)
	other.complete_combat(true)
	_check(other.reward_pending() and other.start_combat() == null, "no fight can start while a reward is pending")
	var story := RunState.new(3)
	_check(story.start_combat() == null, "no fight can start at a story stop")


func _test_defeat_ends_run() -> void:
	var state := _at_first_fight(4)
	state.complete_combat(false)
	_check(state.finished and not state.escaped, "defeat ends the run without escape")
	_check(state.current_stop() == null and not state.reward_pending(), "no stop or reward after defeat")


func _test_reward_flow() -> void:
	var state := _at_first_fight(5)
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
	_check(state.reward_pending() and state.deck.size() == deck_before and state.stop_index == 1, "rejected reward changes nothing")
	_check(state.resolve_reward(choices[0]), "an offered card is accepted")
	_check(state.deck.size() == deck_before + 1 and state.deck.back() == choices[0], "taken reward is added to the deck")
	_check(not state.reward_pending() and state.stop_index == 2, "taking the reward moves to the next stop")
	_check(not state.resolve_reward(null), "no reward to resolve when none is pending")

	var skipper := _at_first_fight(5)
	skipper.complete_combat(true)
	var size := skipper.deck.size()
	_check(skipper.resolve_reward(null) and skipper.deck.size() == size and skipper.stop_index == 2, "skipping adds nothing and moves on")


func _test_rest() -> void:
	var state := _at_first_fight(6)
	_check(state.rest() == -1 and state.stop_index == 1, "rest does nothing at a combat stop")
	_win_and_skip(state)
	_win_and_skip(state)
	state.player.take_damage(30)
	var hp_before := state.player.hp
	_check(state.rest() == RunState.REST_HEAL and state.player.hp == hp_before + RunState.REST_HEAL, "rest heals and reports HP restored")
	_check(state.stop_index == 4, "rest moves to the next stop")

	var full := _at_first_fight(6)
	_win_and_skip(full)
	_win_and_skip(full)
	_check(full.rest() == 0 and full.player.hp == full.player.max_hp, "rest at full HP restores nothing and never overheals")


func _test_story_flow() -> void:
	var state := RunState.new(8)
	var beat := state.current_beat()
	_check(beat != null and not beat.title.is_empty() and not beat.text.is_empty(), "the opening story stop has a beat to show")
	_check(state.rest() == -1 and state.stop_index == 0, "rest does nothing at a story stop")
	_check(state.read_story() and state.stop_index == 1 and not state.finished, "reading the story advances to the next stop")
	_check(state.current_beat() == null, "no beat off a story stop")
	var index_before := state.stop_index
	_check(not state.read_story() and state.stop_index == index_before, "read_story is rejected off a story stop")
	state.complete_combat(true)
	_check(not state.read_story() and state.reward_pending(), "read_story is rejected while a reward is pending")
	# The final story stop sits before the last fight.
	var late := RunState.new(8)
	late.stop_index = 8
	_check(late.current_beat() != null and late.read_story() and late.stop_index == 9, "the late story stop reads and leads to the final fight")


# The missing beat logs push_error on purpose; that output is expected here.
func _test_story_stop_with_missing_beat_is_passable() -> void:
	var state := RunState.new(9)
	state.stops[0].beat_index = 999
	_check(state.current_beat() == null, "a missing beat reads as null")
	_check(state.read_story() and state.stop_index == 1, "a story stop with a missing beat is still passable")
	var last := RunState.new(9)
	last.stops = [RunState.Stop.new(RunState.StopType.STORY, 0, -1)]
	_check(last.read_story() and last.finished and last.escaped, "a missing-beat story stop at the end still finishes the run")


func _test_story_content_loaders() -> void:
	_check(StoryContent.beat_count() > 0, "there are story beats")
	for i in StoryContent.beat_count():
		var beat := StoryContent.beat(i)
		_check(beat != null and beat is StoryBeat and not beat.title.is_empty() and not beat.text.is_empty() and not beat.button_text.is_empty(), "story beat %d loads typed with title, text and button" % i)
	_check(StoryContent.beat(-1) == null, "negative beat index returns null")
	_check(StoryContent.beat(StoryContent.beat_count()) == null, "out-of-range beat index returns null")
	_check(StoryBeat.new().button_text == "Continue", "beat button text defaults to Continue")


func _test_full_run_escapes() -> void:
	var state := RunState.new(7)
	var guard := 0
	while not state.finished and guard < 50:
		guard += 1
		match state.current_stop().type:
			RunState.StopType.COMBAT:
				_win_and_skip(state)
			RunState.StopType.STORY:
				state.read_story()
			RunState.StopType.VENDOR:
				state.leave_vendor()
			_:
				state.rest()
	_check(state.finished and state.escaped and state.stop_index == state.stops.size(), "winning every fight reaches the end and escapes")
	_check(state.current_stop() == null, "no current stop after the run is finished")


func _test_seed_determinism() -> void:
	var a := _at_first_fight(99)
	var b := _at_first_fight(99)
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


## Moves a run to the VENDOR stop (index 5) by winning/skipping and resting on the way.
func _at_vendor(rng_seed: int) -> RunState:
	var state := _at_first_fight(rng_seed)
	while state.current_stop().type != RunState.StopType.VENDOR:
		if state.current_stop().type == RunState.StopType.COMBAT:
			_win_and_skip(state)
		else:
			state.rest()
	return state


func _test_gold_from_wins() -> void:
	var state := _at_first_fight(11)
	_check(state.gold == 0, "a run starts with no gold")
	state.complete_combat(true)
	_check(state.gold == Vendor.gold_for_win(1), "a won solo fight pays its gold")
	state.resolve_reward(null)
	state.complete_combat(true)
	_check(state.gold == Vendor.gold_for_win(1) + Vendor.gold_for_win(2), "gold accumulates across wins")
	var loser := _at_first_fight(11)
	loser.complete_combat(false)
	_check(loser.gold == 0, "a lost fight pays nothing")


func _test_vendor_flow() -> void:
	var state := RunState.new(12)
	_check(state.vendor() == null and not state.leave_vendor(), "no vendor off a vendor stop")
	_check(not state.vendor_buy_card(0).ok and not state.vendor_buy_heal().ok and not state.vendor_remove_card(0).ok, "vendor purchases fail off a vendor stop")

	state = _at_vendor(12)
	_check(state.current_stop().type == RunState.StopType.VENDOR, "setup: at the vendor stop")
	var vendor := state.vendor()
	_check(vendor != null and state.vendor() == vendor, "asking for the vendor again does not re-roll it")
	_check(vendor.gold == state.gold, "the vendor starts with the run's gold")

	# Gold is set before the vendor is first asked for, because the vendor takes it at creation.
	state = _at_vendor(12)
	state.gold = 100
	_check(state.vendor() != null and state.vendor().gold == 100, "setup: fresh vendor with 100 gold")
	var deck_before := state.deck.size()
	var bought := state.vendor_buy_card(0)
	_check(bought.ok and state.deck.size() == deck_before + 1 and state.gold == 100 - bought.spent, "buying a card adds it to the run's deck and syncs gold")
	_check(not state.vendor_buy_card(0).ok and state.gold == 100 - bought.spent and state.deck.size() == deck_before + 1, "buying the same offer twice is refused and changes nothing")

	var removed := state.vendor_remove_card(0)
	_check(removed.ok and state.deck.size() == deck_before and state.gold == 100 - bought.spent - removed.spent, "removing a card shrinks the run's deck and syncs gold")

	state.player.take_damage(30)
	var hp_before := state.player.hp
	var healed := state.vendor_buy_heal()
	_check(healed.ok and state.player.hp == hp_before + healed.healed and healed.healed > 0, "healing restores the run's player")

	var stop_before := state.stop_index
	_check(state.leave_vendor() and state.stop_index == stop_before + 1, "leaving moves to the next stop")
	_check(state.vendor() == null, "no vendor after leaving")

	var poor := _at_vendor(13)
	poor.gold = 0
	_check(poor.vendor() != null and not poor.vendor_buy_card(0).ok and poor.gold == 0, "with no gold every purchase is refused, gold stays at 0")


# These misuse the API on purpose; the push_error output is expected here.
func _test_complete_combat_preconditions() -> void:
	var state := _at_first_fight(21)
	state.complete_combat(true)
	var gold := state.gold
	state.complete_combat(true)
	_check(state.gold == gold, "a second victory while the reward is pending pays nothing")
	state.complete_combat(false)
	_check(not state.finished and state.reward_pending(), "a defeat cannot be recorded while a reward is pending")

	var story := RunState.new(22)
	story.complete_combat(true)
	_check(story.gold == 0 and not story.reward_pending() and story.stop_index == 0, "complete_combat at a story stop changes nothing")

	var rest_stop := _at_first_fight(23)
	_win_and_skip(rest_stop)
	_win_and_skip(rest_stop)
	var hp := rest_stop.player.hp
	var gold_at_rest := rest_stop.gold
	_check(rest_stop.current_stop().type == RunState.StopType.REST, "setup: at the rest stop")
	rest_stop.complete_combat(true)
	_check(rest_stop.gold == gold_at_rest and not rest_stop.reward_pending() and rest_stop.stop_index == 3, "a victory cannot be recorded at a rest stop (the rest cannot be skipped)")
	_check(rest_stop.player.hp == hp, "rest stop untouched")

	var dead := _at_first_fight(24)
	dead.complete_combat(false)
	dead.complete_combat(true)
	_check(dead.finished and not dead.escaped and not dead.reward_pending() and dead.gold == 0, "nothing can be recorded after a defeat")
	_check(not dead.resolve_reward(null), "no reward can be resolved after a defeat")

	var winner := RunState.new(25)
	var guard := 0
	while not winner.finished and guard < 50:
		guard += 1
		match winner.current_stop().type:
			RunState.StopType.COMBAT:
				_win_and_skip(winner)
			RunState.StopType.STORY:
				winner.read_story()
			RunState.StopType.VENDOR:
				winner.leave_vendor()
			_:
				winner.rest()
	var gold_done := winner.gold
	_check(winner.finished and winner.escaped, "setup: an escaped run")
	winner.complete_combat(false)
	winner.complete_combat(true)
	_check(winner.escaped and winner.gold == gold_done and winner.stop_index == winner.stops.size() and not winner.reward_pending(), "a finished run cannot be rewritten or pushed past the line")
	_check(not winner.resolve_reward(null), "no reward after the run finished")


func _test_vendor_gold_and_stale_state() -> void:
	var state := _at_vendor(26)
	var vendor := state.vendor()
	state.gold = 100  # changed after the vendor already exists
	var bought := state.vendor_buy_card(0)
	_check(bought.ok and state.gold == 100 - bought.spent, "gold changed while a vendor exists is honoured, not overwritten")
	state.leave_vendor()
	_check(state.vendor() == null, "the vendor is gone after leaving")
	_check(vendor != null and state.stop_index == 6, "setup: moved past the vendor stop")


func _test_start_combat_twice_releases_first() -> void:
	var state := _at_first_fight(27)
	var first := state.start_combat()
	var second := state.start_combat()
	_check(first != null and second != null and first != second, "asking again builds a new fight")
	_check(first.phase == Combat.Phase.ENDED, "the previous fight is abandoned")
	_check(state.player.changed.get_connections().size() == 1, "only the current fight stays linked to the player")
	second.abandon()


func _test_rewards_rolled_eagerly_and_copied() -> void:
	var shown := _at_first_fight(31)
	var skipped := _at_first_fight(31)
	shown.complete_combat(true)
	shown.reward_choices()
	shown.resolve_reward(null)
	skipped.complete_combat(true)
	skipped.resolve_reward(null)
	var fight_shown := shown.start_combat()
	var fight_skipped := skipped.start_combat()
	var same := fight_shown != null and fight_skipped != null and fight_shown.enemies.size() == fight_skipped.enemies.size()
	if same:
		for i in fight_shown.enemies.size():
			same = same and fight_shown.enemies[i].display_name == fight_skipped.enemies[i].display_name
	_check(same, "a seed plays out the same whether or not the reward screen was shown")
	if fight_shown != null:
		fight_shown.abandon()
	if fight_skipped != null:
		fight_skipped.abandon()

	var state := _at_first_fight(32)
	state.complete_combat(true)
	var choices := state.reward_choices()
	choices.clear()
	_check(state.reward_choices().size() == RunState.REWARD_CHOICES, "mutating the returned choices does not change the offer")
