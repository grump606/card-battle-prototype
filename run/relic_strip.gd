class_name RelicStrip
extends HBoxContainer
## A row of RelicViews for the relics a run owns (see docs/RELIC_ART_DESIGN.md). Hidden while it
## holds none, so screens can keep one in their layout without reserving space. It ignores the
## mouse itself; each badge shows its own tooltip.

var badge_scale := 1.0

var _relics: Array[RelicData] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	visible = false


## A strip already filled with `relics`.
static func create(relics: Array[RelicData], badge := 1.0) -> RelicStrip:
	var strip := RelicStrip.new()
	strip.badge_scale = badge
	strip.set_relics(relics)
	return strip


## Replaces the shown relics with `relics` (purchase order) and hides the strip when empty.
func set_relics(relics: Array[RelicData]) -> void:
	_relics = relics.duplicate()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for relic in _relics:
		var view := RelicView.new()
		view.view_scale = badge_scale
		view.set_relic(relic)
		add_child(view)
	visible = not _relics.is_empty()


## How many relics are shown.
func count() -> int:
	return _relics.size()
