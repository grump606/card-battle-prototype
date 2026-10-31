extends Control
## Thin view over RunState: shows the current stop and forwards choices. A combat
## stop embeds battle.tscn around a Combat built by the run; everything else is a
## small panel. All run rules live in res://run/run_state.gd.

const BATTLE_SCENE := preload("res://battle.tscn")

## Card sizes: reward and vendor offers are drawn larger than a hand card, deck pickers and
## the character select screen use small cards (their names are also in tooltips and labels).
const OFFER_CARD_SCALE := 1.2
const PICKER_CARD_SCALE := 0.7
const PICKER_COLUMNS := 10
## The vendor's relic slot: badge size and the width of the plate around it.
const RELIC_OFFER_SCALE := 1.5
const RELIC_SLOT_WIDTH := 150.0
## Height reserved above the vendor's speech banner for the shopkeeper's hood (see VendorScene).
const VENDOR_HEAD_HEIGHT := 104.0

@onready var _header_row: HBoxContainer = %HeaderRow
@onready var _header: Label = %HeaderLabel
@onready var _body: Control = %Body

var _run: RunState
## The run's relics beside the header line (hidden when there are none, on the select screens and
## during a fight, where the battle screen shows them itself).
var _header_strip: RelicStrip
## Result text of the last vendor action, shown on the vendor panel.
var _vendor_message := ""
## True while the vendor panel shows the pick-a-card-to-remove list.
var _removing := false
## True while the reward panel shows the pick-a-card-to-remove list.
var _reward_removing := false
## Where the in-progress run is saved; tests point this at a scratch file.
var save_path := RunSave.DEFAULT_PATH
## One-off message shown above the header line: a bad save on launch, or a save/delete failure.
var _notice := ""
var _notice_shown := false
## The container holding the character panels on the select screen (re-centred as the layout moves).
var _select_center: CenterContainer
## Pause menu: a button in the corner and an overlay that freezes the scene tree.
var _pause_button: Button
var _pause_overlay: Control
var _pause_box: VBoxContainer
var _pause_scene: PauseScene
## What "Save & Exit" calls once the save is safe; tests replace it so they do not quit.
var exit_callable: Callable = func() -> void: get_tree().quit()


func _ready() -> void:
	_header_strip = RelicStrip.create([] as Array[RelicData])
	_header_row.add_child(_header_strip)
	_build_pause_menu()
	_body.resized.connect(_recenter_select)
	resized.connect(_recenter_select)
	var loaded := RunSave.load_file(save_path)
	if loaded.run != null:
		_offer_continue(loaded.run)
	else:
		if not loaded.missing:
			_notice = "Saved run could not be loaded (%s). Started a new run." % loaded.error
			push_warning(_notice)
		_new_run()


## Launch with a valid save: nothing starts until the player picks Continue or New Run.
func _offer_continue(saved: RunState) -> void:
	_pause_button.visible = false
	_header_strip.set_relics([] as Array[RelicData])
	_clear_body() # Back from the select screen arrives here with that screen still shown
	_header.text = "Saved run found"
	var box := _panel("Stop %d/%d, %s HP %d/%d, Gold %d, Deck %d" % [
		saved.stop_index + 1, saved.stops.size(), saved.player.display_name, saved.player.hp, saved.player.max_hp, saved.gold, saved.deck.size(),
	])
	_add_button(box, "Continue", _continue_run.bind(saved))
	_add_button(box, "New Run", _new_run.bind(_offer_continue.bind(saved)))


func _continue_run(saved: RunState) -> void:
	_run = saved
	_vendor_message = ""
	_removing = false
	_reward_removing = false
	_clear_body()
	_show_stop()


## Every route to a new run goes through here: pick who boards the train, then `_start_run`.
## `back`, when valid, adds a Back button that returns to the screen the player came from; there is
## none when the select screen is the first screen (no save, or a save that failed to load).
func _new_run(back := Callable()) -> void:
	_pause_button.visible = false
	_header_strip.set_relics([] as Array[RelicData])
	_clear_body()
	var prefix := _notice + "
