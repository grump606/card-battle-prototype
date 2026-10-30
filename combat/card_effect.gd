class_name CardEffect
extends Resource
## One atomic outcome of a card play or an enemy intent.
## EXPOSE (`amount` = turns): on a card it exposes its targets (the player for
## SELF cards); on an enemy intent it exposes the player for the next `amount`
## enemy phases.

## New kinds are only ever appended: .tres files store the kind as its integer value.
## HOLD: keep up to `amount` of your remaining Block into your next turn.
## DAMAGE_PER_BLOCK: damage equal to your current Block times `amount`.
## DAMAGE_IF_BLOCK: `bonus` damage if your Block is at least `threshold`, else `amount`.
## THORNS: until your next turn, each enemy attack on you also deals `amount` to that attacker.
## GAIN_ENERGY: gain `amount` energy now (it can lift energy above the per-turn amount).
## DAMAGE_PER_PLAY: `amount` plus `bonus` for each card played earlier this turn.
enum Kind { DAMAGE, BLOCK, DRAW, EXPOSE, HOLD, DAMAGE_PER_BLOCK, DAMAGE_IF_BLOCK, THORNS, GAIN_ENERGY, DAMAGE_PER_PLAY }

@export var kind: Kind = Kind.DAMAGE
@export var amount: int = 0
## Second number for kinds that need one (see DAMAGE_IF_BLOCK); 0 otherwise.
@export var bonus: int = 0
@export var threshold: int = 0


static func make(effect_kind: Kind, effect_amount: int, effect_bonus: int = 0, effect_threshold: int = 0) -> CardEffect:
	var effect := CardEffect.new()
	effect.kind = effect_kind
	effect.amount = effect_amount
	effect.bonus = effect_bonus
	effect.threshold = effect_threshold
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
		Kind.HOLD:
			return "Hold %d" % amount
		Kind.DAMAGE_PER_BLOCK:
			return "Deal damage equal to your Block" if amount == 1 else "Deal %dx your Block" % amount
		Kind.DAMAGE_IF_BLOCK:
			return "Deal %d (%d with %d+ Block)" % [amount, bonus, threshold]
		Kind.THORNS:
			return "Thorns %d" % amount
		Kind.GAIN_ENERGY:
			return "Gain %d energy" % amount
		Kind.DAMAGE_PER_PLAY:
			return "Deal %d, +%d for each card played earlier this turn" % [amount, bonus]
	return ""
