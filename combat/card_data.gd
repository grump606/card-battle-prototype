class_name CardData
extends Resource
## Static definition of a card. Contains no per-combat state.

@export var id: StringName
@export var display_name: String
@export var cost: int = 1
@export var effects: Array[CardEffect] = []


static func make(card_id: StringName, card_name: String, card_cost: int, card_effects: Array[CardEffect]) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = card_name
	card.cost = card_cost
	card.effects = card_effects
	return card


func describe() -> String:
	var parts: PackedStringArray = []
	for effect in effects:
		parts.append(effect.describe())
	return ", ".join(parts)
