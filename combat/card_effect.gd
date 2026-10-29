class_name CardEffect
extends Resource
## One atomic outcome of a card play or an enemy intent.
## EXPOSE (`amount` = turns) is only honoured on cards; enemy intents ignore it.

enum Kind { DAMAGE, BLOCK, DRAW, EXPOSE }

@export var kind: Kind = Kind.DAMAGE
@export var amount: int = 0


static func make(effect_kind: Kind, effect_amount: int) -> CardEffect:
	var effect := CardEffect.new()
	effect.kind = effect_kind
	effect.amount = effect_amount
	return effect


func describe() -> String:
	match kind:
		Kind.DAMAGE:
			return "Deal %d" % amount
		Kind.BLOCK:
			return "Block %d" % amount
		Kind.DRAW:
			return "Draw %d" % amount
		Kind.EXPOSE:
			return "Expose %d" % amount
	return ""
