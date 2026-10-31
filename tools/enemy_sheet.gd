extends SceneTree
## Screenshots the enemy art: a contact sheet of every enemy, a sheet of the panel states, and
## the battle screen with 1, 2 and 3 enemies and the boss fight. Needs a rendering window (not
## --headless):
##   godot --path . -s res://tools/enemy_sheet.gd -- <output dir>
## Default output is user://enemy_sheets. The battle shots use the project's 1152x648 window.

const GAP := 12
const SHEET_SIZE := Vector2i(1180, 700)

var out_dir := "user://enemy_sheets"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _save_sheet(_all_enemies_sheet(), "enemies_all.png")
	await _save_sheet(_states_sheet(), "enemies_states.png")
	await _save_sheet(_chips_sheet(), "enemies_chips.png")
	await _battle_shots()
	quit()


func _paths() -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at("res://data/enemies"):
		if file.ends_with(".tres"):
			paths.append("res://data/enemies/" + file)
	return paths


func _unit(path: String) -> EnemyUnit:
	return EnemyUnit.new(load(path) as EnemyData)


func _view(unit: EnemyUnit, seconds := 0.0, targeted := false) -> EnemyView:
	var view := EnemyView.new()
	view.set_enemy(unit)
	view.set_targeted(targeted)
	view.set_meta("seconds", seconds)
	return view


func _label(text: String, size := 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	return label


func _all_enemies_sheet() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	for path in _paths():
		grid.add_child(_view(_unit(path), 0.9))
	return grid


## Normal, targeted with statuses, hit flash and defeated, for a small and a big enemy.
func _states_sheet() -> Control:
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 6)
	for path in ["res://data/enemies/cinder_hound.tres", "res://data/enemies/the_conductor.tres"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", GAP)
		row.add_child(_view(_unit(path), 0.5))
		var marked := _unit(path)
		marked.gain_block(8)
		marked.apply_status(Combatant.Status.EXPOSED, 2)
		marked.apply_status(Combatant.Status.HAUNTED, 3)
		marked.hold = 4
		marked.thorns = 2
		marked.hp = marked.max_hp * 2 / 3
		row.add_child(_view(marked, 1.3, true))
		var hit := _unit(path)
		var hit_view := _view(hit, 0.2)
		hit.take_damage(6)
		hit_view.refresh()
		row.add_child(hit_view)
		var dead := _unit(path)
		dead.take_damage(9999)
		row.add_child(_view(dead, 2.0))
		root_box.add_child(row)
	return root_box


## Status chips: 0, 2 and 4 statuses on a small enemy, a tall one and the Conductor's wider panel.
func _chips_sheet() -> Control:
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 6)
	for path in ["res://data/enemies/cinder_hound.tres", "res://data/enemies/pale_whisperer.tres", "res://data/enemies/the_conductor.tres"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", GAP)
		for count in [0, 2, 4]:
			var unit := _unit(path)
			if count >= 1:
				unit.apply_status(Combatant.Status.EXPOSED, 2)
			if count >= 2:
				unit.apply_status(Combatant.Status.HAUNTED, 3)
			if count >= 3:
				unit.hold = 4
			if count >= 4:
				unit.thorns = 12
			row.add_child(_view(unit, 0.7))
		root_box.add_child(row)
	return root_box


func _save_sheet(content: Control, file: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = SHEET_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var bg := ColorRect.new()
	bg.color = CardView.BACKDROP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(bg)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_child(content)
	viewport.add_child(margin)
	root.add_child(viewport)
	await process_frame
	# Step each view's animation by a fixed amount so the shot is repeatable.
	for view in EnemyView.find_all(viewport):
		view.advance(float(view.get_meta("seconds", 0.0)))
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	var used := int(margin.get_combined_minimum_size().y) + 24
	image = image.get_region(Rect2i(0, 0, image.get_width(), mini(used, image.get_height())))
	image.save_png(out_dir.path_join(file))
	print("saved ", out_dir.path_join(file))
	viewport.queue_free()


func _battle_shots() -> void:
	var shots := {
		"battle_1.png": ["res://data/enemies/cinder_hound.tres"],
		"battle_2.png": ["res://data/enemies/pale_whisperer.tres", "res://data/enemies/mourning_crow.tres"],
		"battle_3.png": ["res://data/enemies/skittering_wisp.tres", "res://data/enemies/hollow_colossus.tres", "res://data/enemies/lost_shade.tres"],
		"battle_warden_pair.png": ["res://data/enemies/gate_warden.tres", "res://data/enemies/lost_shade.tres"],
		"battle_boss.png": ["res://data/enemies/the_conductor.tres"],
	}
	for file in shots:
		var datas: Array[EnemyData] = []
		for path in shots[file]:
			datas.append(load(path) as EnemyData)
		var combat := Combat.create(Combatant.new("Wanderer", 40), StarterContent.extended_deck(), datas, 606)
		var scene: Control = load("res://battle.tscn").instantiate()
		scene.external_combat = combat
		root.add_child(scene)
		for i in 4:
			await process_frame
		# Dress the fight: Block, statuses, a hit enemy, and (with three enemies) a defeated one.
		var first := combat.enemies[0]
		first.gain_block(6)
		first.apply_status(Combatant.Status.EXPOSED, 2)
		if combat.enemies.size() > 1:
			combat.enemies[1].apply_status(Combatant.Status.HAUNTED, 3)
			combat.enemies[1].hp = combat.enemies[1].max_hp / 2
			combat.enemies[1].gain_block(3)
		if combat.enemies.size() > 2:
			combat.enemies[2].take_damage(9999)
		scene._select_target(0)
		for view in EnemyView.find_all(scene):
			view.advance(1.1)
		for i in 4:
			await process_frame
		var path := out_dir.path_join(file)
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		scene.queue_free()
		await process_frame
