class_name Combatant
extends RefCounted
## Health and block for one side of a fight. The player's instance is owned by
## the caller so HP can persist between fights.

signal changed

var display_name: String
var max_hp: int
var hp: int
var block: int = 0


func _init(combatant_name: String, max_health: int, current_health: int = -1) -> void:
	display_name = combatant_name
	max_hp = max_health
	hp = max_health if current_health < 0 else mini(current_health, max_health)


func is_dead() -> bool:
	return hp <= 0


func gain_block(amount: int) -> void:
	block += maxi(amount, 0)
	changed.emit()


func clear_block() -> void:
	block = 0
	changed.emit()


## Returns the HP actually lost after block absorbs part of the hit.
func take_damage(amount: int) -> int:
	var absorbed := mini(block, maxi(amount, 0))
	block -= absorbed
	var lost := mini(maxi(amount, 0) - absorbed, hp)
	hp -= lost
	changed.emit()
	return lost
