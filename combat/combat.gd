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
## `targets` are the enemies the card hit (empty for SELF cards).
signal card_played(card: CardData, targets: Array[EnemyUnit])
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

# EXPOSE turns that enemy intents applied to the player this enemy phase. They
# are held back until the player's statuses have ticked, so they start counting
# from the next enemy phase instead of ticking away unused.
var _pending_player_expose: int = 0

# The player outlives this fight, so the connection that forwards its changes to
# state_changed is removed when the fight ends; otherwise every finished fight
# would stay alive and keep re-emitting.
var _player_changed_link: Callable = state_changed.emit


## Builds a fight, or returns null (after logging why) if the enemy list is not
## 1 to MAX_ENEMIES long. Use this when the list comes from data that could be
## bad, such as resources that failed to load; `new()` only asserts, which
## release builds skip.
static func create(player_combatant: Combatant, deck: Array[CardData], enemy_datas: Array[EnemyData], rng_seed: int = 0) -> Combat:
	if enemy_datas.size() < 1 or enemy_datas.size() > MAX_ENEMIES:
		push_error("Combat.create: needs 1 to %d enemies, got %d" % [MAX_ENEMIES, enemy_datas.size()])
		return null
	return Combat.new(player_combatant, deck, enemy_datas, rng_seed)


func _init(player_combatant: Combatant, deck: Array[CardData], enemy_datas: Array[EnemyData], rng_seed: int = 0) -> void:
	assert(enemy_datas.size() >= 1 and enemy_datas.size() <= MAX_ENEMIES, "Combat needs 1 to %d enemies" % MAX_ENEMIES)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	player = player_combatant
	# The player outlives fights; statuses must not.
	player.clear_statuses()
	piles = CardPiles.new(deck, rng)
	player.changed.connect(_player_changed_link)
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


## Plays a card. For SINGLE_ENEMY cards `target_index` indexes `enemies`:
## -1 picks the first living enemy, and an invalid or defeated target rejects
## the play. ALL_ENEMIES and SELF cards ignore `target_index`. Returns false,
## changing nothing, if the play is not allowed.
func play_card(hand_index: int, target_index: int = -1) -> bool:
	if not can_play(hand_index):
		return false
	var mode := piles.hand[hand_index].target_mode
	var targets: Array[EnemyUnit] = []
	match mode:
		CardData.TargetMode.SINGLE_ENEMY:
			var target := _resolve_target(target_index)
			if target == null:
				return false
			targets.append(target)
		CardData.TargetMode.ALL_ENEMIES:
			targets = living_enemies()
	var card := piles.play(hand_index)
	energy -= card.cost
	for effect in card.effects:
		match effect.kind:
			CardEffect.Kind.DAMAGE:
				for target in targets:
					_apply(effect, player, target)
			CardEffect.Kind.EXPOSE:
				# SELF cards expose the player; others expose their targets.
				if mode == CardData.TargetMode.SELF:
					_apply(effect, player, player)
				for target in targets:
					_apply(effect, player, target)
			_:
				_apply(effect, player, player)
	card_played.emit(card, targets)
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
		enemy.tick_statuses()
		if _check_end():
			return
	# After the enemies act, so a 1-turn status on the player still covers the
	# enemy phase that follows the turn it was applied in.
	player.tick_statuses()
	# Enemy-applied EXPOSE lands after the tick: amount N exposes the player for
	# the next N enemy phases (not the one that applied it, so even later
	# enemies in that phase hit normally).
	if _pending_player_expose > 0:
		player.apply_status(Combatant.Status.EXPOSED, _pending_player_expose)
		_pending_player_expose = 0
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


## `target` receives damage and statuses; `source` receives block and draws.
## An enemy intent with EXPOSE exposes the player; see `_pending_player_expose`
## for when it takes effect.
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
		CardEffect.Kind.EXPOSE:
			if source == player:
				target.apply_status(Combatant.Status.EXPOSED, effect.amount)
			elif target == player:
				_pending_player_expose += maxi(effect.amount, 0)


func _check_end() -> bool:
	if phase == Phase.ENDED:
		return true
	var victory := living_enemies().is_empty()
	if not (victory or player.is_dead()):
		return false
	phase = Phase.ENDED
	# Block is per-fight; clear it so callers between fights do not see it stale.
	player.clear_block()
	state_changed.emit()
	# The player can only die on an enemy action and enemies only die on the
	# player's, so both cannot be true at once.
	combat_ended.emit(victory)
	player.changed.disconnect(_player_changed_link)
	return true
