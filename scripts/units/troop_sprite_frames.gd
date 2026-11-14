extends RefCounted
class_name TroopSpriteFrames
## Shared frame layout for the hand supplied unit sprite sheets.

const SHEETS := {
	"warrior": preload("res://assets/troops/warrior_sheet.png"),
	"archer": preload("res://assets/troops/archer_sheet.png"),
	"mage": preload("res://assets/troops/mage_sheet.png"),
	"dragon": preload("res://assets/troops/dragon_sheet.png"),
}

const CELL_SIZES := {
	"warrior": Vector2i(128, 140),
	"archer": Vector2i(128, 140),
	"mage": Vector2i(146, 186),
	"dragon": Vector2i(160, 140),
}

const ROWS := {
	# Each row stores its pixel y offset, frame count, and row height. Heights vary in the supplied sheets.
	"warrior": {"idle": [0, 8, 151], "walk": [150, 8, 106], "attack": [254, 7, 146], "death": [398, 6, 161]},
	"archer": {"idle": [0, 8, 151], "walk": [151, 8, 122], "attack": [271, 6, 145], "death": [414, 5, 145]},
	"mage": {"idle": [0, 7, 170], "walk": [0, 7, 170], "attack": [210, 7, 188], "death": [396, 6, 163]},
	"dragon": {"idle": [0, 8, 140], "walk": [0, 8, 140], "attack": [140, 6, 140], "death": [280, 5, 140]},
}


static func texture_for(troop_id: String) -> Texture2D:
	return SHEETS.get(troop_id, SHEETS["warrior"])


static func region_for(troop_id: String, animation: String, frame: int) -> Rect2:
	var layout: Dictionary = ROWS.get(troop_id, ROWS["warrior"])
	var row_data: Array = layout.get(animation, layout["idle"])
	var cell: Vector2i = CELL_SIZES.get(troop_id, CELL_SIZES["warrior"])
	var frame_count := int(row_data[1])
	var frame_column := posmod(frame, frame_count)
	return Rect2(Vector2(frame_column * cell.x, int(row_data[0])), Vector2(cell.x, int(row_data[2])))