" if _notice != "" else ""
	_header.text = prefix + "Choose your passenger"
	_notice_shown = _notice != ""
	_select_center = CenterContainer.new()
	_body.add_child(_select_center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_select_center.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	if back.is_valid():
		var back_button := _add_button(column, "Back", back)
		back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for id in StarterContent.character_ids():
		var character := StarterContent.character(id)
		if character != null:
			var panel := CharacterPanel.new(character)
			panel.play_pressed.connect(_start_run)
			row.add_child(panel)
	if row.get_child_count() == 0:
		row.add_child(_label("No characters could be loaded (content failed to load). See the Output log."))
	else:
		(row.get_child(0) as CharacterPanel).play_button.grab_focus() # keyboard: arrows move between panels
	_recenter_select()
	_recenter_select.call_deferred() # the layout settles after this frame


func _start_run(character_id: StringName) -> void:
	_run = RunState.new(randi(), character_id)
	_vendor_message = ""
	_removing = false
	_reward_removing = false
	_show_stop()


## Keeps the select screen's group centred in the whole window rather than in the body, which
## sits below the header line.
func _recenter_select() -> void:
	if is_instance_valid(_select_center):
		_select_center.position = -(_body.global_position - global_position)
		_select_center.size = size


## A card drawn as a CardView. With `on_pressed` it is clickable and lifts on hover, like a
## button; the tooltip repeats the card's name, cost and text for small sizes.
func _card_view(card: CardData, view_scale: float, on_pressed := Callable()) -> CardView:
	var view := CardView.new()
	view.view_scale = view_scale
	view.set_card(card)
	view.tooltip_text = "%s (%d)\n%s" % [card.display_name, card.cost, card.describe()]
	if on_pressed.is_valid():
		view.clickable = true
		view.auto_hover = true
		view.pressed.connect(on_pressed)
	else:
		view.mouse_filter = Control.MOUSE_FILTER_PASS # still shows its tooltip
	return view


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _show_stop() -> void:
	# A notice lives for one redraw past the one that first showed it.
	if _notice_shown:
		_notice = ""
	_clear_body()
	if _run.finished:
		_delete_save()
		_update_header()
		_show_end()
	elif _run.reward_pending():
		_update_header()
		_show_reward()
	else:
		_autosave()
		_update_header()
		match _run.current_stop().type:
			RunState.StopType.COMBAT:
				_show_combat()
			RunState.StopType.STORY:
				_show_story()
			RunState.StopType.VENDOR:
				_show_vendor()
			_:
				_show_rest()


func _update_header() -> void:
	var player := _run.player
	var position := mini(_run.stop_index + 1, _run.stops.size())
	var prefix := _notice + "\n" if _notice != "" else ""
	var stop_text := _run.current_stop().describe() if not _run.finished else "Journey's end"
	if _run.reward_pending():
		stop_text = "Reward"
	_header.text = prefix + "Stop %d/%d: %s    |    %s  HP %d/%d    |    Gold %d    |    Deck %d" % [
		position, _run.stops.size(), stop_text, player.display_name, player.hp, player.max_hp, _run.gold, _run.deck.size(),
	]
	_notice_shown = _notice != ""
	_pause_button.visible = not _run.finished
	var fighting := not _run.finished and not _run.reward_pending() and _run.current_stop().type == RunState.StopType.COMBAT
	_header_strip.set_relics([] as Array[RelicData] if fighting else _run.relics)


func _clear_body() -> void:
	for child in _body.get_children():
		# Removed at once (not just queued) so a stale button cannot be clicked this frame.
		_body.remove_child(child)
		child.queue_free()


func _show_combat() -> void:
	var combat := _run.start_combat()
	if combat == null:
		var box := _panel("Could not build this fight (content failed to load). See the Output log.")
		_add_button(box, "Start over", _new_run)
		return
	var battle := BATTLE_SCENE.instantiate()
	battle.external_combat = combat
	# The mid-boss and the final boss both get the boss look; only the final one ends the run.
	var stop := _run.current_stop()
	battle.boss_fight = stop.boss or stop.mid_boss
	battle.boss_label = "Mid-boss" if stop.mid_boss else "Boss"
	battle.character_id = _run.character.id if _run.character != null else &""
	battle.relics = _run.relics
	battle.fight_finished.connect(_on_fight_finished)
	_body.add_child(battle)


func _on_fight_finished(victory: bool) -> void:
	_run.complete_combat(victory)
	_show_stop()


func _show_reward() -> void:
	if _reward_removing:
		var picker := _panel("Pick a card to remove from your deck.")
		_show_remove_picker(picker, _reward_remove_card, _cancel_reward_removing)
		return
	var beat_mid_boss := _run.current_stop().mid_boss
	var box := _panel("The mid-boss falls. The line runs on. Take a card for your deck, or skip." if beat_mid_boss else "Victory. Take a card for your deck, or skip.")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	for card in _run.reward_choices():
		row.add_child(_card_view(card, OFFER_CARD_SCALE, _take_reward.bind(card)))
	_add_button(box, "Skip (+%d gold)" % RunState.SKIP_GOLD, _take_reward.bind(null))
	# Once-per-run alternatives: hidden once used (Heal also while at full HP).
	if _run.can_reward_remove():
		_add_button(box, "Remove a card (free, once)", _start_reward_removing)
	if _run.can_reward_heal():
		_add_button(box, "Heal %d HP (free, once)" % RunState.REWARD_HEAL, _reward_heal)


func _take_reward(card: CardData) -> void:
	_run.resolve_reward(card)
	_show_stop()


func _start_reward_removing() -> void:
	_reward_removing = true
	_show_stop()


func _cancel_reward_removing() -> void:
	_reward_removing = false
	_show_stop()


func _reward_remove_card(deck_index: int) -> void:
	_reward_removing = false
	_run.resolve_reward_remove(_run.deck[deck_index])
	_show_stop()


func _reward_heal() -> void:
	_run.resolve_reward_heal()
	_show_stop()


func _show_story() -> void:
	var beat := _run.current_beat()
	# The window onto the tunnel sits behind the panel (see StoryScene).
	var story := StoryScene.new()
	story.beat_index = _run.current_stop().beat_index
	_add_backdrop(story)
	if beat == null:
		# Load failure is logged by the run; the stop must still be passable.
		var fallback := _panel("The train rattles on through the dark.")
		_style_banner(fallback.get_child(0) as Label)
		_add_button(fallback, "Continue", _read_story)
		return
	var box := _panel(beat.title)
	var text := Label.new()
	text.text = beat.text
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(480, 0)
	box.add_child(text)
	_add_button(box, beat.button_text, _read_story)
	# Dark ink on a paper card, like a ticket, so the words read over the art.
	var ink := Color(0.14, 0.10, 0.07)
	for label in [box.get_child(0), text]:
		label.add_theme_color_override("font_color", ink)
	box.get_child(0).add_theme_font_size_override("font_size", 22)
	var card := PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.89, 0.83, 0.68)
	paper.set_border_width_all(3)
	paper.border_color = Color(0.45, 0.30, 0.15)
	paper.set_corner_radius_all(5)
	paper.set_content_margin_all(22)
	paper.shadow_color = Color(0, 0, 0, 0.55)
	paper.shadow_size = 14
	card.add_theme_stylebox_override("panel", paper)
	var center := box.get_parent()
	center.remove_child(box)
	center.add_child(card)
	card.add_child(box)


