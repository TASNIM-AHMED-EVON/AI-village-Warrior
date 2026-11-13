extends SceneTree
## Walls are only a way in. Troops must (1) share ONE breach wall instead of chewing through different walls,
## and (2) drop whatever wall they are hitting the moment a gap opens and go for the buildings behind it.

const DT := 0.05

var failures := 0
var _roots: Array[Node] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_troops_share_one_breach_wall()
	_test_everyone_goes_through_the_gap()
	_test_troop_bashing_another_wall_switches()
	_test_second_wall_layer()
	_test_reachable_buildings_come_before_walls()
	for node in _roots:
		if is_instance_valid(node):
			node.queue_free()
	if failures == 0:
		print("Wall breach checks passed.")
		quit(0)
	else:
		push_error("%d wall breach check(s) failed." % failures)
		quit(1)


func _test_troops_share_one_breach_wall() -> void:
	var battle := _make_battle([25])
	for y in [10, 30, 50]:
		battle.deploy("warrior", Vector2i(19, y))
	var wall_ids: Array[String] = []
	var all_walls := true
	for attacker in battle.attacker_units:
		all_walls = all_walls and is_instance_valid(attacker.target) and attacker.target.building_type == "wall"
		if is_instance_valid(attacker.target):
			wall_ids.append(attacker.target.building_id)
	_check(battle.attacker_units.size() == 3 and all_walls, "troops facing a sealed base all target a wall")
	_check(wall_ids.size() == 3 and wall_ids[0] == wall_ids[1] and wall_ids[1] == wall_ids[2], "they all attack the same breach wall (%s)" % str(wall_ids))
	var wall_y := int(battle.attacker_units[0].target.building_id.split("_")[2])
	_check(absi(wall_y - 29) <= 8, "the breach wall is chosen near the buildings it opens the way to (row %d)" % wall_y)
	var before := battle._breach_wall_id
	battle._assign_minimax_attack_plan(battle.attacker_units[1])
	_check(battle._breach_wall_id == before, "re-planning keeps the same breach wall")


func _test_everyone_goes_through_the_gap() -> void:
	var battle := _make_battle([25])
	for y in [10, 30, 50]:
		battle.deploy("warrior", Vector2i(19, y))
	var breach_id := battle._breach_wall_id
	battle._on_building_destroyed(breach_id)
	_run_ticks(battle, 1.5)
	var on_hall := 0
	var on_wall := 0
	for attacker in battle.attacker_units:
		if is_instance_valid(attacker.target) and attacker.target.building_type == "town_hall":
			on_hall += 1
		if is_instance_valid(attacker.target) and attacker.target.building_type == "wall":
			on_wall += 1
	_check(on_hall == 3 and on_wall == 0, "once a gap opens every troop heads for the Town Hall (%d on hall, %d on walls)" % [on_hall, on_wall])
	_check(battle._breach_wall_id == "", "the shared breach wall is cleared when it falls")


func _test_troop_bashing_another_wall_switches() -> void:
	var battle := _make_battle([25])
	battle.deploy("warrior", Vector2i(19, 30))
	battle.deploy("warrior", Vector2i(19, 12))
	var bystander: TroopActor = battle.attacker_units[1]
	var other_wall: BattleBuildingTarget = battle.building_targets["wall_25_5"]
	bystander.assign_target(other_wall)  # Busy hitting a wall far from the gap.
	other_wall.apply_damage(40, bystander.global_position)
	_check(is_instance_valid(bystander.target) and bystander.target == other_wall, "one troop is busy on a different wall")
	var gap_id := battle._breach_wall_id
	_check(gap_id != "" and gap_id != "wall_25_5", "the shared breach wall is a different wall")
	battle._on_building_destroyed(gap_id)
	_run_ticks(battle, 1.0)
	_check(is_instance_valid(other_wall) and other_wall.hp > 0, "its own wall is still standing")
	_check(is_instance_valid(bystander.target) and bystander.target.building_type == "town_hall", "yet it leaves that wall and goes for the Town Hall as soon as a gap exists")


func _test_second_wall_layer() -> void:
	var battle := _make_battle([25, 29])
	for y in [20, 38]:
		battle.deploy("warrior", Vector2i(19, y))
	var outer_id := battle._breach_wall_id
	_check(outer_id.begins_with("wall_25_"), "with two wall layers the outer wall is breached first (%s)" % outer_id)
	battle._on_building_destroyed(outer_id)
	_run_ticks(battle, 1.5)
	var inner_id := battle._breach_wall_id
	var all_on_inner := true
	for attacker in battle.attacker_units:
		all_on_inner = all_on_inner and is_instance_valid(attacker.target) and attacker.target.building_id == inner_id
	_check(inner_id.begins_with("wall_29_") and all_on_inner, "after the outer gap the troops pick ONE inner wall together (%s)" % inner_id)
	battle._on_building_destroyed(inner_id)
	_run_ticks(battle, 1.5)
	var on_hall := true
	for attacker in battle.attacker_units:
		on_hall = on_hall and is_instance_valid(attacker.target) and attacker.target.building_type == "town_hall"
	_check(on_hall, "after the inner gap they go for the Town Hall")


func _test_reachable_buildings_come_before_walls() -> void:
	var battle := _make_battle([25], true)
	battle.deploy("warrior", Vector2i(10, 20))
	var attacker: TroopActor = battle.attacker_units[0]
	_check(is_instance_valid(attacker.target) and attacker.target.building_type == "barracks", "a reachable building is always preferred to a wall")
	battle._on_building_destroyed("outside_barracks")
	_run_ticks(battle, 1.0)
	_check(is_instance_valid(attacker.target) and attacker.target.building_type == "wall", "only when nothing else is reachable does the troop breach a wall")


# ----------------------------------------------------------------------------------------------
func _make_battle(wall_columns: Array, with_outside_barracks: bool = false) -> BattleManager:
	var village := VillageModel.new()
	village.grid.clear()
	village.structures.clear()
	village.units.clear()
	_add_structure(village, "hall", "town_hall", Vector2i(33, 28), Vector2i(3, 3))
	if with_outside_barracks:
		_add_structure(village, "outside_barracks", "barracks", Vector2i(8, 30), Vector2i(3, 2))
	for column in wall_columns:
		for y in range(village.grid.height):
			_add_structure(village, "wall_%d_%d" % [column, y], "wall", Vector2i(column, y), Vector2i.ONE)
	var actors := Node2D.new()
	var targets := Node2D.new()
	root.add_child(actors)
	root.add_child(targets)
	var battle := BattleManager.new()
	root.add_child(battle)
	_roots.append_array([actors, targets, battle])
	battle.begin_battle(village, actors, targets)
	battle.set_process(false)
	return battle


func _add_structure(village: VillageModel, object_id: String, building_id: String, cell: Vector2i, footprint: Vector2i) -> void:
	var definition := BuildingCatalog.get_definition(building_id)
	if not village.grid.occupy(cell, footprint, object_id):
		push_error("Test fixture structure overlaps at %s." % str(cell))
		return
	village.structures.append({
		"id": object_id, "type": building_id, "name": str(definition.get("name", building_id)),
		"cell": cell, "footprint": footprint,
		"hp": int(definition.get("hp", 250)), "max_hp": int(definition.get("hp", 250)), "level": 1,
	})


func _run_ticks(battle: BattleManager, seconds: float) -> void:
	for _i in range(int(seconds / DT)):
		for troop in battle._all_troops():
			troop.set_process(false)
			troop.step(DT)
		battle._process(DT)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
