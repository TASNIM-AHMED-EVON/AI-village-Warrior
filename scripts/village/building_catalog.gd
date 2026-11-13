extends RefCounted
class_name BuildingCatalog
## Starter building stats kept separate from rendering and placement logic.

const DEFINITIONS := {
	"town_hall": {
		"name": "Town Hall", "footprint": Vector2i(3, 3), "hp": 1200,
		"cost": 0,
		"color": Color("d99c50"), "accent": Color("f3d27c"), "category": "Core",
		"description": "The heart of the village.",
	},
	"cannon": {
		"name": "Cannon", "footprint": Vector2i(2, 2), "hp": 420,
		"cost": 450,
		"color": Color("75848c"), "accent": Color("c8d1ce"), "category": "Defense",
		"description": "A sturdy ground defense.",
	},
	"archer_tower": {
		"name": "Archer Tower", "footprint": Vector2i(2, 2), "hp": 360,
		"cost": 600,
		"color": Color("8b6547"), "accent": Color("9ce3a5"), "category": "Defense",
		"description": "A watchful tower for village guards.",
	},
	"gold_mine": {
		"name": "Gold Mine", "footprint": Vector2i(2, 2), "hp": 300,
		"cost": 350,
		"color": Color("b99639"), "accent": Color("f0dc76"), "category": "Economy",
		"description": "A small source of village gold.",
	},
	"elixir_pump": {
		"name": "Elixir Pump", "footprint": Vector2i(2, 2), "hp": 300,
		"cost": 350,
		"color": Color("9f628b"), "accent": Color("efa9db"), "category": "Economy",
		"description": "Produces elixir for training and upgrades.",
	},
	"barracks": {
		"name": "Barracks", "footprint": Vector2i(3, 2), "hp": 500,
		"cost": 700,
		"color": Color("9d6747"), "accent": Color("e8bd72"), "category": "Army",
		"description": "A training ground for village troops.",
	},
	"clan_castle": {
		"name": "Clan Castle", "footprint": Vector2i(3, 3), "hp": 900,
		"cost": 800, "capacity": 12,
		"color": Color("6f7fa8"), "accent": Color("d8e2ff"), "category": "Defense",
		"description": "Garrisoned troops rush out to defend when attackers get close.",
	},
	"wall": {
		"name": "Wall", "footprint": Vector2i(1, 1), "hp": 250,
		"cost": 75,
		"color": Color("789092"), "accent": Color("c7d8c9"), "category": "Wall",
		"description": "A sturdy section of village wall.",
	},
}


static func get_definition(building_id: String) -> Dictionary:
	return DEFINITIONS.get(building_id, {})


static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for building_id in DEFINITIONS:
		ids.append(building_id)
	return ids
