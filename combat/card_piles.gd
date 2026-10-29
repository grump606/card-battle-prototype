class_name CardPiles
extends RefCounted
## Draw pile, hand and discard pile. Shuffling uses the injected RNG so fights
## are reproducible from a seed.

var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []

var _rng: RandomNumberGenerator


func _init(deck: Array[CardData], rng: RandomNumberGenerator) -> void:
	_rng = rng
	draw_pile.append_array(deck)
	_shuffle(draw_pile)


## Draws up to `count` cards, reshuffling the discard pile when needed.
## Returns how many were actually drawn.
func draw(count: int) -> int:
	var drawn := 0
	while drawn < count:
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			draw_pile.append_array(discard_pile)
			discard_pile.clear()
			_shuffle(draw_pile)
		hand.append(draw_pile.pop_back())
		drawn += 1
	return drawn


## Moves the card at `hand_index` to the discard pile and returns it.
func play(hand_index: int) -> CardData:
	var card: CardData = hand[hand_index]
	hand.remove_at(hand_index)
	discard_pile.append(card)
	return card


func discard_hand() -> void:
	discard_pile.append_array(hand)
	hand.clear()


func _shuffle(cards: Array[CardData]) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
