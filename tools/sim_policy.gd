class_name SimPolicy
extends RefCounted
## Greedy, Expose-aware card policy shared by balance_sim.gd and run_sim.gd.
## Uses only the public Combat API.


## Plays cards until the policy passes or the fight ends, then ends the turn.
## Returns false (after logging) if the policy picked an unplayable card.
static func play_turn(combat: Combat) -> bool:
	while true:
		var pick := _pick_card(combat)
		if pick == -1:
			break
		if not combat.play_card(pick, _lowest_hp_target(combat)):
			printerr("SimPolicy: policy chose an unplayable card (index %d)" % pick)
			return false
		if combat.phase != Combat.Phase.PLAYER_TURN:
			break
	combat.end_player_turn()
	return true


## Hand index to play next, or -1 to end the turn. Priority: an Expose card
## when it can set up another affordable damage card this turn, then 0-cost
## cards, then block if the enemies' intents out-damage current block, then
## damage, then anything else affordable.
static func _pick_card(combat: Combat) -> int:
	var need_block := _incoming_damage(combat) > combat.player.block
	var best := -1
	var best_rank := 99
	for i in combat.piles.hand.size():
		if not combat.can_play(i):
			continue
		var card: CardData = combat.piles.hand[i]
		var rank := 3
		if _expose_sets_up_damage(combat, i):
			rank = -1
		elif card.cost == 0:
			rank = 0
		elif need_block and _has_effect(card, CardEffect.Kind.BLOCK):
			rank = 1
		elif _has_effect(card, CardEffect.Kind.DAMAGE):
			rank = 2
		if rank < best_rank:
			best_rank = rank
			best = i
	return best


## True if hand card `index` exposes a target that is not exposed yet and the
## rest of the hand holds another affordable damage card (after paying for this
## one) to benefit. Targets match play_card's: the lowest-HP enemy for single
## target cards, every living enemy for all-enemies cards.
static func _expose_sets_up_damage(combat: Combat, index: int) -> bool:
	var card: CardData = combat.piles.hand[index]
	if card.target_mode == CardData.TargetMode.SELF or not _has_effect(card, CardEffect.Kind.EXPOSE):
		return false
	var all_exposed := true
	if card.target_mode == CardData.TargetMode.ALL_ENEMIES:
		for enemy in combat.living_enemies():
			if enemy.status_turns(Combatant.Status.EXPOSED) == 0:
				all_exposed = false
	else:
		var target := _lowest_hp_target(combat)
		all_exposed = target == -1 or combat.enemies[target].status_turns(Combatant.Status.EXPOSED) > 0
	if all_exposed:
		return false
	for j in combat.piles.hand.size():
		if j != index and _has_effect(combat.piles.hand[j], CardEffect.Kind.DAMAGE) and combat.piles.hand[j].cost <= combat.energy - card.cost:
			return true
	return false


static func _has_effect(card: CardData, kind: CardEffect.Kind) -> bool:
	for effect in card.effects:
		if effect.kind == kind:
			return true
	return false


static func _incoming_damage(combat: Combat) -> int:
	var total := 0
	for enemy in combat.living_enemies():
		var intent := enemy.current_intent()
		if intent != null and intent.kind == CardEffect.Kind.DAMAGE:
			total += intent.amount
	return total


## Index into combat.enemies of the living enemy with the least HP (first on ties).
static func _lowest_hp_target(combat: Combat) -> int:
	var best := -1
	for i in combat.enemies.size():
		var enemy := combat.enemies[i]
		if not enemy.is_dead() and (best == -1 or enemy.hp < combat.enemies[best].hp):
			best = i
	return best
