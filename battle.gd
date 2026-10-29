extends Control
## Thin view over Combat: renders state and forwards button presses. All rules
## live in res://combat/.

const PLAYER_START_HP := 40
const MAX_HAND_KEYS := 9

# Derived from the rules constants so the text cannot drift from them.
const EXPOSED_MULTIPLIER_TEXT := "%.1fx" % (float(Combatant.EXPOSED_NUM) / Combatant.EXPOSED_DEN)
const EXPOSED_TOOLTIP := "Takes " + EXPOSED_MULTIPLIER_TEXT + " damage, rounded down, for %d more turns."

@onready var _enemy_row: HBoxContainer = %EnemyRow
@onready var _player_label: Label = %PlayerLabel
@onready var _energy_label: Label = %EnergyLabel
@onready var _pile_label: Label = %PileLabel
@onready var _hand_box: HBoxContainer = %HandBox
@onready var _end_turn_button: Button = %EndTurnButton
@onready var _result_label: Label = %ResultLabel
@onready var _log_label: RichTextLabel = %LogLabel
@onready var _new_fight_button: Button = %NewFightButton

## Emitted in embedded mode (see external_combat) when the player presses
## Continue after the fight ended.
signal fight_finished(victory: bool)

## Set before adding this scene to the tree to show a fight built by a run layer
## instead of a standalone random one. The screen then ends with a Continue
## button that emits fight_finished rather than starting a new fight.
var external_combat: Combat = null

var _combat: Combat
var _victory := false
## Index into Combat.enemies that cards will target.
var _target_index: int = 0


func _ready() -> void:
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_new_fight_button.pressed.connect(_on_continue_pressed)
	# Keys are handled in _unhandled_key_input; focusable buttons would let
	# Tab/Enter/Space move focus or re-press a button instead.
	_end_turn_button.focus_mode = Control.FOCUS_NONE
	_new_fight_button.focus_mode = Control.FOCUS_NONE
	if external_combat != null:
		_new_fight_button.text = "Continue"
		_attach(external_combat)
	else:
		_start_combat()


func _start_combat() -> void:
	var player := Combatant.new("Wanderer", PLAYER_START_HP)
	var enemy_count := randi_range(1, Combat.MAX_ENEMIES)
	var encounter_rng := RandomNumberGenerator.new()
	encounter_rng.randomize()
	var combat := Combat.create(player, StarterContent.extended_deck(), StarterContent.varied_encounter(enemy_count, encounter_rng), randi())
	if combat == null:
		_result_label.text = "Could not build this fight (content failed to load). See the Output log."
		_new_fight_button.show()
		return
	_attach(combat)


## Shows and starts `combat`, replacing any previous fight on this screen.
func _attach(combat: Combat) -> void:
	_combat = combat
	_combat.state_changed.connect(_refresh)
	_combat.combat_ended.connect(_on_combat_ended)
	_combat.card_played.connect(_on_card_played)
	_combat.enemy_acted.connect(_on_enemy_acted)
	_target_index = 0
	_result_label.text = ""
	_log_label.clear()
	_new_fight_button.hide()
	_combat.start()


func _refresh() -> void:
	var player := _combat.player
	_player_label.text = "%s  HP %d/%d  Block %d%s" % [player.display_name, player.hp, player.max_hp, player.block, _status_text(player)]
	_player_label.tooltip_text = _status_tooltip(player)
	_energy_label.text = "Energy %d/%d" % [_combat.energy, Combat.ENERGY_PER_TURN]
	_pile_label.text = "Draw %d | Discard %d" % [_combat.piles.draw_pile.size(), _combat.piles.discard_pile.size()]
	_keep_target_alive()
	_rebuild_enemies()
	_rebuild_hand()
	_end_turn_button.disabled = _combat.phase != Combat.Phase.PLAYER_TURN


## Moves the selection to the first living enemy if the current one is defeated.
func _keep_target_alive() -> void:
	if _combat.enemies[_target_index].is_dead():
		for i in _combat.enemies.size():
			if not _combat.enemies[i].is_dead():
				_target_index = i
				return


func _rebuild_enemies() -> void:
	for child in _enemy_row.get_children():
		_discard_node(child)
	for i in _combat.enemies.size():
		var enemy := _combat.enemies[i]
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if enemy.is_dead():
			button.text = "%s\nDefeated" % enemy.display_name
			button.disabled = true
			button.modulate = Color(0.5, 0.5, 0.5, 0.6)
		else:
			var intent := enemy.current_intent()
			var marker := "> " if i == _target_index else ""
			button.text = "%s%s\nHP %d/%d  Block %d%s\nIntent: %s" % [
				marker, enemy.display_name, enemy.hp, enemy.max_hp, enemy.block, _status_text(enemy),
				intent.describe() if intent != null else "-",
			]
			button.tooltip_text = _status_tooltip(enemy)
			button.pressed.connect(_select_target.bind(i))
			if i == _target_index:
				button.modulate = Color(1.0, 0.85, 0.4)
		_enemy_row.add_child(button)


