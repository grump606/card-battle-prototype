class_name MainMenuScreen
extends RunScreen
## The start screen, shown on every launch: Continue (only when a valid save exists), New Run, Exit.

const BUTTON_WIDTH := 220.0

var continue_button: Button
var new_run_button: Button
var exit_button: Button


## `saved` is the run found on disk, or null. `on_continue` is already bound to it by the caller.
func show(saved: RunState, on_continue: Callable, on_new_run: Callable, on_exit: Callable) -> void:
	var box := panel("Card Battle Prototype")
	if saved != null:
		box.add_child(make_label("Saved run: stop %d/%d, %s, HP %d/%d, Gold %d, Deck %d" % [
			saved.stop_index + 1, saved.stops.size(), saved.player.display_name, saved.player.hp, saved.player.max_hp, saved.gold, saved.deck.size(),
		]))
		continue_button = add_button(box, "Continue", on_continue)
	new_run_button = add_button(box, "New Run", on_new_run)
	exit_button = add_button(box, "Exit", on_exit)
	for button in [continue_button, new_run_button, exit_button]:
		if button != null:
			button.custom_minimum_size = Vector2(BUTTON_WIDTH, 36)
			button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	(continue_button if continue_button != null else new_run_button).grab_focus()
