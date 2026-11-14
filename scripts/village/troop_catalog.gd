extends RefCounted
class_name TroopCatalog

const MAX_LEVEL := 10
const LEVEL_BONUS := 0.20  # +20% hit points and damage per troop level above 1.

const DEFINITIONS := {
	"warrior": {
		"name": "Warrior", "hp": 180, "damage": 24, "range": 1,
		"move_speed": 92.0, "attack_speed": 1.0, "cost": 20, "housing_space": 1,
		"color": Color("df7456"),
		"description": "A reliable frontline village guard.",
	},
	"mage": {
		"name": "Mage", "hp": 120, "damage": 40, "range": 5,
		"move_speed": 65.0, "attack_speed": 1.4, "cost": 50, "housing_space": 4,
		"color": Color("9d73d1"), "projectile": "magic",
		"description": "A fragile ranged attacker with powerful magic.",
	},
	"goblin": {
		"name": "Goblin", "hp": 90, "damage": 20, "range": 1,
		"move_speed": 150.0, "attack_speed": 0.65, "cost": 30, "housing_space": 2,
		"color": Color("8dc15d"),
		"description": "A fast raider that favors resource buildings.",
	},
	"archer": {
		"name": "Archer", "hp": 100, "damage": 28, "range": 5,
		"move_speed": 72.0, "attack_speed": 1.1, "cost": 35, "housing_space": 2,
		"color": Color("e58d6b"), "projectile": "arrow",
		"description": "A light ranged troop that attacks exposed targets.",
	},
	"dragon": {
		"name": "Dragon", "hp": 1100, "damage": 15, "range": 4,
		"move_speed": 76.0, "attack_speed": 0.2, "cost": 400, "housing_space": 12,
		"color": Color("d6523a"), "projectile": "fire", "flying": true,
		"description": "Flies over walls and scorches targets with a continuous stream of fire. Ground cannons cannot hit it.",
	},
	"tank": {
		"name": "Tank", "hp": 700, "damage": 55, "range": 1,
		"move_speed": 40.0, "attack_speed": 1.8, "cost": 120, "housing_space": 8,
		"color": Color("758a9b"),
		"description": "A slow, durable frontline unit.",
	},
}


static func get_definition(troop_id: String) -> Dictionary:
	return DEFINITIONS.get(troop_id, {})


static func stat_multiplier(level: int) -> float:
	return 1.0 + LEVEL_BONUS * float(clampi(level, 1, MAX_LEVEL) - 1)


static func hp_at_level(troop_id: String, level: int) -> int:
	return roundi(float(get_definition(troop_id).get("hp", 1)) * stat_multiplier(level))


static func damage_at_level(troop_id: String, level: int) -> int:
	return roundi(float(get_definition(troop_id).get("damage", 1)) * stat_multiplier(level))


## Elixir needed to research the next level, given the troop's current level.
static func upgrade_cost(troop_id: String, level: int) -> int:
	return int(get_definition(troop_id).get("cost", 20)) * 10 * maxi(level, 1)


static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for troop_id in DEFINITIONS:
		ids.append(troop_id)
	return ids
