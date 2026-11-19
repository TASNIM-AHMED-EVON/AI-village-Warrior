extends RefCounted
class_name TrialVillage
## The fixed village used by the AI Trial (AI vs AI). It is a hand-designed "fortress" so the attacking AI has
## something real to analyse: a walled core with four defenses, a Clan Castle on the east flank, and soft
## outlying buildings. It is built fresh each time and never touches the player's saved village.

const ARMY := {"warrior": 4, "archer": 5, "mage": 2, "goblin": 4, "tank": 3, "dragon": 2}
## Upgrade steps applied to every cannon and archer tower, so the fortress hits back with real hit points.
const DEFENSE_UPGRADES := 3


static func build() -> VillageModel:
	var village := VillageModel.new()
	village.grid.clear()
	village.structures.clear()
	village.units.clear()
	village.troop_levels = {}
	village.gold = VillageModel.FULL_RESOURCE_AMOUNT
	village.elixir = VillageModel.FULL_RESOURCE_AMOUNT
	village.gems = VillageModel.FULL_RESOURCE_AMOUNT
	village.army = ARMY.duplicate(true)
	# Walled core: Town Hall in the middle, a cannon and an archer tower on opposite corners.
	village.add_layout_structure("town_hall", Vector2i(30, 30))
	village.add_layout_structure("cannon", Vector2i(26, 26))
	village.add_layout_structure("cannon", Vector2i(34, 34))
	village.add_layout_structure("archer_tower", Vector2i(34, 26))
	village.add_layout_structure("archer_tower", Vector2i(26, 34))
	village.add_layout_structure("wizard_tower", Vector2i(30, 26))
	village.add_layout_structure("gold_mine", Vector2i(26, 30))
	village.add_layout_structure("elixir_pump", Vector2i(34, 30))
	for index in range(24, 38):
		village.add_layout_structure("wall", Vector2i(index, 24))
		village.add_layout_structure("wall", Vector2i(index, 37))
	for index in range(25, 37):
		village.add_layout_structure("wall", Vector2i(24, index))
		village.add_layout_structure("wall", Vector2i(37, index))
	# Outer ring of the fortress: a strong east flank (Clan Castle + tower), and softer west / north / south.
	village.add_layout_structure("clan_castle", Vector2i(42, 30))
	village.add_layout_structure("archer_tower", Vector2i(41, 40))
	village.add_layout_structure("cannon", Vector2i(17, 30))
	village.add_layout_structure("barracks", Vector2i(29, 17))
	village.add_layout_structure("laboratory", Vector2i(29, 42))
	village.add_layout_structure("gold_mine", Vector2i(19, 19))
	village.add_layout_structure("elixir_pump", Vector2i(19, 41))
	for index in range(27, 34):
		village.add_layout_structure("wall", Vector2i(index, 15))
		village.add_layout_structure("wall", Vector2i(index, 46))
	for structure in village.structures:
		var type := str(structure["type"])
		if type == "cannon" or type == "archer_tower" or type == "wizard_tower" or type == "town_hall":
			for _step in range(DEFENSE_UPGRADES):
				village.upgrade_structure(structure["id"])
		elif type == "clan_castle":
			village.set_castle_garrison(structure["id"], 2)  # "Warriors" preset: a big melee garrison.
	return village
