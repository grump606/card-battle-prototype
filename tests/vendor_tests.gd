extends RefCounted
## Tests for the vendor module.
## run() returns the failure count and prints a "FAIL: ..." line per failure.

var _failures := 0


func run() -> int:
	_failures = 0
	_test_stock()
	_test_prices()
	_test_buy_card()
	_test_remove_card()
	_test_buy_heal()
	_test_failed_purchases_change_nothing()
	_test_gold_for_win()
	return _failures


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _vendor(seed_value: int, gold: int, deck: Array[CardData] = []) -> Vendor:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Vendor.new(deck, rng, gold)


func _ids(vendor: Vendor) -> Array:
	var ids: Array = []
	for offer in vendor.offers():
		ids.append((offer["card"] as CardData).id)
	return ids


func _test_stock() -> void:
	var seen := {}
	for seed_value in 40:
		var ids := _ids(_vendor(seed_value, 0))
		_check(ids.size() == Vendor.STOCK_CARDS, "stock size for seed %d" % seed_value)
		var distinct := {}
		for id in ids:
			distinct[id] = true
			seen[id] = true
		_check(distinct.size() == ids.size(), "stock distinct for seed %d" % seed_value)
		_check(ids == _ids(_vendor(seed_value, 0)), "stock deterministic for seed %d" % seed_value)
	_check(seen.size() > Vendor.STOCK_CARDS, "different seeds give varied stock")
	for offer in _vendor(1, 0).offers():
		_check(not offer["sold"] and offer["price"] > 0, "fresh offer unsold with a price")


func _test_prices() -> void:
	var cheap := CardData.make(&"t_cheap", "Cheap", 0, [CardEffect.make(CardEffect.Kind.BLOCK, 2)] as Array[CardEffect])
	var mid := CardData.make(&"t_mid", "Mid", 1, [CardEffect.make(CardEffect.Kind.DAMAGE, 6)] as Array[CardEffect])
	var big := CardData.make(&"t_big", "Big", 2, [CardEffect.make(CardEffect.Kind.DAMAGE, 14)] as Array[CardEffect])
	var draw := CardData.make(&"t_draw", "Draw", 0, [CardEffect.make(CardEffect.Kind.DRAW, 2)] as Array[CardEffect])
	_check(Vendor.card_price(cheap) == Vendor.PRICE_CHEAP, "block 2 cost 0 is cheap")
	_check(Vendor.card_price(mid) == Vendor.PRICE_MID, "damage 6 cost 1 is mid")
	_check(Vendor.card_price(big) == Vendor.PRICE_PRICEY, "damage 14 cost 2 is pricey")
	_check(Vendor.card_value(draw) == 6 and Vendor.card_price(draw) == Vendor.PRICE_MID, "draw counts 3 per card")
	_check(Vendor.PRICE_CHEAP < Vendor.PRICE_MID and Vendor.PRICE_MID < Vendor.PRICE_PRICEY, "tiers ascend")


func _test_buy_card() -> void:
	var deck := StarterContent.deck()
	var before := deck.size()
	var vendor := _vendor(3, 100, deck)
	var offer := vendor.offers()[0]
	var result := vendor.buy_card(0)
	_check(result.ok and result.spent == offer["price"] and result.card == offer["card"], "buy_card succeeds")
	_check(vendor.gold == 100 - offer["price"], "buy_card deducts gold")
	_check(deck.size() == before + 1 and deck[deck.size() - 1] == offer["card"], "buy_card appends to the passed deck")
	_check(vendor.offers()[0]["sold"], "offer marked sold")
	var gold_after := vendor.gold
	var again := vendor.buy_card(0)
	_check(not again.ok and again.reason != "", "double buy refused with a reason")
	_check(vendor.gold == gold_after and deck.size() == before + 1, "double buy changes nothing")
	_check(vendor.buy_card(1).ok, "other offer still buyable")


