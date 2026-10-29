class_name Combat
extends RefCounted
## One fight between the player and 1 to MAX_ENEMIES enemies. Holds rules only:
## no nodes, no scenes. A UI observes the signals; a run layer supplies the
## player's Combatant and deck, and reads the outcome from `combat_ended`.

enum Phase { NOT_STARTED, PLAYER_TURN, ENEMY_TURN, ENDED }

const HAND_SIZE := 5
const ENERGY_PER_TURN := 3
const MAX_ENEMIES := 3

signal state_changed
signal card_played(card: CardData)
signal enemy_acted(enemy: EnemyUnit, intent: CardEffect)
signal combat_ended(victory: bool)

var player: Combatant
## Fixed order for the whole fight. Defeated enemies stay in the list so
## target indices remain stable; use `living_enemies()` to skip them.
var enemies: Array[EnemyUnit] = []
var piles: CardPiles
var energy: int = 0
var turn: int = 0
var phase: Phase = Phase.NOT_STARTED


func _init(player_combatant: Combatant, deck: Array[CardData], enemy_datas: Array[EnemyData], rng_seed: int = 0) -> void:
	assert(enemy_datas.size() >= 1 and enemy_datas.size() <= MAX_ENEMIES, "Combat needs 1 to %d enemies" % MAX_ENEMIES)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	player = player_combatant
	piles = CardPiles.new(deck, rng)
	player.changed.connect(state_changed.emit)
	for enemy_data in enemy_datas:
		var enemy := EnemyUnit.new(enemy_data)
		enemy.changed.connect(state_changed.emit)
		enemies.append(enemy)


func start() -> void:
	assert(phase == Phase.NOT_STARTED, "Combat already started")
	_begin_player_turn()


func living_enemies() -> Array[EnemyUnit]:
	var living: Array[EnemyUnit] = []
	for enemy in enemies:
		if not enemy.is_dead():
			living.append(enemy)
	return living


func can_play(hand_index: int) -> bool:
	return (
		phase == Phase.PLAYER_TURN
		and hand_index >= 0
		and hand_index < piles.hand.size()
		and piles.hand[hand_index].cost <= energy
	)


## Plays a card on the enemy at `target_index` (an index into `enemies`).
## -1 picks the first living enemy. Returns false, changing nothing, if the
## play is not allowed or the target is invalid or already defeated.
func play_card(hand_index: int, target_index: int = -1) -> bool:
	if not can_play(hand_index):
		return false
	var target := _resolve_target(target_index)
	if target == null:
		return false
	var card := piles.play(hand_index)
	energy -= card.cost
	for effect in card.effects:
		_apply(effect, player, target)
	card_played.emit(card)
	if not _check_end():
		state_changed.emit()
	return true


func end_player_turn() -> void:
	if phase != Phase.PLAYER_TURN:
		return
	phase = Phase.ENEMY_TURN
	piles.discard_hand()
	for enemy in living_enemies():
		enemy.clear_block()
		var intent := enemy.current_intent()
		if intent != null:
			_apply(intent, enemy, player)
			enemy_acted.emit(enemy, intent)
		enemy.advance_intent()
		if _check_end():
			return
	_begin_player_turn()


func _resolve_target(target_index: int) -> EnemyUnit:
	if target_index == -1:
		var living := living_enemies()
		return null if living.is_empty() else living[0]
	if target_index < 0 or target_index >= enemies.size() or enemies[target_index].is_dead():
		return null
	return enemies[target_index]


func _begin_player_turn() -> void:
	turn += 1
	phase = Phase.PLAYER_TURN
	energy = ENERGY_PER_TURN
	player.clear_block()
	piles.draw(HAND_SIZE)
	state_changed.emit()


## `target` receives damage; `source` receives block and draws.
func _apply(effect: CardEffect, source: Combatant, target: Combatant) -> void:
	match effect.kind:
		CardEffect.Kind.DAMAGE:
			target.take_damage(effect.amount)
		CardEffect.Kind.BLOCK:
			source.gain_block(effect.amount)
		CardEffect.Kind.DRAW:
			# Only the player has a hand.
			if source == player:
				piles.draw(effect.amount)


func _check_end() -> bool:
	if phase == Phase.ENDED:
		return true
	var victory := living_enemies().is_empty()
	if not (victory or player.is_dead()):
		return false
	phase = Phase.ENDED
	state_changed.emit()
	# The player can only die on an enemy action and enemies only die on the
	# player's, so both cannot be true at once.
	combat_ended.emit(victory)
	return true
