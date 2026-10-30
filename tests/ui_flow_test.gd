extends SceneTree
## Headless test of the run screen glue (run.gd + the battle embedded by it): it
## plays whole runs through the real run.tscn buttons, with every enemy set to 1 HP
## so a run can finish, and checks that each hand-off actually happens. Catches
## a view that forgets to call into RunState (the rules tests cannot see that).
## Run via scripts/check.ps1.

## Scratch save path: the developer's real user://run_save.json must never be touched.
var test_save := "user://ui_flow_test_save_%d.json" % OS.get_process_id()

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


func _all_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text + "\n"
	for child in node.get_children():
		text += _all_text(child)
	return text


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
	RunSave.delete(test_save)
	var scene: Control = load("res://run.tscn").instantiate()
	scene.save_path = test_save
	root.add_child(scene)
	await process_frame
	var body: Control = scene.get_node("%Body")
	var header: Label = scene.get_node("%HeaderLabel")

	# A new game starts on the character select screen.
	_check(scene._run == null and header.text.contains("Choose your passenger"), "a new game opens on the character select screen")
	_check(not scene._pause_button.visible, "no Pause button on the select screen")
	_check(_count_buttons(body, "Play as") == 3, "the select screen offers three characters")
	var select_text := _all_text(body)
	for id in StarterContent.character_ids():
		var character := StarterContent.character(id)
		_check(select_text.contains(character.display_name) and select_text.contains("%d HP" % character.max_hp) and select_text.contains(character.pitch), "the select screen shows %s with HP and pitch" % id)
	_check(select_text.contains("3 Shove") and select_text.contains("Starting deck"), "the select screen shows each starting deck")
	_find(body, "Play as The Deserter").pressed.emit()
	await process_frame
	_check(scene._run != null and scene._run.character.id == &"deserter" and scene._run.stop_index == 0, "picking the Deserter starts a Deserter run")
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
			var reward_buttons: Array = []
			_buttons(body, reward_buttons)
			var skip_label := "Skip (+%d gold)" % RunState.SKIP_GOLD
			var has_skip := false
			for button in reward_buttons:
				has_skip = has_skip or (button as Button).text == skip_label
			_check(has_skip, "the reward panel's Skip button shows its gold")
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
	_check(fights_ended == 5 and rewards == 4, "five fights ended and four rewards were resolved, the boss giving none (%d, %d)" % [fights_ended, rewards])
	_check(vendor_visits == 2 and rests == 2 and stories == 3, "two vendors, two rests and three story stops were visited (%d, %d, %d)" % [vendor_visits, rests, stories])
	_check(_find(body, "New Run") != null, "the end card offers New Run")
	_check(not FileAccess.file_exists(test_save), "the save is deleted when the run ends")
	var win_text := _all_text(body)
	_check(win_text.contains("Outcome: Escaped") and win_text.contains("Stops cleared: 12/12"), "the win summary shows outcome and stops cleared")
	_check(win_text.contains("Final HP: %d/%d" % [run_state.player.hp, run_state.player.max_hp]), "the win summary shows final HP")
	_check(win_text.contains("Deck: %d cards" % run_state.deck.size()) and win_text.contains("Gold: %d" % run_state.gold), "the win summary shows deck size and gold")
	_find(body, "New Run").pressed.emit()
	await process_frame
	_check(_count_buttons(body, "Play as") == 3 and header.text.contains("Choose your passenger"), "New Run on the end card opens the select screen")
	_find(body, "Play as The Pickpocket").pressed.emit()
	await process_frame
	_check(scene._run.character.id == &"pickpocket" and scene._run.player.max_hp == StarterContent.character(&"pickpocket").max_hp and scene._run.player.display_name == "The Pickpocket", "picking the Pickpocket starts a Pickpocket run")
	_check(scene._run.stop_index == 0 and not scene._run.finished and scene._run.gold == 0, "a character pick starts a fresh run")
	_check(body.get_child_count() == 1, "New Run leaves exactly one panel in the body")
	_check(FileAccess.file_exists(test_save), "a new run is saved at its first stop")

	# Defeat summary.
	var lost := RunState.new(2)
	lost.read_story()
	lost.gold = 21
	lost.player.hp = 0
	lost.finished = true
	scene._run = lost
	scene._show_stop()
	await process_frame
	var loss_text := _all_text(body)
	_check(loss_text.contains("Outcome: Defeated") and loss_text.contains("Stops cleared: 1/12") and loss_text.contains("Final HP: 0/%d" % lost.player.max_hp) and loss_text.contains("Gold: 21"), "the loss summary shows the right data")
	_check(not FileAccess.file_exists(test_save), "the save is deleted after a defeat")
	scene.queue_free()
	await process_frame

	# Continue: a valid save is offered, and Continue resumes exactly that run.
	var saved := RunState.new(77)
	saved.read_story()
	saved.gold = 9
	saved.player.hp = 30
	_check(RunSave.save(saved, test_save) == "", "the test run could be saved")
	var resumed_scene: Control = load("res://run.tscn").instantiate()
	resumed_scene.save_path = test_save
	root.add_child(resumed_scene)
	await process_frame
	var resumed_body: Control = resumed_scene.get_node("%Body")
	_check(resumed_scene._run == null and _find(resumed_body, "Continue") != null and _find(resumed_body, "New Run") != null, "a valid save offers Continue and New Run without starting")
	_find(resumed_body, "Continue").pressed.emit()
	await process_frame
	var resumed: RunState = resumed_scene._run
	_check(resumed != null and resumed.stop_index == 1 and resumed.gold == 9 and resumed.player.hp == 30, "Continue resumes the saved run")
	_check(resumed_body.get_child_count() == 1, "Continue shows exactly one panel")
	resumed_scene.queue_free()
	await process_frame

	# Every character can be picked, and the header then shows who is playing.
	for id in StarterContent.character_ids():
		var character := StarterContent.character(id)
		RunSave.delete(test_save)
		var pick_scene: Control = load("res://run.tscn").instantiate()
		pick_scene.save_path = test_save
		root.add_child(pick_scene)
		await process_frame
		_find(pick_scene.get_node("%Body"), "Play as %s" % character.display_name).pressed.emit()
		await process_frame
		var shown := (pick_scene.get_node("%HeaderLabel") as Label).text
		_check(shown.contains(character.display_name) and shown.contains("HP %d/%d" % [character.max_hp, character.max_hp]), "the header shows %s and its HP" % id)
		_check(pick_scene._run.deck.size() == 10 and pick_scene.get_node("%Body").get_child_count() == 1, "%s starts a run with a ten-card deck and one panel" % id)
		pick_scene.queue_free()
		await process_frame

	# A corrupt save falls back to a new run with a visible message.
	var bad := FileAccess.open(test_save, FileAccess.WRITE)
	bad.store_string("{ not json")
	bad.close()
	var bad_scene: Control = load("res://run.tscn").instantiate()
	bad_scene.save_path = test_save
	root.add_child(bad_scene)
	await process_frame
	_check(bad_scene._run == null and _count_buttons(bad_scene.get_node("%Body"), "Play as") == 3, "a corrupt save falls back to the select screen")
	_check((bad_scene.get_node("%HeaderLabel") as Label).text.contains("could not be loaded"), "a corrupt save shows a message")
	bad_scene.queue_free()
	await process_frame

	# Pause menu: opens over a fight, freezes it, and offers Continue, Save & Exit and New Run.
	RunSave.delete(test_save)
	var pause_scene: Control = load("res://run.tscn").instantiate()
	pause_scene.save_path = test_save
	var exits := [0]
	pause_scene.exit_callable = func() -> void: exits[0] += 1
	root.add_child(pause_scene)
	await process_frame
	_find(pause_scene.get_node("%Body"), "Play as The Medium").pressed.emit()
	await process_frame
	_check(pause_scene._run.character.id == &"medium", "setup: playing as the Medium")
	var pause_button: Button = pause_scene._pause_button
	var overlay: Control = pause_scene._pause_overlay
	_check(pause_button.visible and not overlay.visible, "a running run shows the Pause button and a closed menu")
	pause_scene._run.read_story()
	pause_scene._show_stop()
	await process_frame
	_check(pause_scene._run.current_stop().type == RunState.StopType.COMBAT, "setup: standing at a fight")
	var fight: Node = pause_scene.get_node("%Body").get_child(0)
	var energy_before: int = fight._combat.energy
	pause_button.pressed.emit()
	await process_frame
	_check(overlay.visible and pause_scene.get_tree().paused, "Pause opens the menu and pauses the tree")
	_check(_find(pause_scene._pause_box, "Continue") != null and _find(pause_scene._pause_box, "Save & Exit") != null and _find(pause_scene._pause_box, "New Run") != null, "the pause menu offers Continue, Save & Exit and New Run")
	_find(pause_scene._pause_box, "Continue").pressed.emit()
	await process_frame
	_check(not overlay.visible and not pause_scene.get_tree().paused, "Continue closes the menu and unpauses")
	_check(fight._combat.energy == energy_before, "the fight is untouched by pausing")

	# Escape toggles the menu.
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	pause_scene._unhandled_key_input(esc)
	_check(overlay.visible and pause_scene.get_tree().paused, "Escape opens the menu")
	pause_scene._unhandled_key_input(esc)
	_check(not overlay.visible and not pause_scene.get_tree().paused, "Escape closes it again")

	# Save & Exit mid-fight keeps the stop-start save and exits; it refuses with no save.
	pause_button.pressed.emit()
	await process_frame
	RunSave.delete(test_save)
	_find(pause_scene._pause_box, "Save & Exit").pressed.emit()
	await process_frame
	_check(exits[0] == 0 and _all_text(pause_scene._pause_box).contains("No save to resume"), "Save & Exit refuses to exit when there is no save to resume from")
	_set_paused_off(pause_scene)
	pause_scene._run.complete_combat(true)
	pause_scene._run.resolve_reward(null)
	pause_scene._show_stop()
	await process_frame
	var at_next: int = pause_scene._run.stop_index
	pause_button.pressed.emit()
	await process_frame
	_find(pause_scene._pause_box, "Save & Exit").pressed.emit()
	await process_frame
	var after_exit := RunSave.load_file(test_save)
	_check(exits[0] == 1 and after_exit.run != null and after_exit.run.stop_index == at_next, "Save & Exit writes the save and exits")
	_set_paused_off(pause_scene)

	# New Run asks first, and Cancel backs out.
	pause_button.pressed.emit()
	await process_frame
	var stop_before_new: int = pause_scene._run.stop_index
	_find(pause_scene._pause_box, "New Run").pressed.emit()
	await process_frame
	_check(_all_text(pause_scene._pause_box).contains("Abandon this run") and pause_scene._run.stop_index == stop_before_new, "New Run asks for confirmation first")
	_find(pause_scene._pause_box, "Cancel").pressed.emit()
	await process_frame
	_check(_find(pause_scene._pause_box, "Continue") != null and pause_scene._run.stop_index == stop_before_new, "Cancel returns to the pause menu with the run intact")
	_find(pause_scene._pause_box, "New Run").pressed.emit()
	await process_frame
	_find(pause_scene._pause_box, "Yes").pressed.emit()
	await process_frame
	_check(not overlay.visible and not pause_scene.get_tree().paused and _count_buttons(pause_scene.get_node("%Body"), "Play as") == 3, "confirming closes the menu and opens the select screen")
	_find(pause_scene.get_node("%Body"), "Play as The Deserter").pressed.emit()
	await process_frame
	_check(pause_scene._run.stop_index == 0 and pause_scene._run.character.id == &"deserter", "picking a character after abandoning starts a fresh run")

	# No Pause button once the run is over.
	var done := RunState.new(4)
	done.finished = true
	pause_scene._run = done
	pause_scene._show_stop()
	await process_frame
	_check(not pause_button.visible, "the Pause button is hidden on the end card")
	pause_scene.queue_free()
	await process_frame

	RunSave.delete(test_save)

	print("UI FLOW FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _set_paused_off(scene: Control) -> void:
	scene._set_paused(false)


func _count_buttons(node: Node, prefix: String) -> int:
	var found: Array = []
	_buttons(node, found)
	var count := 0
	for button in found:
		if (button as Button).text.begins_with(prefix):
			count += 1
	return count