func _test_remove_card() -> void:
	var deck := StarterContent.deck()
	var first := deck[0]
	var vendor := _vendor(3, 100, deck)
	var result := vendor.remove_card(0)
	_check(result.ok and result.card == first and result.spent == Vendor.REMOVE_CARD_PRICE, "remove_card succeeds")
	_check(deck.size() == 9, "remove_card shrinks the passed deck")
	_check(vendor.gold == 100 - Vendor.REMOVE_CARD_PRICE and vendor.has_removed(), "remove_card deducts gold once")
	var again := vendor.remove_card(0)
	_check(not again.ok and deck.size() == 9 and vendor.gold == 100 - Vendor.REMOVE_CARD_PRICE, "double remove refused, nothing changed")
	var fresh := _vendor(3, 100, deck)
	_check(not fresh.remove_card(-1).ok and not fresh.remove_card(deck.size()).ok, "bad indices refused")
	_check(deck.size() == 9 and fresh.gold == 100 and not fresh.has_removed(), "bad index changes nothing")
	var single: Array[CardData] = [first]
	var lone := _vendor(3, 100, single)
	_check(not lone.remove_card(0).ok and single.size() == 1 and lone.gold == 100, "deck of 1 cannot be emptied")
	# Removal targets the chosen index, not just the first card.
	var pair: Array[CardData] = [first, StarterContent.deck()[9]]
	var keep := pair[1]
	var chosen := _vendor(3, 100, pair).remove_card(0)
	_check(chosen.ok and pair.size() == 1 and pair[0] == keep, "remove_card removes the chosen index")


func _test_buy_heal() -> void:
	var player := Combatant.new("Soul", 40, 20)
	var vendor := _vendor(3, 50)
	var result := vendor.buy_heal(player)
	_check(result.ok and result.healed == Vendor.HEAL_AMOUNT and player.hp == 20 + Vendor.HEAL_AMOUNT, "heal restores HEAL_AMOUNT")
	_check(vendor.gold == 50 - Vendor.HEAL_PRICE and vendor.has_healed(), "heal deducts gold")
	var hp_after := player.hp
	var again := vendor.buy_heal(player)
	_check(not again.ok and vendor.gold == 50 - Vendor.HEAL_PRICE and player.hp == hp_after, "double heal refused, nothing changed")
	var near := Combatant.new("Soul", 40, 38)
	var capped := _vendor(3, 50).buy_heal(near)
	_check(capped.ok and capped.healed == 2 and near.hp == 40, "heal reports HP actually regained")
	var full := Combatant.new("Soul", 40)
	var full_vendor := _vendor(3, 50)
	_check(not full_vendor.buy_heal(full).ok and full_vendor.gold == 50 and not full_vendor.has_healed(), "heal at full HP refused, gold kept")
	var hurt := Combatant.new("Soul", 40, 10)
	var poor := _vendor(3, Vendor.HEAL_PRICE - 1)
	_check(not poor.buy_heal(hurt).ok and hurt.hp == 10 and poor.gold == Vendor.HEAL_PRICE - 1, "heal without gold refused")


func _test_failed_purchases_change_nothing() -> void:
	var deck := StarterContent.deck()
	var snapshot := deck.duplicate()
	var vendor := _vendor(5, 1, deck)
	var hurt := Combatant.new("Soul", 40, 10)
	_check(not vendor.buy_card(0).ok and not vendor.remove_card(0).ok and not vendor.buy_heal(hurt).ok, "all purchases refused with 1 gold")
	_check(vendor.gold == 1 and deck == snapshot and hurt.hp == 10, "failed purchases change nothing")
	_check(not vendor.has_removed() and not vendor.has_healed() and not vendor.offers()[0]["sold"], "failed purchases set no flags")
	_check(not vendor.buy_card(-1).ok and not vendor.buy_card(Vendor.STOCK_CARDS).ok, "bad offer index refused")
	# Spend everything available: gold must never go negative.
	var rich := _vendor(5, 40, deck)
	for i in Vendor.STOCK_CARDS:
		rich.buy_card(i)
		_check(rich.gold >= 0, "gold never negative after buy %d" % i)
	rich.remove_card(0)
	rich.buy_heal(hurt)
	_check(rich.gold >= 0, "gold never negative after services")


func _test_gold_for_win() -> void:
	_check(Vendor.gold_for_win(1) == Vendor.GOLD_PER_ENEMY + Vendor.GOLD_WIN_BONUS, "gold_for_win(1)")
	_check(Vendor.gold_for_win(3) == 3 * Vendor.GOLD_PER_ENEMY + Vendor.GOLD_WIN_BONUS, "gold_for_win(3)")
	_check(Vendor.gold_for_win(2) > Vendor.gold_for_win(1), "more enemies pay more")
	_check(Vendor.gold_for_win(0) == 0, "gold_for_win(0) awards nothing")