## Adds a scene behind the panel that follows it (the panel is added after, so it sits on top).
func _add_backdrop(scene: Control) -> void:
	_body.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _read_story() -> void:
	_run.read_story()
	_show_stop()


func _show_vendor() -> void:
	var vendor := _run.vendor()
	# The stall is drawn behind the panel (the panel is added after it, so it sits on top).
	var stall := VendorScene.new()
	_body.add_child(stall)
	stall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stall.set_gold(_run.gold)
	stall.dimmed = _removing
	var box := _panel("A pale vendor leans out of the lantern light." if _run.gold >= Vendor.PRICE_CHEAP else "\"Empty pockets? Look, then. Looking is free.\"")
	_style_banner(box.get_child(0) as Label)
	if not _removing:
		var head := Control.new() # room for the shopkeeper's hood above the speech banner
		head.custom_minimum_size = Vector2(0, VENDOR_HEAD_HEIGHT)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(head)
		box.move_child(head, 0)
		stall.head_anchor = head
	if _vendor_message != "":
		var message := Label.new()
		message.text = _vendor_message
		message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_style_banner(message)
		box.add_child(message)
	if _removing:
		_show_remove_picker(box, _remove_card, _cancel_removing)
		return
	var offers := vendor.offers()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	for i in offers.size():
		var card: CardData = offers[i]["card"]
		var sold: bool = offers[i]["sold"]
		var price: int = offers[i]["price"]
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		var view := _card_view(card, OFFER_CARD_SCALE, _buy_card.bind(i))
		# A sold or unaffordable offer is dimmed with the reason on the card, and cannot be clicked.
		if sold:
			view.set_state(CardView.State.UNPLAYABLE, "SOLD")
		elif _run.gold < price:
			view.set_state(CardView.State.UNPLAYABLE, "NEED %d GOLD" % price)
		column.add_child(view)
		column.add_child(_label("Sold" if sold else "%d gold" % price))
		row.add_child(column)
	var relic_offer := vendor.relic_offer()
	if not relic_offer.is_empty():
		row.add_child(_relic_slot(relic_offer))
	stall.counter_anchor = row
	# The services sit on the counter front in a row, each with a prop drawn to its left by the stall
	# (the spacers keep the row centred).
	var services := HBoxContainer.new()
	services.alignment = BoxContainer.ALIGNMENT_CENTER
	services.add_theme_constant_override("separation", 52)
	box.add_child(services)
	services.add_child(_service_gap())
	# Disabled up front when the purchase would be refused, so the player is not
	# sent into a picker or a click that can only fail.
	var remove := _add_button(services, "Remove a card (%d gold)" % Vendor.REMOVE_CARD_PRICE, _start_removing)
	remove.disabled = vendor.has_removed() or _run.gold < Vendor.REMOVE_CARD_PRICE or _run.deck.size() <= 1
	var heal := _add_button(services, "Heal %d HP (%d gold)" % [Vendor.HEAL_AMOUNT, Vendor.HEAL_PRICE], _buy_heal)
	heal.disabled = vendor.has_healed() or _run.gold < Vendor.HEAL_PRICE or _run.player.hp >= _run.player.max_hp
	var leave := _add_button(services, "Leave", _leave_vendor)
	services.add_child(_service_gap())
	for button in [remove, heal, leave]:
		_style_service(button)
		stall.service_anchors.append(button)


