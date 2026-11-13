extends SceneTree
## Clan Castle: garrison data, saving, trigger/release, defender behaviour and battle integration.

const DT := 0.05

var failures := 0
var _roots: Array[Node] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_garrison_rules()
	_test_village_model()
	_test_trigger_and_release()
	_test_defenders_fight_and_go_home()
	_test_troop_versus_troop_combat()
	_test_castle_destroyed_before_release()
	_test_castle_destroyed_after_release()
	_test_controls_reach_defenders()
	_test_replan_queue_and_recovery()
	_test_defender_death_and_result()
	for node in _roots:
		if is_instance_valid(node):
			node.queue_free()
	if failures == 0:
		print("Clan Castle checks passed.")
		quit(0)
	else:
		push_error("%d Clan Castle check(s) failed." % failures)
		quit(1)


# ----------------------------------------------------------------------------------------------
func _test_garrison_rules() -> void:
	_check(ClanCastle.capacity() == 12, "Clan Castle holds 12 housing space")
	for index in range(ClanCastle.preset_count()):
		var garrison := ClanCastle.preset_garrison(index)
		_check(ClanCastle.housing_used(garrison) <= ClanCastle.capacity(), "preset %s fits the capacity" % ClanCastle.preset_name(index))
		_check(ClanCastle.preset_index_of(garrison) == index, "preset %s is recognised again" % ClanCastle.preset_name(index))
	var overflow := ClanCastle.sanitize({"warrior": 100, "ghost": 4, "tank": -2, "archer": "3"})
	_check(ClanCastle.housing_used(overflow) <= ClanCastle.capacity(), "oversized garrison is trimmed to capacity")
	_check(not overflow.has("ghost") and not overflow.has("tank"), "unknown and negative troops are dropped")
	_check(ClanCastle.sanitize("garbage") == ClanCastle.default_garrison(), "corrupt garrison data falls back to the default")
	_check(ClanCastle.sanitize(null) == ClanCastle.default_garrison(), "missing garrison data falls back to the default")
	_check(ClanCastle.expand({"warrior": 2, "archer": 1}).size() == 3, "garrison expands into individual troops")
	_check(ClanCastle.describe({}) == "Empty", "empty garrison is described as Empty")
	_check(ClanCastle.preset_index_of({"warrior": 1}) == -1, "custom garrisons are not mistaken for a preset")


func _test_village_model() -> void:
	var village := VillageModel.new()
	village.create_starter_layout()
	var castle := _castle_of(village)
	_check(not castle.is_empty(), "starter village contains a Clan Castle")
	_check(castle["footprint"] == Vector2i(3, 3), "Clan Castle is a 3x3 building")
	_check(castle["garrison"] == ClanCastle.default_garrison(), "new castle starts with the default garrison")
	var placed := village.try_place("clan_castle", Vector2i(5, 5))
	_check(placed["ok"] and placed["object"]["garrison"] == ClanCastle.default_garrison(), "a newly built Clan Castle gets a garrison")
	var cycled := village.cycle_castle_garrison(castle["id"])
	_check(cycled["ok"] and castle["garrison"] == ClanCastle.preset_garrison(1), "cycling the garrison moves to the next preset")
	for _i in range(ClanCastle.preset_count() - 1):
		village.cycle_castle_garrison(castle["id"])
	_check(castle["garrison"] == ClanCastle.preset_garrison(0), "cycling wraps back to the first preset")
	_check(not village.cycle_castle_garrison("missing")["ok"], "cycling an unknown building fails safely")
	var cannon := village.try_place("cannon", Vector2i(10, 5))
	_check(not village.set_castle_garrison(cannon["object"]["id"], 0)["ok"], "only a Clan Castle accepts a garrison")
	village.set_castle_garrison(castle["id"], 2)
	var json_text := JSON.stringify(village.serialize())
	var restored := VillageModel.new()
	_check(restored.deserialize(JSON.parse_string(json_text)), "village with a castle round-trips through JSON")
	_check(_castle_of(restored)["garrison"] == ClanCastle.preset_garrison(2), "garrison survives saving and loading")
	# A hand-edited save must never yield an over-capacity garrison.
	var tampered: Dictionary = JSON.parse_string(json_text)
	for structure in tampered["structures"]:
		if structure["type"] == "clan_castle":
			structure["garrison"] = {"warrior": 999, "mage": 999}
	var tampered_village := VillageModel.new()
	tampered_village.deserialize(tampered)
	_check(ClanCastle.housing_used(_castle_of(tampered_village)["garrison"]) <= ClanCastle.capacity(), "tampered garrison is clamped on load")
	var legacy: Dictionary = JSON.parse_string(json_text)
	for structure in legacy["structures"]:
		structure.erase("garrison")
	var legacy_village := VillageModel.new()
	legacy_village.deserialize(legacy)
	_check(_castle_of(legacy_village)["garrison"] == ClanCastle.default_garrison(), "saves without garrison data load with the default garrison")


