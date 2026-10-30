extends Control
## Thin view over RunState: shows the current stop and forwards choices. A combat
## stop embeds battle.tscn around a Combat built by the run; everything else is a
## small panel. All run rules live in res://run/run_state.gd.

const BATTLE_SCENE := preload("res://battle.tscn")

@onready var _header: Label = %HeaderLabel
@onready var _body: Control = %Body

var _run: RunState
## Result text of the last vendor action, shown on the vendor panel.
var _vendor_message := ""
## True while the vendor panel shows the pick-a-card-to-remove list.
var _removing := false
## Where the in-progress run is saved; tests point this at a scratch file.
var save_path := RunSave.DEFAULT_PATH
## One-off message shown above the header line: a bad save on launch, or a save/delete failure.
var _notice := ""
var _notice_shown := false
## Pause menu: a button in the corner and an overlay that freezes the scene tree.
var _pause_button: Button
var _pause_overlay: Control
var _pause_box: VBoxContainer
## What "Save & Exit" calls once the save is safe; tests replace it so they do not quit.
var exit_callable: Callable = func() -> void: get_tree().quit()


func _ready() -> void:
	_build_pause_menu()
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
	_header.text = "Saved run found"
	var box := _panel("Stop %d/%d, %s HP %d/%d, Gold %d, Deck %d" % [
		saved.stop_index + 1, saved.stops.size(), saved.player.display_name, saved.player.hp, saved.player.max_hp, saved.gold, saved.deck.size(),
	])
	_add_button(box, "Continue", _continue_run.bind(saved))
	_add_button(box, "New Run", _new_run)


func _continue_run(saved: RunState) -> void:
	_run = saved
	_vendor_message = ""
	_removing = false
	_clear_body()
	_show_stop()


func _new_run() -> void:
	_run = RunState.new(randi())
	_vendor_message = ""
	_removing = false
	_show_stop()


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
	battle.fight_finished.connect(_on_fight_finished)
	_body.add_child(battle)


func _on_fight_finished(victory: bool) -> void:
	_run.complete_combat(victory)
	_show_stop()


func _show_reward() -> void:
	var box := _panel("Victory. Take a card for your deck, or skip.")
	for card in _run.reward_choices():
		var button := _add_button(box, "%s (%d)\n%s" % [card.display_name, card.cost, card.describe()], _take_reward.bind(card))
		button.custom_minimum_size = Vector2(260, 56)
	_add_button(box, "Skip", _take_reward.bind(null))


func _take_reward(card: CardData) -> void:
	_run.resolve_reward(card)
	_show_stop()


func _show_story() -> void:
	var beat := _run.current_beat()
	if beat == null:
		# Load failure is logged by the run; the stop must still be passable.
		var fallback := _panel("The train rattles on through the dark.")
		_add_button(fallback, "Continue", _read_story)
		return
	var box := _panel(beat.title)
	var text := Label.new()
	text.text = beat.text
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(480, 0)
	box.add_child(text)
	_add_button(box, beat.button_text, _read_story)


func _read_story() -> void:
	_run.read_story()
	_show_stop()


func _show_vendor() -> void:
	var vendor := _run.vendor()
	var box := _panel("A vendor leans out of the dark.    Gold: %d" % _run.gold)
	if _vendor_message != "":
		var message := Label.new()
		message.text = _vendor_message
		message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(message)
	if _removing:
		_show_remove_picker(box)
		return
	var offers := vendor.offers()
	for i in offers.size():
		var card: CardData = offers[i]["card"]
		var sold: bool = offers[i]["sold"]
		var text := "%s (%d)\n%s\n%d gold" % [card.display_name, card.cost, card.describe(), offers[i]["price"]]
		var button := _add_button(box, "%s  (sold)" % card.display_name if sold else text, _buy_card.bind(i))
		button.disabled = sold or _run.gold < offers[i]["price"]
		button.custom_minimum_size = Vector2(300, 56)
	# Disabled up front when the purchase would be refused, so the player is not
	# sent into a picker or a click that can only fail.
	var remove := _add_button(box, "Remove a card (%d gold)" % Vendor.REMOVE_CARD_PRICE, _start_removing)
	remove.disabled = vendor.has_removed() or _run.gold < Vendor.REMOVE_CARD_PRICE or _run.deck.size() <= 1
	var heal := _add_button(box, "Heal %d HP (%d gold)" % [Vendor.HEAL_AMOUNT, Vendor.HEAL_PRICE], _buy_heal)
	heal.disabled = vendor.has_healed() or _run.gold < Vendor.HEAL_PRICE or _run.player.hp >= _run.player.max_hp
	_add_button(box, "Leave", _leave_vendor)


func _show_remove_picker(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	box.add_child(grid)
	for i in _run.deck.size():
		_add_button(grid, _run.deck[i].display_name, _remove_card.bind(i))
	_add_button(box, "Cancel", _cancel_removing)


func _buy_card(offer_index: int) -> void:
	_finish_vendor_action(_run.vendor_buy_card(offer_index), "Bought")


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
	var box := _panel("A quiet platform. The train waits.\nHP %d/%d" % [player.hp, player.max_hp])
	_add_button(box, "Rest (+%d HP)" % RunState.REST_HEAL, _rest)


func _rest() -> void:
	_run.rest()
	_show_stop()


func _show_end() -> void:
	var title := "You slip off the train and into the light." if _run.escaped else "You are claimed by the afterlife."
	var box := _panel("%s\nOutcome: %s" % [title, "Escaped" if _run.escaped else "Defeated"])
	var summary := Label.new()
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.text = "Stops cleared: %d/%d\nFinal HP: %d/%d\nDeck: %d cards\nGold: %d" % [
		_run.stop_index, _run.stops.size(), _run.player.hp, _run.player.max_hp, _run.deck.size(), _run.gold,
	]
	box.add_child(summary)
	_add_button(box, "New Run", _new_run)


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
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	# Opaque, so the pause is a full screen of its own rather than a veil over the fight.
	dim.color = Color(0.04, 0.04, 0.07)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP # nothing underneath can be clicked
	_pause_overlay.add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_pause_overlay.add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
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
		_show_pause_options("")


func _show_pause_options(message: String) -> void:
	_clear_pause_box()
	_add_pause_label("The train waits.", 36)
	_add_pause_label("Paused. Nothing moves until you do.")
	if message != "":
		_add_pause_label(message)
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
