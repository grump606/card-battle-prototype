class_name CardData
extends Resource
## Static definition of a card. Contains no per-combat state.

enum TargetMode { SINGLE_ENEMY, ALL_ENEMIES, SELF }

@export var id: StringName
@export var display_name: String
@export var cost: int = 1
@export var effects: Array[CardEffect] = []
## SINGLE_ENEMY: the chosen enemy. ALL_ENEMIES: every living enemy. SELF: no enemy
## is targeted. BLOCK and DRAW always affect the player.
@export var target_mode: TargetMode = TargetMode.SINGLE_ENEMY


static func make(card_id: StringName, card_name: String, card_cost: int, card_effects: Array[CardEffect], card_target_mode: TargetMode = TargetMode.SINGLE_ENEMY) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = card_name
	card.cost = card_cost
	card.effects = card_effects
	card.target_mode = card_target_mode
	return card


func describe() -> String:
	var parts: PackedStringArray = []
	for effect in effects:
		parts.append(effect.describe())
	return ", ".join(parts)
