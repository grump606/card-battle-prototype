class_name StarterContent
extends RefCounted
## Placeholder content for the afterlife-escape theme. Real content should move
## to .tres resources once the card set grows. Numbers are untuned.


static func deck() -> Array[CardData]:
	var cards: Array[CardData] = []
	for i in 5:
		cards.append(CardData.make(&"shove", "Shove", 1, [CardEffect.make(CardEffect.Kind.DAMAGE, 6)]))
	for i in 4:
		cards.append(CardData.make(&"slip_past", "Slip Past", 1, [CardEffect.make(CardEffect.Kind.BLOCK, 5)]))
	cards.append(CardData.make(&"glimpse_exit", "Glimpse the Exit", 0, [CardEffect.make(CardEffect.Kind.DRAW, 2)]))
	return cards


static func warden() -> EnemyData:
	return EnemyData.make("Gate Warden", 30, [
		CardEffect.make(CardEffect.Kind.DAMAGE, 6),
		CardEffect.make(CardEffect.Kind.BLOCK, 8),
		CardEffect.make(CardEffect.Kind.DAMAGE, 11),
	])


static func lost_shade() -> EnemyData:
	return EnemyData.make("Lost Shade", 12, [
		CardEffect.make(CardEffect.Kind.DAMAGE, 4),
		CardEffect.make(CardEffect.Kind.DAMAGE, 3),
	])


## An early-run encounter with `enemy_count` enemies (clamped to 1..MAX_ENEMIES).
static func early_encounter(enemy_count: int) -> Array[EnemyData]:
	var count := clampi(enemy_count, 1, Combat.MAX_ENEMIES)
	var enemies: Array[EnemyData] = []
	if count == 1:
		enemies.append(warden())
	else:
		for i in count:
			enemies.append(lost_shade())
	return enemies
