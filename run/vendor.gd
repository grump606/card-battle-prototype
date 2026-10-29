class_name Vendor
extends RefCounted
## One vendor visit: three cards for sale plus two fixed services (remove a card,
## heal). Pure logic, no nodes, no RunState dependency.
##
## Wiring: `var vendor := Vendor.new(run_deck, run_rng, run_gold)`. The Vendor
## MUTATES `run_deck` (the exact array passed in) on buy_card/remove_card, and
## tracks gold in `vendor.gold`; the caller copies `vendor.gold` back into the run
## when the visit ends. Every purchase returns a Result (`ok`, `reason`, and what
## changed); a failed purchase changes nothing and gold never goes negative.
## Caller bugs (bad index, null player) also push_error; "cannot afford" and
## "already sold" are normal outcomes and only return a failed Result.

## Gold economy (placeholder numbers for tuning).
## Gold earned per enemy defeated in a won fight.
const GOLD_PER_ENEMY := 8
## Flat bonus for winning a fight, on top of the per-enemy gold.
const GOLD_WIN_BONUS := 5

const STOCK_CARDS := 3
const REMOVE_CARD_PRICE := 15
const HEAL_PRICE := 12
const HEAL_AMOUNT := 12

## Card price tiers (see card_price).
const PRICE_CHEAP := 10
const PRICE_MID := 16
const PRICE_PRICEY := 24
## Card value below MID_FROM is cheap; at or above PRICEY_FROM is pricey; else mid.
const MID_FROM := 6
const PRICEY_FROM := 12


## Gold awarded for winning a fight against `enemy_count` enemies.
## Fails loudly (and awards nothing) for a count below 1.
static func gold_for_win(enemy_count: int) -> int:
	if enemy_count < 1:
		push_error("Vendor.gold_for_win: enemy_count must be >= 1, got %d" % enemy_count)
		return 0
	return enemy_count * GOLD_PER_ENEMY + GOLD_WIN_BONUS


## Raw strength of a card: damage and block count 1 per point, expose 2 per turn,
## draw 3 per card, plus 2 per energy of cost.
static func card_value(card: CardData) -> int:
	var value := card.cost * 2
	for effect in card.effects:
		match effect.kind:
			CardEffect.Kind.DAMAGE, CardEffect.Kind.BLOCK:
				value += effect.amount
			CardEffect.Kind.EXPOSE:
				value += effect.amount * 2
			CardEffect.Kind.DRAW:
				value += effect.amount * 3
	return value


## The single price rule: value < MID_FROM -> PRICE_CHEAP, value < PRICEY_FROM ->
## PRICE_MID, otherwise PRICE_PRICEY.
static func card_price(card: CardData) -> int:
	var value := card_value(card)
	if value < MID_FROM:
		return PRICE_CHEAP
	if value < PRICEY_FROM:
		return PRICE_MID
	return PRICE_PRICEY


## Outcome of a purchase attempt. On failure `reason` says why and nothing changed.
class Result extends RefCounted:
	var ok := false
	var reason := ""
	var spent := 0
	## buy_card: the card added to the deck. remove_card: the card removed.
	var card: CardData = null
	## buy_heal: HP the player actually regained.
	var healed := 0

	static func fail(why: String) -> Result:
		var result := Result.new()
		result.reason = why
		return result


## Remaining gold; never negative.
var gold: int
var _deck: Array[CardData]
var _offers: Array[Dictionary] = []  # {card: CardData, price: int, sold: bool}
var _removed := false
var _healed := false


func _init(deck: Array[CardData], rng: RandomNumberGenerator, starting_gold: int) -> void:
	_deck = deck
	if starting_gold < 0:
		push_error("Vendor: starting gold must be >= 0, got %d" % starting_gold)
	gold = maxi(starting_gold, 0)
	if rng == null:
		push_error("Vendor: rng is required")
		return
	# Distinct card types by id, in deck order, then a seeded Fisher-Yates shuffle.
	var pool: Array[CardData] = []
	var seen := {}
	for card in StarterContent.extended_deck():
		if not seen.has(card.id):
			seen[card.id] = true
			pool.append(card)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for i in mini(STOCK_CARDS, pool.size()):
		_offers.append({"card": pool[i], "price": card_price(pool[i]), "sold": false})
	if _offers.size() < STOCK_CARDS:
		push_error("Vendor: could only stock %d of %d cards" % [_offers.size(), STOCK_CARDS])


## Cards for sale: copies of {card: CardData, price: int, sold: bool}, in display order.
func offers() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for offer in _offers:
		copy.append(offer.duplicate())
	return copy


func has_removed() -> bool:
	return _removed


func has_healed() -> bool:
	return _healed


## Buys offer `index`: appends its card (shared immutable resource, like the
## starter deck) to the deck and deducts the price.
func buy_card(index: int) -> Result:
	if index < 0 or index >= _offers.size():
		push_error("Vendor.buy_card: bad offer index %d" % index)
		return Result.fail("no such offer")
	var offer := _offers[index]
	if offer["sold"]:
		return Result.fail("already sold")
	var price: int = offer["price"]
	if gold < price:
		return Result.fail("not enough gold")
	gold -= price
	offer["sold"] = true
	_deck.append(offer["card"])
	var result := Result.new()
	result.ok = true
	result.spent = price
	result.card = offer["card"]
	return result


## Removes the card at `deck_index` of the deck. Once per visit; the last card
## can never be removed so the deck is never emptied.
func remove_card(deck_index: int) -> Result:
	if deck_index < 0 or deck_index >= _deck.size():
		push_error("Vendor.remove_card: bad deck index %d" % deck_index)
		return Result.fail("no such card")
	if _removed:
		return Result.fail("already removed a card")
	if _deck.size() <= 1:
		return Result.fail("deck cannot be emptied")
	if gold < REMOVE_CARD_PRICE:
		return Result.fail("not enough gold")
	gold -= REMOVE_CARD_PRICE
	_removed = true
	var result := Result.new()
	result.ok = true
	result.spent = REMOVE_CARD_PRICE
	result.card = _deck[deck_index]
	_deck.remove_at(deck_index)
	return result


## Heals `player` by up to HEAL_AMOUNT (calls player.heal) and deducts HEAL_PRICE.
## Once per visit; refused at full HP so gold is not wasted. `healed` is the HP
## actually regained.
func buy_heal(player: Combatant) -> Result:
	if player == null:
		push_error("Vendor.buy_heal: player is required")
		return Result.fail("no player")
	if _healed:
		return Result.fail("already healed")
	if player.hp >= player.max_hp:
		return Result.fail("already at full HP")
	if gold < HEAL_PRICE:
		return Result.fail("not enough gold")
	gold -= HEAL_PRICE
	_healed = true
	var result := Result.new()
	result.ok = true
	result.spent = HEAL_PRICE
	result.healed = player.heal(HEAL_AMOUNT)
	return result
