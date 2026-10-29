class_name EnemyData
extends Resource
## Static definition of an enemy. It repeats its intents in order, one per turn.

@export var display_name: String
@export var max_hp: int = 20
@export var intents: Array[CardEffect] = []


static func make(enemy_name: String, hp: int, enemy_intents: Array[CardEffect]) -> EnemyData:
	var enemy := EnemyData.new()
	enemy.display_name = enemy_name
	enemy.max_hp = hp
	enemy.intents = enemy_intents
	return enemy
