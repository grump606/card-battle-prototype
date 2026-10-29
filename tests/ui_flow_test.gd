extends SceneTree
## Headless test of the run screen glue (run.gd + the battle embedded by it): it
## plays whole runs through the real run.tscn buttons, with every enemy set to 1 HP
## so a run can finish, and checks that each hand-off actually happens. Catches
## a view that forgets to call into RunState (the rules tests cannot see that).
## Run via scripts/check.ps1.

var _failures := 0


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _buttons(node: Node, out: Array) -> void:
	if node is Button and (node as Button).visible:
		out.append(node)
	for child in node.get_children():
		_buttons(child, out)


func _first_enabled(body: Node) -> Button:
	var found: Array = []
	_buttons(body, found)
	for button in found:
		if not (button as Button).disabled:
			return button
	return null


func _find(body: Node, prefix: String) -> Button:
	var found: Array = []
	_buttons(body, found)
	for button in found:
		if (button as Button).text.begins_with(prefix) and not (button as Button).disabled:
			return button
	return null


func _initialize() -> void:
	var scene: Control = load("res://run.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var body: Control = scene.get_node("%Body")
	var header: Label = scene.get_node("%HeaderLabel")
	var run_state: RunState = scene._run

	var fights_ended := 0
	var rewards := 0
	var vendor_visits := 0
	var stories := 0
	var rests := 0
	var guard := 0
	var last_stop := -1
	var stuck := 0
	while not run_state.finished and guard < 4000:
		guard += 1
		await process_frame
		run_state = scene._run
		# Frames spent at one stop, whatever the panel: a fight takes a few dozen,
		# so hundreds means a hand-off is not happening and the loop would spin.
		if run_state.stop_index == last_stop:
			stuck += 1
		else:
			stuck = 0
		last_stop = run_state.stop_index
		var battle: Node = body.get_child(0) if body.get_child_count() > 0 else null
		if battle != null and battle.has_method("_attach"):
			var combat: Combat = battle._combat
			if combat == null:
				continue
			if combat.turn == 1 and combat.phase == Combat.Phase.PLAYER_TURN:
				for enemy in combat.enemies:
					enemy.hp = 1
			if combat.phase == Combat.Phase.PLAYER_TURN:
				var played := false
				for i in combat.piles.hand.size():
					if combat.can_play(i):
						battle._play_hand_card(i)
						played = true
						break
				if not played:
					battle._on_end_turn_pressed()
			elif combat.phase == Combat.Phase.ENDED:
				fights_ended += 1
				var continue_button: Button = battle._new_fight_button
				_check(continue_button.visible and continue_button.text == "Continue", "a finished embedded fight shows Continue")
				_check(battle._result_label.text != "", "a finished fight shows its result")
				var stop_before := run_state.stop_index
				continue_button.pressed.emit()
				await process_frame
				_check(scene._run.reward_pending() or scene._run.stop_index > stop_before, "Continue hands the result to the run")
			continue
		var stop_type: int = run_state.current_stop().type
		if run_state.reward_pending():
			rewards += 1
			_check(header.text.contains("Reward"), "the header says Reward while a reward is pending")
			var deck_before := run_state.deck.size()
			var pick := _first_enabled(body)
			_check(pick != null, "the reward panel offers a choice")
			var pick_text := pick.text  # read first: pressing rebuilds the panel and frees this button
			pick.pressed.emit()
			await process_frame
			_check(scene._run.deck.size() == deck_before + 1 or pick_text == "Skip", "picking a reward adds the card")
		elif stop_type == RunState.StopType.VENDOR:
			vendor_visits += 1
			_check(header.text.contains("Gold %d" % run_state.gold), "the header shows the run's gold")
			var gold_before := run_state.gold
			var buy: Button = null
			var found: Array = []
			_buttons(body, found)
			for button in found:
				var text: String = (button as Button).text
				if not (button as Button).disabled and text.contains(" gold") and not text.begins_with("Remove") and not text.begins_with("Heal"):
					buy = button
					break
			if buy != null:
				var deck_size := run_state.deck.size()
				buy.pressed.emit()
				await process_frame
				_check(scene._run.deck.size() == deck_size + 1 and scene._run.gold < gold_before, "buying at the vendor panel adds a card and spends gold")
			_find(body, "Leave").pressed.emit()
		elif stop_type == RunState.StopType.REST:
			rests += 1
			var hp_before := run_state.player.hp
			_first_enabled(body).pressed.emit()
			await process_frame
			_check(scene._run.player.hp >= hp_before and scene._run.stop_index > 0, "the rest button rests")
		else:
			stories += 1
			_first_enabled(body).pressed.emit()
		if stuck > 400:
			break

	run_state = scene._run
	_check(guard < 4000 and stuck <= 400, "the run never got stuck at one stop")
	_check(run_state.finished and run_state.escaped, "the run finished with an escape")
	_check(run_state.stop_index == run_state.stops.size(), "every stop was passed")
	_check(fights_ended == 5 and rewards == 5, "five fights ended and five rewards were resolved (%d, %d)" % [fights_ended, rewards])
	_check(vendor_visits == 1 and rests == 2 and stories == 2, "one vendor, two rests and two story stops were visited (%d, %d, %d)" % [vendor_visits, rests, stories])
	_check(_find(body, "New Run") != null, "the end card offers New Run")
	scene._new_run()
	await process_frame
	_check(scene._run.stop_index == 0 and not scene._run.finished and scene._run.gold == 0, "New Run starts a fresh run")
	_check(body.get_child_count() == 1, "New Run leaves exactly one panel in the body")

	print("UI FLOW FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
