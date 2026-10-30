extends SceneTree
## Headless UI test for battle.tscn: pile labels, tooltips, damage preview, keyboard
## control, target cycling and the New Fight flow. Run via scripts/check.ps1.

var fails := 0

func check(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		printerr("FAIL: " + msg)
	else:
		print("ok: " + msg)

func key(node: Node, code: int, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	node._unhandled_key_input(e)

## For each card with a state-dependent hit, the hand-button preview must equal the
## damage the real play deals, across plain, Blocked and Exposed targets.
func _check_preview_matches_damage(node: Control, combat: Combat) -> void:
	node._select_target(0)
	var cards := ["bash", "cold_steel", "last_pocket", "spree", "reckoning"]
	# [player block, plays already made this turn, target haunt, target block, exposed]
	var setups := [[0, 0, 0, 0, false], [4, 2, 3, 0, false], [12, 3, 5, 0, false], [12, 3, 5, 3, false], [4, 2, 3, 0, true]]
	for id in cards:
		for setup in setups:
			var card: CardData = load("res://data/cards/%s.tres" % id)
			var label := "%s %s" % [id, str(setup)]
			combat.player.clear_block()
			combat.player.gain_block(setup[0])
			combat.plays_this_turn = setup[1]
			combat.energy = 9
			var target: EnemyUnit = combat.enemies[0]
			target.clear_statuses()
			target.clear_block()
			target.max_hp = 500
			target.hp = 500
			if setup[2] > 0:
				target.apply_status(Combatant.Status.HAUNTED, setup[2])
			target.gain_block(setup[3])
			if setup[4]:
				target.apply_status(Combatant.Status.EXPOSED, 2)
			combat.piles.hand.clear()
			combat.piles.hand.append(card)
			node._rebuild_hand()
			var text: String = node._hand_box.get_child(0).text
			var dealt_to_block := target.block
			combat.play_card(0, 0)
			var lost: int = 500 - target.hp
			var expected := "%d after Block" % lost if dealt_to_block > 0 else ("(%d vs Exposed)" % lost if setup[4] else "Deals %d" % lost)
			check(text.contains(expected), "preview matches damage: %s lost %d in %s" % [label, lost, text.replace("\n", " | ")])
			combat.piles.hand.clear()


func _initialize() -> void:
	var node: Control = (load("res://battle.tscn") as PackedScene).instantiate()
	root.add_child(node)
	await process_frame
	var tries := 0
	while node._combat.enemies.size() < 3 and tries < 100:
		node._start_combat()
		tries += 1
	check(node._combat.enemies.size() == 3, "3 enemies")
	var c: Combat = node._combat
	var before: String = node._pile_label.text
	check(before.begins_with("Draw "), "pile label " + before)
	var idx := -1
	for i in c.piles.hand.size():
		if c.can_play(i):
			idx = i
			break
	var hand_n := c.piles.hand.size()
	var disc := c.piles.discard_pile.size()
	key(node, KEY_1 + idx)
	check(c.piles.discard_pile.size() == disc + 1, "number key played (discard grew)")
	check(node._pile_label.text != before, "pile label changed: " + node._pile_label.text)
	node._select_target(0)
	# The card played above may itself have exposed the target, so start from a clean slate.
	c.enemies[0].clear_statuses()
	c.player.clear_statuses()
	c.enemies[0].apply_status(Combatant.Status.EXPOSED, 2)
	c.player.apply_status(Combatant.Status.EXPOSED, 3)
	check(node._player_label.tooltip_text == "Takes 1.5x damage, rounded down, for 3 more turns.", "player tooltip: " + node._player_label.tooltip_text)
	check(node._enemy_row.get_child(0).tooltip_text.contains("2 more turns"), "enemy tooltip")
	check(node._enemy_row.get_child(1).tooltip_text == "", "no tooltip unexposed")
	var all_txt := ""
	for b in node._hand_box.get_children():
		all_txt += b.text + "\n---\n"
	print(all_txt)
	var dmg_cards := 0
	for card in c.piles.hand:
		if card.target_mode == CardData.TargetMode.SINGLE_ENEMY and card.describe().contains("Deal"):
			dmg_cards += 1
	check(all_txt.contains("vs Exposed") or dmg_cards == 0, "exposed preview present")
	if dmg_cards > 0:
		node._select_target(1)
		var t2 := ""
		for b in node._hand_box.get_children():
			t2 += b.text
		check(not t2.contains("vs Exposed"), "no exposed preview on unexposed target")
		node._select_target(0)
	c.enemies[1].take_damage(9999)
	node._select_target(0)
	key(node, KEY_RIGHT)
	check(node._target_index == 2, "right skips defeated")
	key(node, KEY_RIGHT)
	check(node._target_index == 0, "right wraps")
	key(node, KEY_TAB, true)
	check(node._target_index == 2, "shift-tab back skips defeated")
	key(node, KEY_LEFT)
	check(node._target_index == 0, "left")
	var turn: int = c.turn
	key(node, KEY_E)
	check(c.turn == turn + 1 or c.phase == Combat.Phase.ENDED, "E ends turn")
	for i in 10:
		key(node, KEY_1)
	check(c.energy >= 0, "no negative energy after rapid presses")
	if c.phase == Combat.Phase.PLAYER_TURN:
		for e in c.enemies:
			e.take_damage(9999)
		c._check_end()
	check(c.phase == Combat.Phase.ENDED, "ended")
	check(node._new_fight_button.visible, "new fight visible")
	var t: int = c.turn
	key(node, KEY_1)
	key(node, KEY_E)
	key(node, KEY_RIGHT)
	key(node, KEY_ENTER)
	check(c.turn == t and c.phase == Combat.Phase.ENDED, "keys no-op after end")
	node._on_end_turn_pressed()
	node._play_hand_card(0)
	node._select_target(0)
	check(true, "handlers no error after end")
	key(node, KEY_N)
	check(node._combat != c and node._combat.phase == Combat.Phase.PLAYER_TURN and not node._new_fight_button.visible, "N new fight")
	var c2: Combat = node._combat
	_check_preview_matches_damage(node, c2)
	c2.phase = Combat.Phase.ENEMY_TURN
	var h := c2.piles.hand.size()
	key(node, KEY_1)
	key(node, KEY_E)
	check(c2.piles.hand.size() == h, "enemy phase ignored")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
