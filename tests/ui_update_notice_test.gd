extends SceneTree
## Headless test of the update notice on the run screen. No network: a fake reply is fed to
## UpdateNotice.handle_response. Also checks that the real request is never started headless.
## Run via scripts/check.ps1.

var test_save := "user://ui_update_notice_test_save_%d.json" % OS.get_process_id()

var _failures := 0


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _release(tag: Variant) -> PackedByteArray:
	return JSON.stringify({"tag_name": tag}).to_utf8_buffer()


func _make_scene() -> Control:
	var scene: Control = load("res://run.tscn").instantiate()
	scene.save_path = test_save
	root.add_child(scene)
	return scene


func _initialize() -> void:
	RunSave.delete(test_save)
	var scene := _make_scene()
	await process_frame
	var notice: UpdateNotice = scene._update_notice
	var opened: Array[String] = []
	notice.open_url = func(url: String) -> void: opened.append(url)
	notice.current_version = "0.3.0"

	_check(notice != null and not notice.visible, "the notice starts hidden")
	_check(DisplayServer.get_name() == "headless", "this test runs headless")
	_check(not notice.start(), "the check does not start under headless")
	_check(notice.get_children().all(func(child: Node) -> bool: return not child is HTTPRequest), "no HTTPRequest node exists under headless")

	# Replies that must not show anything.
	notice.handle_response(200, _release("v0.3.0"))
	_check(not notice.visible, "the same version shows no notice")
	notice.handle_response(200, _release("v0.2.9"))
	_check(not notice.visible, "an older version shows no notice")
	for junk in [PackedByteArray(), "not json".to_utf8_buffer(), "[]".to_utf8_buffer(), _release("latest"), _release("1.2.3-beta; rm"), _release(null), _release(99999)]:
		notice.handle_response(200, junk)
		_check(not notice.visible, "a bad reply shows no notice")
	notice.handle_response(404, _release("v9.9.9"))
	notice.handle_response(403, _release("v9.9.9"))
	notice.handle_response(500, _release("v9.9.9"))
	_check(not notice.visible, "an HTTP error shows no notice")

	# A newer release shows it on the select screen, clear of the character panels.
	notice.handle_response(200, _release("v0.3.1"))
	await process_frame
	await process_frame
	_check(notice.visible and notice.latest_tag == "v0.3.1", "a newer release shows the notice")
	_check(notice.label.text == "Update available: v0.3.1 (you have 0.3.0)", "the notice says what is available (got '%s')" % notice.label.text)
	_check(notice.download_button != null and notice.download_button.visible and notice.dismiss_button != null, "the notice has Download and dismiss buttons")
	_check(scene.get_node("%HeaderLabel").text.contains("Main menu"), "the main menu is showing, untouched")
	_find_button(scene.get_node("%Body"), "New Run").pressed.emit()
	await process_frame
	await process_frame
	_check(notice.visible and scene._run == null and scene.get_node("%HeaderLabel").text.contains("Choose your passenger"), "the notice stays on the select screen")
	_check(notice.get_parent() == scene and not scene.get_node("%Body").is_ancestor_of(notice), "the notice sits outside the body")
	var window := scene.get_global_rect()
	_check(window.encloses(notice.get_global_rect()), "the notice fits inside the window")
	var panels: Array[CharacterPanel] = []
	_find_panels(scene, panels)
	for panel in panels:
		_check(not panel.get_global_rect().intersects(notice.get_global_rect()), "the notice does not overlap the %s panel" % panel.character_id)

	notice.download_button.pressed.emit()
	_check(opened == [UpdateCheck.RELEASES_PAGE], "Download opens only the fixed releases page (opened %s)" % str(opened))

	# A later reply cannot swap the page that Download opens.
	notice.handle_response(200, JSON.stringify({"tag_name": "v0.4.0", "html_url": "https://evil.example/", "assets": [{"browser_download_url": "https://evil.example/x.exe"}]}).to_utf8_buffer())
	opened.clear()
	notice.download_button.pressed.emit()
	_check(opened == [UpdateCheck.RELEASES_PAGE], "Download ignores any URL in the reply")

	notice.dismiss_button.pressed.emit()
	_check(not notice.visible, "dismiss hides the notice")
	notice.set_allowed(true)
	_check(not notice.visible, "a dismissed notice stays hidden")
	scene.queue_free()
	await process_frame

	# With a saved run the Continue prompt carries it, and starting the run takes it away.
	var saved := RunState.new(7, &"deserter")
	_check(RunSave.save(saved, test_save) == "", "setup: a save was written")
	scene = _make_scene()
	await process_frame
	notice = scene._update_notice
	notice.current_version = "0.3.0"
	_check(scene.get_node("%HeaderLabel").text.contains("Main menu") and _find_button(scene.get_node("%Body"), "Continue") != null, "setup: the main menu offers Continue")
	notice.handle_response(200, _release("v0.3.1"))
	await process_frame
	_check(notice.visible, "the main menu shows the notice")
	var body: Control = scene.get_node("%Body")
	var continue_button := _find_button(body, "Continue")
	_check(continue_button != null, "the Continue button exists")
	if continue_button != null:
		_check(not continue_button.get_global_rect().intersects(notice.get_global_rect()), "the notice does not cover the Continue button")
		continue_button.pressed.emit()
		await process_frame
	_check(scene._run != null and not notice.visible, "the notice is gone once a run is in progress")
	scene.queue_free()
	await process_frame
	RunSave.delete(test_save)

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _find_panels(node: Node, out: Array[CharacterPanel]) -> void:
	if node is CharacterPanel:
		out.append(node)
	for child in node.get_children():
		_find_panels(child, out)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null
