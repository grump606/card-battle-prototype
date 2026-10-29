class_name Combatant
extends RefCounted
## Health, block and statuses for one side of a fight. The player's instance is
## owned by the caller so HP can persist between fights.

signal changed

enum Status { EXPOSED }

## EXPOSED multiplies incoming damage by 3/2, rounded down.
const EXPOSED_NUM := 3
const EXPOSED_DEN := 2

var display_name: String
var max_hp: int
var hp: int
var block: int = 0

var _statuses: Dictionary = {}  # Status -> remaining turns (always > 0)


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


## Remaining turns of `status`, 0 if absent.
func status_turns(status: Status) -> int:
	return _statuses.get(status, 0)


## Adds `turns` to the status duration. Non-positive turns are ignored.
func apply_status(status: Status, turns: int) -> void:
	if turns <= 0:
		return
	_statuses[status] = status_turns(status) + turns
	changed.emit()


func clear_statuses() -> void:
	_statuses.clear()
	changed.emit()


## Counts every status down by one turn; expired ones are removed.
func tick_statuses() -> void:
	for status in _statuses.keys():
		var left: int = _statuses[status] - 1
		if left <= 0:
			_statuses.erase(status)
		else:
			_statuses[status] = left
	changed.emit()


## Returns the HP actually lost. EXPOSED scales the incoming hit before block
## absorbs any of it.
func take_damage(amount: int) -> int:
	amount = maxi(amount, 0)
	if amount > 0 and status_turns(Status.EXPOSED) > 0:
		amount = maxi(amount * EXPOSED_NUM / EXPOSED_DEN, 1)
	var absorbed := mini(block, amount)
	block -= absorbed
	var lost := mini(amount - absorbed, hp)
	hp -= lost
	changed.emit()
	return lost
