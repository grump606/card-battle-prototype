extends SceneTree
## Headless balance simulation: plays many seeded fights with a simple greedy
## policy and prints win rate, turns and remaining HP per encounter size, then
## the win rate per enemy type (over the fights it appeared in) for each size.
## Run: godot --headless --path . -s res://tools/balance_sim.gd -- --fights 500 --seed 1
## Uses only the public Combat API and never mutates shared resources.

const PLAYER_START_HP := 40 # keep in sync with battle.gd
const TURN_CAP := 50 # a fight still running after this many turns is a stall
const DEFAULT_FIGHTS := 500
const DEFAULT_SEED := 1
const USAGE := "Usage: godot --headless --path . -s res://tools/balance_sim.gd -- [--fights N] [--seed S] [--help]\n  --fights N  fights per encounter size, integer >= 1 (default 500)\n  --seed S    base random seed, integer (default 1)\n  --help      print this usage and exit 0"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if "--help" in args:
		print(USAGE)
		quit(0)
		return
	var opts := _parse_args(args)
	if opts.is_empty():
		quit(2)
		return
	var fights: int = opts["fights"]
	var base_seed: int = opts["seed"]
	var deck := StarterContent.extended_deck()
	if deck.is_empty():
		printerr("balance_sim: extended deck failed to load")
		quit(1)
		return

	print("Balance sim: %d fights per size, seed %d, player HP %d, turn cap %d" % [fights, base_seed, PLAYER_START_HP, TURN_CAP])
	print("%-8s %8s %10s %12s %7s" % ["enemies", "win rate", "avg turns", "avg HP (win)", "stalls"])
	var breakdown: Array[Dictionary] = [] # per size: enemy name -> [fights, wins]
	for count in range(1, Combat.MAX_ENEMIES + 1):
		var wins := 0
		var stalls := 0
		var total_turns := 0
		var win_hp := 0
		var by_enemy := {}
		for i in fights:
			var fight_seed := base_seed * 1000003 + count * 100003 + i
			var rng := RandomNumberGenerator.new()
			rng.seed = fight_seed
			var enemy_datas := StarterContent.varied_encounter(count, rng)
			if enemy_datas.size() != count:
				printerr("balance_sim: encounter of %d enemies failed to load" % count)
				quit(1)
				return
			var player := Combatant.new("Sim", PLAYER_START_HP)
			var combat := Combat.new(player, deck, enemy_datas, fight_seed)
			var result := _run_fight(combat)
			total_turns += combat.turn
			var seen := {}
			for data in enemy_datas:
				if seen.has(data.display_name):
					continue
				seen[data.display_name] = true
				var tally: Array = by_enemy.get(data.display_name, [0, 0])
				tally[0] += 1
				if result == 1:
					tally[1] += 1
				by_enemy[data.display_name] = tally
			if result == 1:
				wins += 1
				win_hp += player.hp
			elif result == 0:
				stalls += 1
		print("%-8d %7.1f%% %10.2f %12s %7d" % [
			count,
			100.0 * wins / fights,
			float(total_turns) / fights,
			"%.2f" % (float(win_hp) / wins) if wins > 0 else "n/a",
			stalls,
		])
		breakdown.append(by_enemy)
	print("")
	print("Win rate by enemy type (fights in which it appeared; stalls count as not won)")
	print("%-8s %-20s %8s %8s" % ["enemies", "enemy", "fights", "win rate"])
	for size in breakdown.size():
		var names: Array = breakdown[size].keys()
		names.sort()
		for enemy_name: String in names:
			var tally: Array = breakdown[size][enemy_name]
			print("%-8d %-20s %8d %7.1f%%" % [size + 1, enemy_name, tally[0], 100.0 * tally[1] / tally[0]])
	quit(0)


## Returns {fights, seed} or an empty dictionary (after printing usage) on bad input.
func _parse_args(args: PackedStringArray) -> Dictionary:
	var opts := {"fights": DEFAULT_FIGHTS, "seed": DEFAULT_SEED}
	var i := 0
	while i < args.size():
		var name := args[i]
		if name != "--fights" and name != "--seed":
			printerr("balance_sim: unknown argument '%s'\n%s" % [name, USAGE])
			return {}
		if i + 1 >= args.size() or not args[i + 1].is_valid_int():
			printerr("balance_sim: %s needs an integer value\n%s" % [name, USAGE])
			return {}
		var value := args[i + 1].to_int()
		if name == "--fights":
			if value < 1:
				printerr("balance_sim: --fights must be >= 1\n%s" % USAGE)
				return {}
			opts["fights"] = value
		else:
			opts["seed"] = value
		i += 2
	return opts


## Plays one fight. Returns 1 for a win, -1 for a loss, 0 for a stall.
func _run_fight(combat: Combat) -> int:
	var outcome := [0]
	combat.combat_ended.connect(func(victory: bool) -> void: outcome[0] = 1 if victory else -1)
	combat.start()
	while combat.phase == Combat.Phase.PLAYER_TURN:
		if combat.turn > TURN_CAP:
			return 0
		while true:
			var pick := _pick_card(combat)
			if pick == -1:
				break
			if not combat.play_card(pick, _lowest_hp_target(combat)):
				printerr("balance_sim: policy chose an unplayable card (index %d)" % pick)
				quit(1)
				return 0
			if combat.phase != Combat.Phase.PLAYER_TURN:
				break
		combat.end_player_turn()
	return outcome[0]


## Hand index to play next, or -1 to end the turn. Priority: an Expose card
## when it can set up another affordable damage card this turn, then 0-cost
## cards, then block if the enemies' intents out-damage current block, then
## damage, then anything else affordable.
func _pick_card(combat: Combat) -> int:
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
func _expose_sets_up_damage(combat: Combat, index: int) -> bool:
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


func _has_effect(card: CardData, kind: CardEffect.Kind) -> bool:
	for effect in card.effects:
		if effect.kind == kind:
			return true
	return false


func _incoming_damage(combat: Combat) -> int:
	var total := 0
	for enemy in combat.living_enemies():
		var intent := enemy.current_intent()
		if intent != null and intent.kind == CardEffect.Kind.DAMAGE:
			total += intent.amount
	return total


## Index into combat.enemies of the living enemy with the least HP (first on ties).
func _lowest_hp_target(combat: Combat) -> int:
	var best := -1
	for i in combat.enemies.size():
		var enemy := combat.enemies[i]
		if not enemy.is_dead() and (best == -1 or enemy.hp < combat.enemies[best].hp):
			best = i
	return best
