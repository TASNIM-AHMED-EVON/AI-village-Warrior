extends Node
## Local JSON persistence. File access stays outside gameplay and renderer code.

const VILLAGE_PATH := "user://village_layout.json"


func save_village(village: VillageModel, save_path: String = VILLAGE_PATH) -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open village save file: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(village.serialize(), "\t"))
	file.close()
	return true


func load_village(save_path: String = VILLAGE_PATH) -> Variant:
	if not FileAccess.file_exists(save_path):
		return null
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_error("Could not read village save file: %s" % error_string(FileAccess.get_open_error()))
		return null
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		push_error("Village save contains invalid JSON.")
		return null
	var village := VillageModel.new()
	if not village.deserialize(json.data):
		push_error("Village save contains invalid layout data.")
		return null
	return village


func get_village_save_path() -> String:
	return ProjectSettings.globalize_path(VILLAGE_PATH)
