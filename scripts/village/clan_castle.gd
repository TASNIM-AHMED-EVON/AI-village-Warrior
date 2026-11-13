extends RefCounted
class_name ClanCastle
## Garrison rules for the Clan Castle: what troops it holds and how far it reaches in battle.
## Data-only, so both the village editor and the battle simulation share one definition.

const BUILDING_ID := "clan_castle"
## An attacker closer than this (world pixels) to the castle centre releases the garrison.
const TRIGGER_RADIUS := 260.0
## Released defenders chase attackers inside this radius and return home when none remain.
const LEASH_RADIUS := 420.0
const PRESETS := [
	{"name": "Balanced", "troops": {"warrior": 2, "archer": 2, "mage": 1}},
	{"name": "Archers", "troops": {"archer": 6}},
	{"name": "Warriors", "troops": {"warrior": 8, "archer": 2}},
	{"name": "Tank Guard", "troops": {"tank": 1, "warrior": 4}},
]


static func capacity() -> int:
	return int(BuildingCatalog.get_definition(BUILDING_ID).get("capacity", 0))


static func housing_used(garrison: Dictionary) -> int:
	var used := 0
	for troop_id in garrison:
		var definition := TroopCatalog.get_definition(str(troop_id))
		used += int(definition.get("housing_space", 0)) * int(garrison[troop_id])
	return used


## Returns a clean {troop_id: count} dictionary that never exceeds the castle capacity.
## Anything that is not a Dictionary (missing/corrupt save data) becomes the default garrison.
static func sanitize(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return default_garrison()
	var clean: Dictionary = {}
	var used := 0
	var limit := capacity()
	for troop_id in TroopCatalog.all_ids():
		var wanted := maxi(0, int(raw.get(troop_id, 0)))
		var space := int(TroopCatalog.get_definition(troop_id).get("housing_space", 1))
		var fits := floori(float(maxi(0, limit - used)) / float(maxi(space, 1)))
		var count := mini(wanted, fits)
		if count > 0:
			clean[troop_id] = count
			used += count * space
	return clean


static func preset_count() -> int:
	return PRESETS.size()


static func preset_name(index: int) -> String:
	return str(PRESETS[posmod(index, PRESETS.size())]["name"])


static func preset_garrison(index: int) -> Dictionary:
	return sanitize(PRESETS[posmod(index, PRESETS.size())]["troops"])


static func default_garrison() -> Dictionary:
	return preset_garrison(0)


## Index of the preset equal to `garrison`, or -1 for a custom composition.
static func preset_index_of(garrison: Dictionary) -> int:
	for index in range(PRESETS.size()):
		if preset_garrison(index) == sanitize(garrison):
			return index
	return -1


static func describe(garrison: Dictionary) -> String:
	var parts: Array[String] = []
	for troop_id in TroopCatalog.all_ids():
		var count := int(garrison.get(troop_id, 0))
		if count > 0:
			parts.append("%d %s" % [count, str(TroopCatalog.get_definition(troop_id)["name"])])
	return "Empty" if parts.is_empty() else ", ".join(parts)


## Troop ids expanded in catalog order, e.g. {"warrior": 2, "archer": 1} -> [warrior, warrior, archer].
static func expand(garrison: Dictionary) -> Array[String]:
	var troops: Array[String] = []
	for troop_id in TroopCatalog.all_ids():
		for _copy in range(maxi(0, int(garrison.get(troop_id, 0)))):
			troops.append(troop_id)
	return troops