# ----------------------------------------------------------------------------------------------
func _test_trigger_and_release() -> void:
	var setup := _new_battle()
	var battle: BattleManager = setup["battle"]
	var castle_id: String = setup["castle_id"]
	var castle_pos: Vector2 = setup["castle_pos"]
	_check(battle.castles.has(castle_id) and not bool(battle.castles[castle_id]["released"]), "battle registers an untriggered Clan Castle")
	var far_cell := _find_cell(battle, castle_pos, false)
	_check(battle.deploy("warrior", far_cell), "deploys a Warrior far from the castle")
	_run_ticks(battle, 3.0)
	_check(battle.defenders_released == 0 and battle.defender_units.is_empty(), "a distant attacker does not trigger the garrison")
	var near_cell := _find_cell(battle, castle_pos, true)
	_check(battle.deploy("warrior", near_cell), "deploys a Warrior inside the trigger radius")
	_run_ticks(battle, 0.2)
	var expected := ClanCastle.expand(ClanCastle.default_garrison()).size()
	_check(bool(battle.castles[castle_id]["released"]), "an attacker inside the trigger radius releases the garrison")
	_check(battle.defender_units.size() == expected and battle.defenders_released == expected, "every garrisoned troop is released exactly once")
	var all_defenders := true
	var all_on_free_cells := true
	var in_tree := true
	for defender in battle.defender_units:
		all_defenders = all_defenders and defender.team == TroopActor.Team.DEFENDER
		var cell := battle.village.grid.world_to_cell(defender.global_position)
		all_on_free_cells = all_on_free_cells and not battle.village.grid.occupied.has(cell)
		in_tree = in_tree and defender.is_inside_tree()
	_check(all_defenders and in_tree, "released troops are defender-team actors in the scene")
	_check(all_on_free_cells, "defenders appear on free tiles, not inside buildings")
	_run_ticks(battle, 1.0)
	_check(battle.defenders_released == expected, "the garrison is never released twice")
	_check(int(battle.last_defender_decision.get("depth", 0)) >= 1, "defenders run the tactical search")


func _test_defenders_fight_and_go_home() -> void:
	var setup := _new_battle()
	var battle: BattleManager = setup["battle"]
	var castle_pos: Vector2 = setup["castle_pos"]
	for i in range(6):
		battle.deploy("warrior", _find_cell(battle, castle_pos, true, i))
	var attackers: Array[TroopActor] = []
	for attacker in battle.attacker_units:
		attackers.append(attacker)
	var defender_chased_attacker := false
	var attacker_fought_defender := false
	for _i in range(int(12.0 / DT)):
		_tick(battle, DT)
		for defender in battle.defender_units:
			if is_instance_valid(defender.target) and defender.target is TroopActor and defender.target.team == TroopActor.Team.ATTACKER:
				defender_chased_attacker = true
		for attacker in attackers:
			if is_instance_valid(attacker.target) and attacker.target is TroopActor:
				attacker_fought_defender = true
	_check(defender_chased_attacker, "defenders chase and target attackers")
	_check(attacker_fought_defender, "attackers fight back against defending troops")
	_check(attackers.any(func(a: TroopActor) -> bool: return a.hp < a.max_hp), "defenders damage the attackers")

	# Defenders return home once no attacker is within reach. One healthy attacker keeps the battle running.
	var calm := _new_battle()
	var calm_battle: BattleManager = calm["battle"]
	calm_battle.deploy("tank", _find_cell(calm_battle, calm["castle_pos"], true))
	_run_ticks(calm_battle, 0.4)
	var lone: TroopActor = calm_battle.attacker_units[0]
	_check(calm_battle.defender_units.size() > 0, "the lone attacker released the garrison")
	lone.global_position = calm_battle.village.grid.cell_to_world(Vector2(4, 4))
	lone.clear_target()
	var frozen := {lone.get_instance_id(): true}
	for _i in range(int(30.0 / DT)):
		_tick(calm_battle, DT, frozen)
	var all_home := true
	var all_calm := true
	for defender in calm_battle._living_defenders():
		all_home = all_home and defender.global_position.distance_to(defender.home_position) <= BattleManager.HOME_ARRIVAL_DISTANCE + 2.0
		all_calm = all_calm and not is_instance_valid(defender.target) and defender.state == TroopActor.State.IDLE
	_check(calm_battle.phase == BattleManager.Phase.ACTIVE, "the battle is still running while an attacker lives")
	_check(all_home, "defenders walk back to the castle when no attacker is in reach")
	_check(all_calm, "defenders stand down (idle, no target) after returning")
	# And they re-engage when the attacker comes back into reach.
	lone.global_position = calm["castle_pos"] + Vector2(150, 40)
	var re_engaged := false
	for _i in range(int(3.0 / DT)):
		_tick(calm_battle, DT, frozen)
		for defender in calm_battle._living_defenders():
			if is_instance_valid(defender.target) and defender.target == lone:
				re_engaged = true
	_check(re_engaged, "defenders re-engage an attacker that returns to the castle")