## The vendor's relic for sale, beside the cards: badge, name, effect, price and a Buy button. Like a
## card offer it shows "Sold" afterwards and cannot be bought without the gold.
func _relic_slot(offer: Dictionary) -> Control:
	var relic: RelicData = offer["relic"]
	var sold: bool = offer["sold"]
	var price: int = offer["price"]
	var affordable := _run.gold >= price
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.03, 0.03, 0.9)
	style.set_border_width_all(2)
	style.border_color = Color(0.78, 0.55, 0.24)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	plate.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.custom_minimum_size = Vector2(RELIC_SLOT_WIDTH, 0)
	plate.add_child(column)
	var view := RelicView.new()
	view.view_scale = RELIC_OFFER_SCALE
	view.set_relic(relic)
	view.dimmed = sold or not affordable
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(view)
	var name_label := _label(relic.display_name)
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))
	column.add_child(name_label)
	var text := _label(relic.description)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color", Color(0.86, 0.82, 0.74))
	column.add_child(text)
	var price_label := _label("Sold" if sold else "%d gold" % price)
	price_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))
	column.add_child(price_label)
	var buy := _add_button(column, "Buy relic", _buy_relic)
	buy.disabled = sold or not affordable
	_style_service(buy)
	return plate


## A dark ribbon with a brass edge, so the vendor's words read over the art.
func _style_banner(label: Label) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.03, 0.03, 0.9)
	style.set_border_width_all(2)
	style.border_color = Color(0.78, 0.55, 0.24)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(5)
	label.add_theme_stylebox_override("normal", style)
	label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))


