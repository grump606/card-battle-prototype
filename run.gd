extends Control
## Thin view over RunState: shows the current stop and forwards choices. A combat
## stop embeds battle.tscn around a Combat built by the run; everything else is a
## small panel. All run rules live in res://run/run_state.gd.

const BATTLE_SCENE := preload("res://battle.tscn")

@onready var _header: Label = %HeaderLabel
@onready var _body: Control = %Body

var _run: RunState


func _ready() -> void:
	_new_run()


func _new_run() -> void:
	_run = RunState.new(randi())
	_show_stop()


func _show_stop() -> void:
	_update_header()
	_clear_body()
	if _run.finished:
		_show_end()
	elif _run.reward_pending():
		_show_reward()
	elif _run.current_stop().type == RunState.StopType.COMBAT:
		_show_combat()
	else:
		_show_rest()


func _update_header() -> void:
	var player := _run.player
	var position := mini(_run.stop_index + 1, _run.stops.size())
	var stop_text := "Journey's end" if _run.finished else _run.current_stop().describe()
	_header.text = "Stop %d/%d: %s    |    %s  HP %d/%d    |    Deck %d" % [
		position, _run.stops.size(), stop_text, player.display_name, player.hp, player.max_hp, _run.deck.size(),
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
