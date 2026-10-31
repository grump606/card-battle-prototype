class_name SavedRunScreen
extends RunScreen
## The launch prompt shown when a valid save exists: Continue it or start a New Run.


## `on_continue` and `on_new_run` are already bound to the saved run by the caller.
func show(saved: RunState, on_continue: Callable, on_new_run: Callable) -> void:
	var box := panel("Stop %d/%d, %s HP %d/%d, Gold %d, Deck %d" % [
		saved.stop_index + 1, saved.stops.size(), saved.player.display_name, saved.player.hp, saved.player.max_hp, saved.gold, saved.deck.size(),
	])
	add_button(box, "Continue", on_continue)
	add_button(box, "New Run", on_new_run)
