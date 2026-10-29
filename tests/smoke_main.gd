extends SceneTree
## Smoke test: loads and instantiates the project's main scene.
## Run: godot --headless --path . -s res://tests/smoke_main.gd


func _initialize() -> void:
	var path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	var scene := load(path) as PackedScene
	if scene == null:
		printerr("SMOKE FAIL: cannot load main scene '%s'" % path)
		quit(1)
		return
	var node := scene.instantiate()
	if node == null:
		printerr("SMOKE FAIL: cannot instantiate main scene")
		quit(1)
		return
	root.add_child(node)
	print("SMOKE OK: %s" % path)
	node.queue_free()
	quit(0)
