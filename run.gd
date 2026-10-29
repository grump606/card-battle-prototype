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


func _ready() -> void:
	_new_run()


func _new_run() -> void:
	_run = RunState.new(randi())
	_vendor_message = ""
	_removing = false
	_show_stop()


func _show_stop() -> void:
	_update_header()
	_clear_body()
	if _run.finished:
		_show_end()
	elif _run.reward_pending():
		_show_reward()
	else:
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
	var stop_text := _run.current_stop().describe() if not _run.finished else "Journey's end"
	if _run.reward_pending():
		stop_text = "Reward"
	_header.text = "Stop %d/%d: %s    |    %s  HP %d/%d    |    Gold %d    |    Deck %d" % [
		position, _run.stops.size(), stop_text, player.display_name, player.hp, player.max_hp, _run.gold, _run.deck.size(),
	]


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
	var box := _panel("%s\nStops passed: %d/%d   Deck: %d cards" % [title, _run.stop_index, _run.stops.size(), _run.deck.size()])
	_add_button(box, "New Run", _new_run)


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
