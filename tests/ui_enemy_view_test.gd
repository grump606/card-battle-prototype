extends SceneTree
## Headless test for EnemyView and its place in the battle screen: a view builds for every enemy
## (and an unknown one), the animation is deterministic and only runs while visible, the target and
## defeated states follow the fight, and 1 to 3 panels sit centered with the hand below.
## Run via scripts/check.ps1.

var fails := 0

func check(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		printerr("FAIL: " + msg)
	else:
		print("ok: " + msg)


func _unit(path: String) -> EnemyUnit:
	return EnemyUnit.new(load(path) as EnemyData)


func _combat_of(paths: Array) -> Combat:
	var datas: Array[EnemyData] = []
	for path in paths:
		datas.append(load(path) as EnemyData)
	return Combat.create(Combatant.new("Wanderer", 40), StarterContent.extended_deck(), datas, 7)


func _battle(paths: Array) -> Control:
	var scene: Control = (load("res://battle.tscn") as PackedScene).instantiate()
	scene.external_combat = _combat_of(paths)
	root.add_child(scene)
	return scene


func _initialize() -> void:
	var holder := Control.new()
	root.add_child(holder)

	# Every enemy in the game, plus names the art does not know, builds and draws without errors.
	var keys := {}
	var all_paths: Array[String] = []
	for file in DirAccess.get_files_at("res://data/enemies"):
		if file.ends_with(".tres"):
			all_paths.append("res://data/enemies/" + file)
	for path in all_paths:
		var unit := _unit(path)
		var view := EnemyView.new()
		holder.add_child(view)
		view.set_enemy(unit)
		keys[view.art_key] = true
		check(view.art_key != &"ghost", "%s has its own silhouette" % unit.display_name)
		check(view.is_boss == (unit.display_name == "The Conductor"), "%s: only the Conductor gets the boss frame" % unit.display_name)
		check(view.custom_minimum_size == (EnemyView.BOSS_BASE if view.is_boss else EnemyView.BASE), "%s panel size" % unit.display_name)
	check(all_paths.size() >= 8 and keys.size() == all_paths.size(), "all %d enemies have a distinct silhouette" % all_paths.size())
	var unknown := EnemyView.new()
	holder.add_child(unknown)
	unknown.set_enemy(EnemyUnit.new(EnemyData.make("Nobody Knows", 9, [] as Array[CardEffect])))
	check(unknown.art_key == &"ghost" and not unknown.is_boss, "an unknown enemy gets the generic ghost, with no intent")
	var empty := EnemyView.new()
	holder.add_child(empty)
	empty.refresh()
	empty.advance(0.1)
	await process_frame
	await process_frame
	check(true, "views with and without an enemy draw")

	# Animation: advance moves it, a hidden or detached view does not, and the same steps give the same state.
	var a := EnemyView.new()
	var b := EnemyView.new()
	holder.add_child(a)
	holder.add_child(b)
	a.set_enemy(_unit("res://data/enemies/cinder_hound.tres"))
	b.set_enemy(_unit("res://data/enemies/cinder_hound.tres"))
	var t0 := a.time
	var breath0 := a.breath()
	a.advance(0.4)
	check(a.time > t0 and a.breath() != breath0, "advance changes the animation state")
	b.advance(0.4)
	check(b.breath() == a.breath() and b.glow_level() == a.glow_level(), "the same steps give the same animation")
	check(a.glow_level() >= 0.6 and a.glow_level() <= 1.0, "glow stays in its range")
	var phased := EnemyView.new()
	phased.phase = 1.9
	holder.add_child(phased)
	phased.set_enemy(_unit("res://data/enemies/cinder_hound.tres"))
	phased.advance(0.4)
	check(phased.breath() != a.breath(), "a phase offset desynchronises two enemies")
	a.visible = false
	var frozen := a.time
	a.advance(1.0)
	check(a.time == frozen, "a hidden view does not advance")
	var detached := EnemyView.new()
	detached.advance(1.0)
	check(detached.time == 0.0, "a view outside the tree does not advance")
	a.visible = true

	# Hit flash, defeated fade and the status chips follow the unit.
	var hurt := _unit("res://data/enemies/lost_shade.tres")
	var hv := EnemyView.new()
	holder.add_child(hv)
	hv.set_enemy(hurt)
	hurt.take_damage(5)
	hv.refresh()
	check(hv._flash > 0.0, "losing HP starts a hit flash")
	hv.advance(1.0)
	check(hv._flash == 0.0, "the hit flash fades")
	hurt.take_damage(9999)
	hv.refresh()
	check(hv.is_defeated() and hv.fade < 1.0, "a death starts the defeated fade")
	hv.advance(2.0)
	check(hv.fade == 1.0, "the defeated fade completes")
	hv.play_attack()
	check(hv._lunge == 1.0, "play_attack starts a lunge")
	var chips_unit := _unit("res://data/enemies/pale_whisperer.tres")
	var cv := EnemyView.new()
	holder.add_child(cv)
	cv.set_enemy(chips_unit)
	check(cv.status_chips().is_empty(), "no chips without statuses")
	chips_unit.apply_status(Combatant.Status.EXPOSED, 2)
	chips_unit.apply_status(Combatant.Status.HAUNTED, 3)
	chips_unit.hold = 4
	chips_unit.thorns = 5
	var texts: Array[String] = []
	for chip in cv.status_chips():
		texts.append(chip.text)
	check(texts == ["Exposed 2", "Haunt 3", "Hold 4", "Thorns 5"], "chips show Exposed, Haunt, Hold and Thorns with their numbers: %s" % str(texts))
	check(EnemyView.find_all(holder).size() >= 8, "find_all finds the views")

	# Chip layout: with 0 to 4 statuses, on every enemy, chips stay inside the panel and the portrait
	# window and never touch the portrait's subject area (the middle of the window).
	for path in all_paths:
		var lay_unit := _unit(path)
		var lay := EnemyView.new()
		holder.add_child(lay)
		lay.set_enemy(lay_unit)
		var name_ := lay_unit.display_name
		var panel := Rect2(0, EnemyView.MARKER, lay.custom_minimum_size.x, EnemyView.BASE.y - EnemyView.MARKER)
		var subject := lay.portrait_subject_rect()
		check(lay.window_rect().encloses(subject) and subject.size.x >= 100.0, "%s: the portrait subject area is inside its window" % name_)
		for count in 5:
			lay_unit.hold = 0
			lay_unit.thorns = 0
			lay_unit.clear_statuses()
			if count >= 1:
				lay_unit.apply_status(Combatant.Status.EXPOSED, 2)
			if count >= 2:
				lay_unit.apply_status(Combatant.Status.HAUNTED, 3)
			if count >= 3:
				lay_unit.hold = 4
			if count >= 4:
				lay_unit.thorns = 12
			var rects := lay.chip_rects()
			var ok := rects.size() == count and lay.status_chips().size() == count
			for i in rects.size():
				ok = ok and not rects[i].intersects(subject) and panel.encloses(rects[i]) and lay.window_rect().encloses(rects[i])
				for j in i:
					ok = ok and not rects[i].intersects(rects[j])
			check(ok, "%s with %d status(es): chips clear of the portrait, inside the panel, not overlapping" % [name_, count])
		lay.queue_free()

	# In the battle screen: the target marker follows the target, the dead are skipped, clicks select.
	var trio: Array[String] = ["res://data/enemies/skittering_wisp.tres", "res://data/enemies/pale_whisperer.tres", "res://data/enemies/mourning_crow.tres"]
	var battle := _battle(trio)
	await process_frame
	await process_frame
	var views := EnemyView.find_all(battle._enemy_row)
	check(views.size() == 3, "one enemy view per enemy")
	for i in views.size():
		check(views[i].unit == battle._combat.enemies[i], "enemy view %d shows its enemy" % i)
	check(views[0].targeted and not views[1].targeted and not views[2].targeted, "the first enemy starts targeted")
	battle._select_target(2)
	check(views[2].targeted and not views[0].targeted, "targeted follows _select_target")
	views[1].pressed.emit()
	check(battle._target_index == 1 and views[1].targeted and not views[2].targeted, "clicking a panel targets that enemy")
	var before: int = battle._combat.enemies[1].hp
	battle._combat.enemies[1].apply_status(Combatant.Status.EXPOSED, 2)
	battle._refresh()
	check(battle._enemy_row.get_child(1).tooltip_text.contains("2 more turns") and battle._enemy_row.get_child(0).tooltip_text == "", "the status tooltip is on the panel")
	check(EnemyView.find_all(battle._enemy_row)[1] == views[1], "a refresh keeps the same views")
	battle._combat.enemies[1].take_damage(9999)
	battle._refresh()
	check(before > 0 and views[1].is_defeated() and not views[1].targeted and views[1].tooltip_text == "", "a defeated enemy is shown defeated, not targeted")
	check(battle._target_index != 1 and views[battle._target_index].targeted, "the target moved to a living enemy")
	var target_before: int = battle._target_index
	views[1].pressed.emit()
	check(battle._target_index == target_before, "a defeated panel cannot be selected")
	battle.queue_free()
	await process_frame

	# Layout at the project's 1152x648: 1 to 3 panels centered, hand and buttons still on screen.
	var enemies_by_count := [
		["res://data/enemies/the_conductor.tres"],
		["res://data/enemies/gate_warden.tres", "res://data/enemies/lost_shade.tres"],
		trio,
	]
	for paths in enemies_by_count:
		var scene := _battle(paths)
		for i in 3:
			await process_frame
		var shown := EnemyView.find_all(scene._enemy_row)
		var row_rect: Rect2 = scene._enemy_row.get_global_rect()
		var left := INF
		var right := -INF
		for v in shown:
			left = minf(left, v.get_global_rect().position.x)
			right = maxf(right, v.get_global_rect().end.x)
		check(shown.size() == paths.size() and absf((left + right) / 2.0 - row_rect.get_center().x) <= 1.0, "%d panel(s) are centered in the row" % paths.size())
		check(left >= row_rect.position.x and right <= row_rect.end.x, "%d panel(s) fit in the row" % paths.size())
		var hand_rect: Rect2 = scene._hand_box.get_global_rect()
		var hand_views := CardView.find_all(scene._hand_box)
		check(not hand_views.is_empty() and row_rect.end.y <= hand_rect.position.y, "%d enemies: the enemy row sits above the hand" % paths.size())
		var screen := Rect2(Vector2.ZERO, Vector2(scene.size))
		var all_on_screen := true
		for card in hand_views:
			all_on_screen = all_on_screen and screen.encloses(card.get_global_rect())
		check(all_on_screen and screen.encloses(scene._end_turn_button.get_global_rect()), "%d enemies: the hand and End Turn fit on screen" % paths.size())
		scene.queue_free()
		await process_frame
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