func _test_troop_versus_troop_combat() -> void:
	# Direct: an attacker's blow on a defending troop lands, and a corpse is never attacked again.
	var setup := _new_battle()
	var battle: BattleManager = setup["battle"]
	battle.deploy("warrior", _find_cell(battle, setup["castle_pos"], false))
	var attacker: TroopActor = battle.attacker_units[0]
	var defender := TroopActor.new()
	defender.configure("archer")
	defender.team = TroopActor.Team.DEFENDER
	battle.units_root.add_child(defender)
	defender.global_position = attacker.global_position + Vector2(20, 0)
	var hits: Array[int] = []
	battle.damage_event.connect(func(_position: Vector2, amount: int, _heal: bool) -> void: hits.append(amount))
	battle._on_attack_requested(attacker, defender, 24)
	_check(defender.hp == defender.max_hp - 24 and hits == [24], "an attacker's blow damages a defending troop")
	defender.apply_damage(9999)
	var queued_before := battle._replan_queue.size()
	attacker.target = defender
	battle._on_attack_requested(attacker, defender, 24)
	_check(hits.size() == 1, "nobody keeps hitting a dead defender")
	_check(battle._replan_queue.size() == queued_before + 1, "the attacker re-plans after its victim dies")
	# End to end: a strong, mixed army beats the garrison.
	var strong := _new_battle()
	var strong_battle: BattleManager = strong["battle"]
	for i in range(8):
		strong_battle.deploy("warrior", _find_cell(strong_battle, strong["castle_pos"], true, i))
	for i in range(8):
		strong_battle.deploy("archer", _find_cell(strong_battle, strong["castle_pos"], false, i))
	_run_ticks(strong_battle, 40.0)
	_check(strong_battle.defenders_released > 0 and strong_battle.defenders_defeated >= 1, "a strong army defeats Clan Castle defenders (%d of %d)" % [strong_battle.defenders_defeated, strong_battle.defenders_released])


func _test_castle_destroyed_before_release() -> void:
	var setup := _new_battle()
	var battle: BattleManager = setup["battle"]
	battle._on_building_destroyed(setup["castle_id"])
	_check(bool(battle.castles[setup["castle_id"]]["lost"]), "a castle that falls before release loses its garrison")
	battle.deploy("warrior", _find_cell(battle, setup["castle_pos"], true))
	_run_ticks(battle, 2.0)
	_check(battle.defenders_released == 0, "a destroyed castle releases nobody")


func _test_castle_destroyed_after_release() -> void:
	var setup := _new_battle()
	var battle: BattleManager = setup["battle"]
	battle.deploy("tank", _find_cell(battle, setup["castle_pos"], true))
	_run_ticks(battle, 0.2)
	var released := battle.defender_units.size()
	battle._on_building_destroyed(setup["castle_id"])
	_run_ticks(battle, 0.5)
	_check(released > 0 and battle._living_defenders().size() > 0, "released defenders keep fighting after the castle falls")
	_check(battle.destroyed_count == 1, "the castle counts toward destruction")


func _test_controls_reach_defenders() -> void:
	var setup := _new_battle()
	var battle: BattleManager = setup["battle"]
	battle.deploy("tank", _find_cell(battle, setup["castle_pos"], true))
	_run_ticks(battle, 0.2)
	var defender: TroopActor = battle.defender_units[0]
	battle.set_speed(3.0)
	_check(is_equal_approx(defender.simulation_speed, 3.0), "battle speed applies to defenders")
	battle.set_paused(true)
	_check(not defender.is_processing(), "pausing the battle pauses defenders")
	battle.set_paused(false)
	_check(defender.is_processing(), "resuming the battle resumes defenders")


