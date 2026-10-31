class_name RunScreen
extends RefCounted
## Base for the run screens (the stop panels built by run.gd). A screen is given the run, the body
## container to build into and `refresh`, a callable that redraws the current stop (run.gd's
## `_show_stop`). It owns no navigation: run.gd decides which screen is shown.
## The shared widget helpers are static so any screen (or the pause menu) can use them.

## Card sizes: reward and vendor offers are drawn larger than a hand card, deck pickers and
## the character select screen use small cards (their names are also in tooltips and labels).
const OFFER_CARD_SCALE := 1.2
const PICKER_CARD_SCALE := 0.7
const PICKER_COLUMNS := 10

var run: RunState
var body: Control
var refresh: Callable


## Hands the screen what it builds from. Called by run.gd before each `show`.
func attach(run_state: RunState, body_container: Control, refresh_callable: Callable) -> void:
	run = run_state
	body = body_container
	refresh = refresh_callable


## Adds a centred column to the body and returns it; the first line is `title`.
func panel(title: String) -> VBoxContainer:
	var center := CenterContainer.new()
	body.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return box


## Adds a scene behind the panel that follows it (the panel is added after, so it sits on top).
func add_backdrop(scene: Control) -> void:
	body.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The pick-a-card-to-remove list shared by the reward and vendor screens.
func add_remove_picker(box: VBoxContainer, on_pick: Callable, on_cancel: Callable) -> void:
	var grid := GridContainer.new()
	grid.columns = PICKER_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for i in run.deck.size():
		grid.add_child(card_view(run.deck[i], PICKER_CARD_SCALE, on_pick.bind(i)))
	add_button(box, "Cancel", on_cancel)


static func add_button(box: Container, text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	box.add_child(button)
	return button


static func make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## A card drawn as a CardView. With `on_pressed` it is clickable and lifts on hover, like a
## button; the tooltip repeats the card's name, cost and text for small sizes.
static func card_view(card: CardData, view_scale: float, on_pressed := Callable()) -> CardView:
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


## A dark ribbon with a brass edge, so the words read over the art.
static func style_banner(label: Label) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.03, 0.03, 0.9)
	style.set_border_width_all(2)
	style.border_color = Color(0.78, 0.55, 0.24)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(5)
	label.add_theme_stylebox_override("normal", style)
	label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))


## A brass-edged counter button; the stock focus outline is kept visible for the keyboard.
static func style_service(button: Button) -> void:
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
