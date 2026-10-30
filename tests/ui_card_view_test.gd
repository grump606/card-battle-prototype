extends SceneTree
## Headless test for CardView: every card in data/cards builds and draws without errors, the
## frame follows card.character, and each effect kind gets an icon. Run via scripts/check.ps1.

var fails := 0

func check(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		printerr("FAIL: " + msg)
	else:
		print("ok: " + msg)


func _initialize() -> void:
	var holder := Control.new()
	root.add_child(holder)
	var count := 0
	var classes := {}
	for file in DirAccess.get_files_at("res://data/cards"):
		if not file.ends_with(".tres"):
			continue
		var card := load("res://data/cards/" + file) as CardData
		var view := CardView.new()
		holder.add_child(view)
		view.set_card(card)
		check(view.class_id == (card.character if card.character != &"" else &""), "%s uses the %s frame" % [card.id, card.character if card.character != &"" else "neutral"])
		check(CardView.primary_kind(card) >= 0, "%s has a primary icon" % card.id)
		classes[view.class_id] = true
		for state in [CardView.State.NORMAL, CardView.State.HOVER, CardView.State.SELECTED, CardView.State.UNPLAYABLE]:
			view.set_state(state, "NEED 1 ENERGY" if state == CardView.State.UNPLAYABLE else "")
		count += 1
	await process_frame
	await process_frame
	check(count >= 35, "built a view for all %d cards" % count)
	check(classes.size() == 4, "neutral and three class frames are all in use")
	check(CardView.palette_id(null) == &"" and CardView.PALETTES.has(&"medium"), "palette lookup")
	var unknown := CardData.make(&"x", "X", 1, [] as Array[CardEffect])
	unknown.character = &"nobody"
	check(CardView.palette_id(unknown) == &"" and CardView.primary_kind(unknown) == -1, "unknown class falls back to neutral")
	for kind in CardEffect.Kind.values():
		check(CardView.ICON_PRIORITY.has(kind), "kind %d has an icon" % kind)
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
