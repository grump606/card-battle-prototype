class_name Character
extends Resource
## A playable character: who the player is, how tough they are, and the deck they
## start with. Their card pool (rewards and vendor stock) is the neutral cards plus
## the cards tagged with this character's id (see CardData.character).

@export var id: StringName
@export var display_name: String
## One line shown when choosing a character.
@export var pitch: String
@export var max_hp: int = 48
@export var starting_deck: Array[CardData] = []
