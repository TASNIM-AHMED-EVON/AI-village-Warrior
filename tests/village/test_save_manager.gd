extends SceneTree

var failures := 0
const TEST_SAVE_PATH := "res://_test_village_layout.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var save_manager: Node = load("res://scripts/save/save_manager.gd").new()
	var village: Variant = VillageModel.new()
	village.create_starter_layout()
	var placement: Dictionary = village.try_place("wall", Vector2i(4, 4))
	_check(placement["ok"], "prepare a modified village for persistence")
	_check(save_manager.save_village(village, TEST_SAVE_PATH), "save village JSON to a test file")
	var restored: Variant = save_manager.load_village(TEST_SAVE_PATH)
	_check(restored is VillageModel, "load a village from saved JSON")
	if restored is VillageModel:
		_check(restored.structures.size() == village.structures.size(), "saved layout retains buildings and walls")
		_check(restored.get_structure_at(Vector2i(4, 4))["type"] == "wall", "saved layout retains placed wall occupancy")
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	_check(remove_error == OK, "remove the temporary test save")
	save_manager.free()
	save_manager = null
	village = null
	restored = null
	if failures == 0:
		print("Save manager checks passed.")
		quit(0)
	else:
		push_error("%d save manager check(s) failed." % failures)
		quit(1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
