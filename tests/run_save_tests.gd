extends RefCounted
## Tests for run save/restore (run/run_save.gd). Returns the failure count; the
## suite in run_tests.gd adds it to its own. Files go to a scratch path under
## user://, never the real run_save.json.

const TEST_PATH := "user://run_save_test.json"

var _failures := 0


func run() -> int:
	_failures = 0
	_test_round_trip_equal_state()
	_test_resume_has_equal_future()
	_test_file_round_trip_and_delete()
	_test_missing_file()
	_test_corrupt_files()
	_test_version_mismatch()
	_test_bad_fields()
	_test_save_refused_mid_flight()
	_cleanup()
	return _failures


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _cleanup() -> void:
	RunSave.delete(TEST_PATH)
	RunSave.delete(TEST_PATH + ".tmp")


func _write(text: String) -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Plays `state` until it has passed `stops` stops (or finished), buying one card at
## vendors and taking the first reward, and returns a log of everything random it saw.
func _walk(state: RunState, stops: int) -> Array:
	var log: Array = []
	while not state.finished and state.stop_index < stops:
		match state.current_stop().type:
			RunState.StopType.COMBAT:
				var combat := state.start_combat()
				combat.start()
				var names: Array = []
				for enemy in combat.enemies:
					names.append(enemy.display_name)
				var hand: Array = []
				for card in combat.piles.hand:
					hand.append(String(card.id))
				log.append([names, hand])
				combat.abandon()
				state.complete_combat(true)
				if state.reward_pending():
					var choices := state.reward_choices()
					var ids: Array = []
					for card in choices:
						ids.append(String(card.id))
					log.append(ids)
					state.resolve_reward(choices[0])
			RunState.StopType.VENDOR:
				var offers: Array = []
				for offer in state.vendor().offers():
					offers.append([String(offer["card"].id), offer["price"]])
				log.append(offers)
				state.vendor_buy_card(0)
				state.leave_vendor()
			RunState.StopType.REST:
				state.rest()
			_:
				state.read_story()
	return log


## Round-trips through JSON text, as a real save file does.
func _clone(state: RunState) -> RunState:
	var json := JSON.new()
	json.parse(JSON.stringify(RunSave.to_dict(state)))
	return RunSave.from_dict(json.data).run


func _test_round_trip_equal_state() -> void:
	var state := RunState.new(7)
	_walk(state, 4)
	state.player.hp = 17
	var copy := _clone(state)
	_check(copy != null, "a valid dict restores a run")
	if copy == null:
		return
	_check(RunSave.to_dict(copy) == RunSave.to_dict(state), "restored run serialises to the same dict")
	_check(copy.player.hp == 17 and copy.player.max_hp == state.player.max_hp, "hp restored")
	_check(copy.gold == state.gold and copy.stop_index == state.stop_index and copy.deck.size() == state.deck.size(), "gold, stop and deck restored")
	_check(copy.at_stop_boundary(), "restored run is at a stop boundary")


func _test_resume_has_equal_future() -> void:
	for cut in [0, 1, 2, 6, 9]:
		var original := RunState.new(1234)
		_walk(original, cut)
		var resumed := _clone(original)
		var future_a := _walk(original, 99)
		var future_b := _walk(resumed, 99)
		_check(future_a == future_b and not future_a.is_empty(), "same future after resuming at stop %d" % cut)
		_check(RunSave.to_dict(original) == RunSave.to_dict(resumed), "same end state after resuming at stop %d" % cut)
		_check(original.finished == resumed.finished and original.escaped == resumed.escaped, "same outcome after resuming at stop %d" % cut)


func _test_file_round_trip_and_delete() -> void:
	var state := RunState.new(5)
	_walk(state, 2)
	_check(RunSave.save(state, TEST_PATH) == "", "save writes the file")
	_check(not FileAccess.file_exists(TEST_PATH + ".tmp"), "no temp file left behind")
	var loaded := RunSave.load_file(TEST_PATH)
	_check(loaded.run != null and loaded.error == "", "saved file loads")
	if loaded.run != null:
		_check(RunSave.to_dict(loaded.run) == RunSave.to_dict(state), "file round trip keeps the state")
	_check(RunSave.delete(TEST_PATH) == "" and not FileAccess.file_exists(TEST_PATH), "delete removes the file")
	_check(RunSave.delete(TEST_PATH) == "", "deleting a missing save is fine")


func _test_missing_file() -> void:
	_cleanup()
	var loaded := RunSave.load_file(TEST_PATH)
	_check(loaded.run == null and loaded.missing, "a missing save is reported as missing, not as an error")


func _test_corrupt_files() -> void:
	for text in ["", "{", "not json", "[1,2]", "42", "null", "{\"version\":1}", "\u0001\u0002"]:
		_write(text)
		var loaded := RunSave.load_file(TEST_PATH)
		_check(loaded.run == null and not loaded.missing and loaded.error != "", "corrupt save %s falls back with a message" % JSON.stringify(text))
	_cleanup()


func _test_version_mismatch() -> void:
	var state := RunState.new(3)
	for bad in [0, 2, -1, "1", null, 1.5]:
		var data := RunSave.to_dict(state)
		data["version"] = bad
		var result := RunSave.from_dict(data)
		_check(result.run == null and result.error != "", "version %s is rejected" % str(bad))
	var no_version := RunSave.to_dict(state)
	no_version.erase("version")
	_check(RunSave.from_dict(no_version).run == null, "missing version is rejected")


func _test_bad_fields() -> void:
	var state := RunState.new(3)
	var cases := {
		"hp": [0, -5, 9999, "x", null, 3.5],
		"max_hp": [0, -1, 100000, "x"],
		"gold": [-1, 99999999, "x", null],
		"stop_index": [-1, 12, 500, "x", null],
		"rng_state": [12, "abc", "", null],
		"deck": [[], "x", ["no_such_card"], [5], null],
	}
	for key in cases:
		for bad in cases[key]:
			var data := RunSave.to_dict(state)
			data[key] = bad
			var result := RunSave.from_dict(data)
			_check(result.run == null and result.error != "", "%s = %s is rejected" % [key, JSON.stringify(bad)])
	var big := RunSave.to_dict(state)
	var ids: Array = []
	for i in RunSave.MAX_DECK + 1:
		ids.append("shove")
	big["deck"] = ids
	_check(RunSave.from_dict(big).run == null, "an oversized deck is rejected")
	_check(RunSave.from_dict("text").run == null and RunSave.from_dict(null).run == null, "a non-object is rejected")


func _test_save_refused_mid_flight() -> void:
	var state := RunState.new(3)
	state.read_story()
	var combat := state.start_combat()
	_check(RunSave.save(state, TEST_PATH) != "" and not FileAccess.file_exists(TEST_PATH), "no save while a fight is in flight")
	combat.abandon()
	state.complete_combat(true)
	_check(RunSave.save(state, TEST_PATH) != "" and not FileAccess.file_exists(TEST_PATH), "no save while a reward is pending")
	var done := RunState.new(3)
	done.finished = true
	_check(RunSave.save(done, TEST_PATH) != "", "no save of a finished run")