func _rebuild_hand() -> void:
	for child in _hand_box.get_children():
		_discard_node(child)
	for i in _combat.piles.hand.size():
		var card := _combat.piles.hand[i]
		var button := Button.new()
		button.text = "%s (%d)\n%s%s%s" % [card.display_name, card.cost, card.describe(), _damage_preview(card), _target_tag(card)]
		button.disabled = not _combat.can_play(i)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_play_hand_card.bind(i))
		_hand_box.add_child(button)


## Removes a stale child immediately (not just queue_free) so it can no longer
## receive a click in the same frame, which would act on an outdated index.
func _discard_node(node: Node) -> void:
	node.get_parent().remove_child(node)
	node.queue_free()


func _play_hand_card(hand_index: int) -> void:
	if _combat == null:
		return
	_combat.play_card(hand_index, _target_index)


func _status_tooltip(combatant: Combatant) -> String:
	var exposed := combatant.status_turns(Combatant.Status.EXPOSED)
	return EXPOSED_TOOLTIP % exposed if exposed > 0 else ""


## DISPLAY-ONLY preview of damage on the selected enemy: Exposed scaling comes
## from Combatant.damage_after_status, then block is subtracted per hit as
## take_damage does. The result of an actual play is authoritative.
func _damage_preview(card: CardData) -> String:
	var base := 0
	var hits: Array[int] = []
	for effect in card.effects:
		if effect.kind == CardEffect.Kind.DAMAGE:
			base += effect.amount
			hits.append(effect.amount)
	if hits.is_empty():
		return ""
	if card.target_mode == CardData.TargetMode.ALL_ENEMIES:
		return "\nDeals %d (x%d enemies)" % [base, _combat.living_enemies().size()]
	var target := _combat.enemies[_target_index]
	if card.target_mode != CardData.TargetMode.SINGLE_ENEMY or target.is_dead():
		return ""
	var exposed := target.status_turns(Combatant.Status.EXPOSED) > 0
	var block := target.block
	var dealt := 0
	var lost := 0
	for hit in hits:
		var amount := target.damage_after_status(hit)
		var absorbed := mini(block, amount)
		block -= absorbed
		dealt += amount
		lost += amount - absorbed
	var text := "\nDeals %d" % dealt
	if exposed:
		text = "\nDeals %d (%d vs Exposed)" % [base, dealt]
	if target.block > 0:
		text += ", %d after Block" % lost
	return text


func _status_text(combatant: Combatant) -> String:
	var exposed := combatant.status_turns(Combatant.Status.EXPOSED)
	return "  Exposed %d" % exposed if exposed > 0 else ""


## Single-target cards use the selected enemy, so only the other modes get a tag.
func _target_tag(card: CardData) -> String:
	match card.target_mode:
		CardData.TargetMode.ALL_ENEMIES:
			return "\n[all enemies]"
		CardData.TargetMode.SELF:
			return "\n[self]"
	return ""


func _select_target(index: int) -> void:
	if _combat == null or index < 0 or index >= _combat.enemies.size() or _combat.enemies[index].is_dead():
		return
	_target_index = index
	_refresh()


func _on_end_turn_pressed() -> void:
	if _combat == null:
		return
	_combat.end_player_turn()


## Moves the selection to the next living enemy in `direction` (+1 or -1).
func _cycle_target(direction: int) -> void:
	var count := _combat.enemies.size()
	for step in range(1, count):
		var index := posmod(_target_index + direction * step, count)
		if not _combat.enemies[index].is_dead():
			_select_target(index)
			return


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	if _new_fight_button.visible:
		if key.keycode == KEY_N:
			get_viewport().set_input_as_handled()
			_on_continue_pressed()
		return
	# Same gate as the buttons: nothing happens outside the player's turn.
	if _combat == null or _combat.phase != Combat.Phase.PLAYER_TURN:
		return
	var number := key.keycode - KEY_1
	if number >= 0 and number < MAX_HAND_KEYS:
		get_viewport().set_input_as_handled()
		_play_hand_card(number)
		return
	match key.keycode:
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_on_end_turn_pressed()
		KEY_RIGHT:
			get_viewport().set_input_as_handled()
			_cycle_target(1)
		KEY_LEFT:
			get_viewport().set_input_as_handled()
			_cycle_target(-1)
		KEY_TAB:
			get_viewport().set_input_as_handled()
			_cycle_target(-1 if key.shift_pressed else 1)


func _on_continue_pressed() -> void:
	if external_combat != null:
		fight_finished.emit(_victory)
	else:
		_start_combat()


func _on_combat_ended(victory: bool) -> void:
	_victory = victory
	_result_label.text = "You slip through the gate." if victory else "You are claimed by the afterlife."
	_log_label.append_text("[b]%s[/b]\n" % ("Victory" if victory else "Defeat"))
	_new_fight_button.show()


func _on_card_played(card: CardData, targets: Array[EnemyUnit]) -> void:
	if targets.is_empty():
		_log_label.append_text("Played %s\n" % card.display_name)
		return
	var names: PackedStringArray = []
	for target in targets:
		names.append(target.display_name)
	_log_label.append_text("Played %s on %s\n" % [card.display_name, ", ".join(names)])


func _on_enemy_acted(enemy: EnemyUnit, intent: CardEffect) -> void:
	_log_label.append_text("%s: %s\n" % [enemy.display_name, intent.describe()])