func _test_replan_queue_and_recovery() -> void:
	var setup := _new_battle()
	var battle: BattleManager = setup["battle"]
	for i in range(4):
		battle.deploy("warrior", _find_cell(battle, setup["castle_pos"], false, i))
	battle.set_path_algorithm(GridPathfinder.BFS)
	_check(battle._replan_queue.size() == battle._living_attackers().size(), "switching algorithm queues a re-plan for every attacker")
	var started := Time.get_ticks_usec()
	_tick(battle, DT)
	var first_frame_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_check(battle._replan_queue.size() == battle._living_attackers().size() - BattleManager.REPLANS_PER_FRAME, "only a few plans are served per frame")
	_check(first_frame_ms < 400.0, "a queued re-plan does not freeze the frame (%.0f ms)" % first_frame_ms)
	_run_ticks(battle, 1.0)
	_check(battle._replan_queue.is_empty(), "the re-plan queue drains")
	# A troop that ends up idle without a target is recovered automatically.
	var stuck: TroopActor = battle.attacker_units[0]
	stuck.clear_target()
	_check(stuck.state == TroopActor.State.IDLE and not is_instance_valid(stuck.target), "a stuck troop has no target")
	_run_ticks(battle, 4.0)
	_check(is_instance_valid(stuck.target), "a troop left idle without a target is re-planned")


func _test_defender_death_and_result() -> void:
	var setup := _new_battle()
	var battle: BattleManager = setup["battle"]
	var finished: Array[Dictionary] = []
	battle.battle_finished.connect(func(result: Dictionary) -> void: finished.append(result))
	for i in range(3):
		battle.deploy("warrior", _find_cell(battle, setup["castle_pos"], true, i))
	_run_ticks(battle, 4.0)
	var victim: TroopActor = null
	for defender in battle._living_defenders():
		victim = defender
		break
	_check(victim != null, "defenders are alive to be defeated")
	if victim != null:
		var before := battle.defenders_defeated
		victim.apply_damage(99999)
		_run_ticks(battle, 0.2)
		_check(battle.defenders_defeated == before + 1, "a defeated defender is counted once")
		var stale := false
		for attacker in battle._living_attackers():
			if is_instance_valid(attacker.target) and attacker.target == victim:
				stale = true
		_check(not stale, "no attacker keeps targeting a dead defender")
	battle._finish(BattleManager.Phase.DEFEAT)
	_check(finished.size() == 1 and finished[0].has("defenders_released") and finished[0].has("defenders_defeated"), "the battle result reports castle defenders")
	for defender in battle.defender_units:
		if is_instance_valid(defender):
			_check(not defender.is_processing(), "finished battles stop defender processing")
			break


# ----------------------------------------------------------------------------------------------
func _new_battle() -> Dictionary:
	var village := VillageModel.new()
	village.create_starter_layout()
	var castle := _castle_of(village)
	var actors := Node2D.new()
	var targets := Node2D.new()
	root.add_child(actors)
	root.add_child(targets)
	var battle := BattleManager.new()
	root.add_child(battle)
	_roots.append_array([actors, targets, battle])
	battle.begin_battle(village, actors, targets)
	var castle_target: BattleBuildingTarget = battle.building_targets[castle["id"]]
	return {"battle": battle, "castle_id": castle["id"], "castle_pos": castle_target.global_position}


func _castle_of(village: VillageModel) -> Dictionary:
	for structure in village.structures:
		if structure["type"] == "clan_castle":
			return structure
	return {}


## A legal deployment cell either inside (<= 230 px) or well outside (>= 700 px) the castle trigger radius.
func _find_cell(battle: BattleManager, castle_pos: Vector2, inside: bool, skip: int = 0) -> Vector2i:
	var found := 0
	for y in range(battle.village.grid.height):
		for x in range(battle.village.grid.width):
			var cell := Vector2i(x, y)
			if not battle.is_valid_deployment_cell(cell):
				continue
			var distance := battle.village.grid.cell_to_world(Vector2(cell)).distance_to(castle_pos)
			if (inside and distance <= 230.0) or (not inside and distance >= 700.0):
				if found == skip:
					return cell
				found += 1
	return Vector2i(-1, -1)


func _tick(battle: BattleManager, dt: float, frozen: Dictionary = {}) -> void:
	for troop in battle._all_troops():
		troop.set_process(false)
		if not frozen.has(troop.get_instance_id()):
			troop.step(dt)
	battle._process(dt)


func _run_ticks(battle: BattleManager, seconds: float) -> void:
	for _i in range(int(seconds / DT)):
		_tick(battle, DT)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
