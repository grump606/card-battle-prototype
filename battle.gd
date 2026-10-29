extends Control
## Thin view over Combat: renders state and forwards button presses. All rules
## live in res://combat/.

const PLAYER_START_HP := 40

@onready var _enemy_row: HBoxContainer = %EnemyRow
@onready var _player_label: Label = %PlayerLabel
@onready var _energy_label: Label = %EnergyLabel
@onready var _hand_box: HBoxContainer = %HandBox
@onready var _end_turn_button: Button = %EndTurnButton
@onready var _result_label: Label = %ResultLabel
@onready var _log_label: RichTextLabel = %LogLabel
@onready var _new_fight_button: Button = %NewFightButton

var _combat: Combat
## Index into Combat.enemies that cards will target.
var _target_index: int = 0


func _ready() -> void:
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_new_fight_button.pressed.connect(_start_combat)
	_start_combat()


func _start_combat() -> void:
	var player := Combatant.new("Wanderer", PLAYER_START_HP)
	var enemy_count := randi_range(1, Combat.MAX_ENEMIES)
	_combat = Combat.new(player, StarterContent.deck(), StarterContent.early_encounter(enemy_count), randi())
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
	_player_label.text = "%s  HP %d/%d  Block %d" % [player.display_name, player.hp, player.max_hp, player.block]
	_energy_label.text = "Energy %d/%d" % [_combat.energy, Combat.ENERGY_PER_TURN]
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
		child.queue_free()
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
			button.text = "%s%s\nHP %d/%d  Block %d\nIntent: %s" % [
				marker, enemy.display_name, enemy.hp, enemy.max_hp, enemy.block,
				intent.describe() if intent != null else "-",
			]
			button.pressed.connect(_select_target.bind(i))
			if i == _target_index:
				button.modulate = Color(1.0, 0.85, 0.4)
		_enemy_row.add_child(button)


func _rebuild_hand() -> void:
	for child in _hand_box.get_children():
		child.queue_free()
	for i in _combat.piles.hand.size():
		var card := _combat.piles.hand[i]
		var button := Button.new()
		button.text = "%s (%d)\n%s" % [card.display_name, card.cost, card.describe()]
		button.disabled = not _combat.can_play(i)
		button.pressed.connect(_combat.play_card.bind(i, _target_index))
		_hand_box.add_child(button)


func _select_target(index: int) -> void:
	_target_index = index
	_refresh()


func _on_end_turn_pressed() -> void:
	_combat.end_player_turn()


func _on_combat_ended(victory: bool) -> void:
	_result_label.text = "You slip through the gate." if victory else "You are claimed by the afterlife."
	_log_label.append_text("[b]%s[/b]\n" % ("Victory" if victory else "Defeat"))
	_new_fight_button.show()


func _on_card_played(card: CardData) -> void:
	_log_label.append_text("Played %s\n" % card.display_name)


func _on_enemy_acted(enemy: EnemyUnit, intent: CardEffect) -> void:
	_log_label.append_text("%s: %s\n" % [enemy.display_name, intent.describe()])