## A brass-edged counter button; the stock focus outline is kept visible for the keyboard.
func _style_service(button: Button) -> void:
	var states := {"normal": Color(0.17, 0.105, 0.06), "hover": Color(0.27, 0.17, 0.08), "pressed": Color(0.12, 0.07, 0.04), "disabled": Color(0.09, 0.07, 0.06)}
	for state in states:
		var style := StyleBoxFlat.new()
		style.bg_color = states[state]
		style.set_border_width_all(2)
		style.border_color = Color(0.42, 0.34, 0.26) if state == "disabled" else Color(0.82, 0.6, 0.28)
		style.set_corner_radius_all(5)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		button.add_theme_stylebox_override(state, style)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.border_color = Color(1.0, 0.95, 0.7)
	focus.set_corner_radius_all(5)
	focus.set_expand_margin_all(2)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.9))
	button.add_theme_color_override("font_disabled_color", Color(0.62, 0.57, 0.52))


func _service_gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(36, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _show_remove_picker(box: VBoxContainer, on_pick: Callable, on_cancel: Callable) -> void:
	var grid := GridContainer.new()
	grid.columns = PICKER_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for i in _run.deck.size():
		grid.add_child(_card_view(_run.deck[i], PICKER_CARD_SCALE, on_pick.bind(i)))
	_add_button(box, "Cancel", on_cancel)


func _buy_card(offer_index: int) -> void:
	_finish_vendor_action(_run.vendor_buy_card(offer_index), "Bought")


func _buy_relic() -> void:
	var result := _run.vendor_buy_relic()
	_finish_vendor_action(result, "Bought %s" % result.relic.display_name if result.ok else "")


func _buy_heal() -> void:
	_finish_vendor_action(_run.vendor_buy_heal(), "Healed")


func _remove_card(deck_index: int) -> void:
	_removing = false
	_finish_vendor_action(_run.vendor_remove_card(deck_index), "Removed")


func _start_removing() -> void:
	_removing = true
	_vendor_message = "Pick a card to remove."
	_show_stop()


func _cancel_removing() -> void:
	_removing = false
	_vendor_message = ""
	_show_stop()


func _finish_vendor_action(result: Vendor.Result, done_text: String) -> void:
	_vendor_message = done_text if result.ok else "Can't: %s." % result.reason
	_show_stop()


func _leave_vendor() -> void:
	_vendor_message = ""
	_removing = false
	_run.leave_vendor()
	_show_stop()


func _show_rest() -> void:
	var player := _run.player
	var scene := RestScene.new()
	scene.character_id = _run.character.id if _run.character != null else &""
	_add_backdrop(scene)
	var box := _panel("A quiet platform. The train waits.\nHP %d/%d" % [player.hp, player.max_hp])
	_style_banner(box.get_child(0) as Label)
	_style_service(_add_button(box, "Rest (+%d HP)" % RunState.REST_HEAL, _rest))


func _rest() -> void:
	_run.rest()
	_show_stop()


func _show_end() -> void:
	var title := "You slip off the train and into the light." if _run.escaped else "You are claimed by the afterlife."
	var scene := EndScene.new()
	scene.escaped = _run.escaped
	_add_backdrop(scene)
	var box := _panel("%s\nOutcome: %s" % [title, "Escaped" if _run.escaped else "Defeated"])
	_style_banner(box.get_child(0) as Label)
	var summary := Label.new()
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.text = "Stops cleared: %d/%d\nFinal HP: %d/%d\nDeck: %d cards\nGold: %d" % [
		_run.stop_index, _run.stops.size(), _run.player.hp, _run.player.max_hp, _run.deck.size(), _run.gold,
	]
	_style_banner(summary)
	box.add_child(summary)
	_style_service(_add_button(box, "New Run", _new_run.bind(_show_stop)))


## Saves the run at the start of a stop (never mid-fight). A failure is shown, not fatal.
func _autosave() -> void:
	if not _run.at_stop_boundary():
		return
	var error := RunSave.save(_run, save_path)
	if error != "":
		_notice = "Could not save the run: %s" % error
		push_warning(_notice)


## A finished run has nothing to resume.
func _delete_save() -> void:
	var error := RunSave.delete(save_path)
	if error != "":
		_notice = error
		push_warning(_notice)


## Adds a centred column to the body and returns it; the first line is `title`.
func _panel(title: String) -> VBoxContainer:
	var center := CenterContainer.new()
	_body.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return box


func _add_button(box: Container, text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	box.add_child(button)
	return button


# --- Pause menu -------------------------------------------------------------

func _build_pause_menu() -> void:
	# This screen keeps running while the tree is paused (the overlay buttons and the Escape key
	# need to), so only the run body, which holds the fight, is made pausable.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_body.process_mode = Node.PROCESS_MODE_PAUSABLE
	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.visible = false
	_pause_button.focus_mode = Control.FOCUS_NONE # keys belong to the battle screen
	_pause_button.pressed.connect(_set_paused.bind(true))
	add_child(_pause_button)
	_pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)

	_pause_overlay = Control.new()
	_pause_overlay.visible = false
	add_child(_pause_overlay)
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	# Opaque, so the pause is a full screen of its own rather than a veil over the fight.
	dim.color = Color(0.04, 0.04, 0.07)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP # nothing underneath can be clicked
	_pause_overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_scene = PauseScene.new() # animated backdrop; only runs while the overlay is visible
	_pause_overlay.add_child(_pause_scene)
	_pause_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_pause_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_box = VBoxContainer.new()
	_pause_box.add_theme_constant_override("separation", 12)
	center.add_child(_pause_box)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	if _pause_overlay.visible or _pause_button.visible:
		_set_paused(not _pause_overlay.visible)
		get_viewport().set_input_as_handled()


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	_pause_overlay.visible = on
	if on:
		_pause_scene.set_character(_run.character.id if _run != null and _run.character != null else &"")
		_show_pause_options("")


func _show_pause_options(message: String) -> void:
	_clear_pause_box()
	_add_pause_label("The train waits.", 36)
	_add_pause_label("Paused. Nothing moves until you do.")
	if message != "":
		_add_pause_label(message)
	if _run != null and not _run.relics.is_empty():
		_add_pause_label("Relics")
		var strip := RelicStrip.create(_run.relics)
		strip.alignment = BoxContainer.ALIGNMENT_CENTER
		_pause_box.add_child(strip)
	_add_button(_pause_box, "Continue", _set_paused.bind(false))
	_add_button(_pause_box, "Save & Exit", _save_and_exit)
	_add_button(_pause_box, "New Run", _confirm_new_run)
	_add_pause_label("A save is taken at the start of every stop, so\nSave & Exit resumes from the start of this stop.")


func _confirm_new_run() -> void:
	_clear_pause_box()
	_add_pause_label("Abandon this run?", 36)
	_add_pause_label("This ends the journey and starts a new one.")
	_add_button(_pause_box, "Yes, start a new run", _start_new_run_from_pause)
	_add_button(_pause_box, "Cancel", _show_pause_options.bind(""))


func _start_new_run_from_pause() -> void:
	_set_paused(false)
	_new_run()


## The run is saved at the start of each stop, so mid-fight the existing save is already the
## resume point; only at a stop boundary is there anything new to write. Never exits unless
## a save exists to come back to.
func _save_and_exit() -> void:
	if _run.at_stop_boundary():
		var error := RunSave.save(_run, save_path)
		if error != "":
			_show_pause_options("Could not save: %s" % error)
			return
	elif not FileAccess.file_exists(save_path):
		_show_pause_options("No save to resume from, so not exiting.")
		return
	exit_callable.call()


func _clear_pause_box() -> void:
	for child in _pause_box.get_children():
		_pause_box.remove_child(child)
		child.queue_free()


func _add_pause_label(text: String, font_size: int = 0) -> void:
	var label := Label.new()
	label.text = text
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_box.add_child(label)
