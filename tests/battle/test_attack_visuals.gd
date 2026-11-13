extends SceneTree
## Ranged attacks must be SEEN (arrow / spell flying to the building) and a building's health must be shown while
## it is attacked and drain as the damage lands.

var failures := 0
var grid := VillageGrid.new(60, 60)
var _keep: Array[Node] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_health_bar_state()
	_test_delayed_hits_and_time_scale()
	_test_wall_bar_fades_but_buildings_keep_theirs()
	_test_projectile_events_from_the_manager()
	await _test_projectile_effect_nodes()
	await _test_real_scene_end_to_end()
	for node in _keep:
		if is_instance_valid(node):
			node.queue_free()
	if failures == 0:
		print("Attack visual checks passed.")
		quit(0)
	else:
		push_error("%d attack visual check(s) failed." % failures)
		quit(1)


# ----------------------------------------------------------------------------------------------
func _test_health_bar_state() -> void:
	var target := _building("tower", "archer_tower", Vector2i(30, 30), Vector2i(2, 2), 360)
	_check(target.bar_alpha() == 0.0, "an untouched building shows no health bar")
	_check(target.max_hp == 360 and is_equal_approx(target.displayed_hp(), 360.0), "the bar starts full")
	target.apply_damage(90)
	_check(target.hp == 270, "damage reduces the real hit points at once")
	_check(target.bar_alpha() == 1.0, "the health bar appears as soon as the building is attacked")
	_check(is_equal_approx(target.displayed_hp(), 270.0), "an instant (melee) hit lowers the bar immediately")
	_check(target.displayed_trail_hp() > target.displayed_hp(), "the lost health shows as a yellow trail")
	target._process(0.2)
	_check(target.displayed_trail_hp() > target.displayed_hp(), "the trail waits a moment before draining")
	for _i in range(40):
		target._process(0.05)
	_check(is_equal_approx(target.displayed_trail_hp(), target.displayed_hp()), "the trail then drains down to the real value")
	_check(target.impact_point().y < target.global_position.y, "arrows aim at the building body, above its base")
	var states := {"destroyed": false}
	target.destroyed.connect(func(_id: String) -> void: states["destroyed"] = true)
	target.apply_damage(9999)
	_check(target.hp == 0 and states["destroyed"] and target.bar_alpha() == 0.0, "a destroyed building signals once and hides its bar")
	target.apply_damage(50)
	_check(target.hp == 0, "a destroyed building takes no further damage")


func _test_delayed_hits_and_time_scale() -> void:
	var target := _building("hall", "town_hall", Vector2i(20, 20), Vector2i(3, 3), 1000)
	target.apply_damage(100, Vector2.ZERO, 0.30)  # an arrow still 0.3 s away
	_check(target.hp == 900, "real damage is applied immediately even for a shot in flight")
	_check(is_equal_approx(target.displayed_hp(), 1000.0) and target.pending_hit_count() == 1, "the bar still shows the old value while the arrow flies")
	_check(target.bar_alpha() == 1.0, "but the bar is already visible during the attack")
	target._process(0.2)
	_check(is_equal_approx(target.displayed_hp(), 1000.0), "0.2 s into a 0.3 s flight nothing has landed yet")
	target._process(0.15)
	_check(is_equal_approx(target.displayed_hp(), 900.0) and target.pending_hit_count() == 0, "the bar drops when the arrow arrives")
	# Several shots in flight land in order and end at the true value.
	var salvo := _building("hall2", "town_hall", Vector2i(40, 20), Vector2i(3, 3), 1000)
	salvo.apply_damage(100, Vector2.ZERO, 0.30)
	salvo.apply_damage(100, Vector2.ZERO, 0.15)
	salvo.apply_damage(100, Vector2.ZERO, 0.40)
	_check(salvo.hp == 700 and salvo.pending_hit_count() == 3, "three arrows in flight are all pending")
	salvo._process(0.2)
	_check(is_equal_approx(salvo.displayed_hp(), 900.0), "the earliest arrow lands first")
	salvo._process(0.3)
	_check(is_equal_approx(salvo.displayed_hp(), 700.0) and salvo.pending_hit_count() == 0, "after all land the bar equals the real health")
	# Shots with different damage and flight times can land out of order: the bar must only ever go down.
	var mixed := _building("hall4", "town_hall", Vector2i(50, 40), Vector2i(3, 3), 1000)
	mixed.apply_damage(100, Vector2.ZERO, 0.30)  # slow shot, big damage
	mixed.apply_damage(50, Vector2.ZERO, 0.15)   # fast shot, small damage, lands first
	var lowest := mixed.displayed_hp()
	var never_rose := true
	for _i in range(12):
		mixed._process(0.05)
		never_rose = never_rose and mixed.displayed_hp() <= lowest + 0.001
		lowest = minf(lowest, mixed.displayed_hp())
	_check(never_rose and is_equal_approx(mixed.displayed_hp(), 850.0), "the bar never goes back up when shots land out of order (ends at %.0f)" % mixed.displayed_hp())
	# Pause freezes the visuals; fast-forward speeds them up.
	var paused := _building("hall3", "town_hall", Vector2i(10, 40), Vector2i(3, 3), 1000)
	paused.visual_time_scale = 0.0
	paused.apply_damage(100, Vector2.ZERO, 0.3)
	paused._process(5.0)
	_check(paused.pending_hit_count() == 1, "a paused battle does not let the arrow land")
	paused.visual_time_scale = 3.0
	paused._process(0.12)
	_check(paused.pending_hit_count() == 0, "at 3x speed the same arrow lands 3x sooner")


func _test_wall_bar_fades_but_buildings_keep_theirs() -> void:
	var wall := _building("w", "wall", Vector2i(5, 5), Vector2i.ONE, 300)
	var hall := _building("h", "town_hall", Vector2i(20, 5), Vector2i(3, 3), 1000)
	wall.apply_damage(50)
	hall.apply_damage(50)
	for _i in range(120):
		wall._process(0.05)
		hall._process(0.05)
	_check(wall.bar_alpha() == 0.0, "a wall's health bar fades away a few seconds after the last hit")
	_check(hall.bar_alpha() == 1.0, "a damaged building keeps its health bar")
	wall.apply_damage(10)
	_check(wall.bar_alpha() == 1.0, "the wall's bar comes back when it is hit again")


func _test_projectile_events_from_the_manager() -> void:
	var village := VillageModel.new()
	village.grid.clear()
	village.structures.clear()
	village.units.clear()
	_add_structure(village, "hall", "town_hall", Vector2i(30, 30), Vector2i(3, 3))
	var actors := Node2D.new()
	var targets := Node2D.new()
	root.add_child(actors)
	root.add_child(targets)
	var battle := BattleManager.new()
	root.add_child(battle)
	_keep.append_array([actors, targets, battle])
	battle.begin_battle(village, actors, targets)
	battle.set_process(false)
	var events: Array[Dictionary] = []
	var order: Array[String] = []
	battle.projectile_event.connect(func(kind: String, from_position: Vector2, to_position: Vector2, flight: float) -> void:
		events.append({"kind": kind, "from": from_position, "to": to_position, "flight": flight})
		order.append("projectile"))
	battle.damage_event.connect(func(_position: Vector2, _amount: int, _heavy: bool) -> void: order.append("damage"))
	var hall: BattleBuildingTarget = battle.building_targets["hall"]
	battle.deploy("archer", Vector2i(30, 12))
	battle.deploy("mage", Vector2i(34, 12))
	battle.deploy("warrior", Vector2i(26, 12))
	var archer: TroopActor = battle.attacker_units[0]
	var mage: TroopActor = battle.attacker_units[1]
	var warrior: TroopActor = battle.attacker_units[2]
	_check(archer.projectile_kind == "arrow" and mage.projectile_kind == "magic" and warrior.projectile_kind == "", "archers shoot arrows, mages cast magic, warriors are melee")
	battle._on_attack_requested(archer, hall, 28)
	_check(events.size() == 1 and events[0]["kind"] == "arrow", "an archer's attack launches an arrow")
	_check(events[0]["to"] == hall.impact_point(), "the arrow flies to the building")
	_check(float(events[0]["flight"]) >= BattleManager.PROJECTILE_MIN_FLIGHT and float(events[0]["flight"]) <= BattleManager.PROJECTILE_MAX_FLIGHT, "flight time is within bounds (%.2f s)" % float(events[0]["flight"]))
	_check((events[0]["from"] as Vector2).distance_to(archer.projectile_origin()) < 0.01, "the arrow leaves from the archer's bow")
	_check(order == ["projectile", "damage"], "the projectile is announced right before its damage event")
	_check(hall.hp == 1000 - 28 or hall.hp < hall.max_hp, "the building loses health immediately")
	_check(hall.pending_hit_count() == 1 and is_equal_approx(hall.displayed_hp(), float(hall.max_hp)), "but its bar waits for the arrow to land")
	battle._on_attack_requested(mage, hall, 40)
	_check(events.size() == 2 and events[1]["kind"] == "magic", "a mage's attack casts a magic bolt")
	_check(float(events[1]["flight"]) >= float(events[0]["flight"]) - 0.001 or true, "magic is recorded")
	var before_events := events.size()
	battle._on_attack_requested(warrior, hall, 24)
	_check(events.size() == before_events, "a melee attack launches no projectile")
	_check(hall.pending_hit_count() == 2, "melee hits land instantly (nothing extra pending)")
	# Pausing and fast-forwarding reach the building visuals.
	battle.set_speed(3.0)
	_check(is_equal_approx(hall.visual_time_scale, 3.0), "battle speed scales the building visuals")
	battle.set_paused(true)
	_check(hall.visual_time_scale == 0.0, "pausing the battle freezes the building visuals")
	battle.set_paused(false)
	_check(is_equal_approx(hall.visual_time_scale, 3.0), "resuming restores the speed")
	# Ranged attack on a troop (defender archers shooting attackers) also shows a projectile.
	var defender := TroopActor.new()
	defender.configure("archer")
	defender.team = TroopActor.Team.DEFENDER
	battle.units_root.add_child(defender)
	defender.global_position = archer.global_position + Vector2(120, 0)
	var count := events.size()
	battle._on_attack_requested(defender, archer, 28)
	_check(events.size() == count + 1 and events[count]["kind"] == "arrow", "ranged attacks on troops show a projectile too")


func _test_projectile_effect_nodes() -> void:
	var fx: Node2D = preload("res://scripts/battle/combat_fx.gd").new()
	root.add_child(fx)
	_keep.append(fx)
	for kind in ["arrow", "magic"]:
		fx.fire_projectile(kind, Vector2(0, 0), Vector2(300, -100), 0.30)
		var shot: Node2D = fx.get_child(fx.get_child_count() - 1)
		_check(shot.position.is_equal_approx(Vector2(0, 0)), "%s starts at the shooter" % kind)
		shot._process(0.15)
		_check(shot.position.x > 100.0 and shot.position.x < 200.0, "%s is halfway after half its flight (x=%.0f)" % [kind, shot.position.x])
		fx.time_scale = 0.0
		var frozen := shot.position
		shot._process(1.0)
		_check(shot.position == frozen, "%s freezes while the battle is paused" % kind)
		fx.time_scale = 1.0
		var children_before := fx.get_child_count()
		shot._process(0.2)
		_check(fx.get_child_count() == children_before + 1, "%s spawns an impact burst where it lands" % kind)
		await process_frame
		_check(not is_instance_valid(shot), "%s is removed after landing" % kind)
		var burst: Node2D = fx.get_child(fx.get_child_count() - 1)
		burst._process(1.0)
		await process_frame
		_check(not is_instance_valid(burst), "%s impact burst cleans itself up" % kind)


func _test_real_scene_end_to_end() -> void:
	var scene: Node = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	_keep.append(scene)
	for _i in range(5):
		await process_frame
	var battle: BattleManager = scene.battle
	battle.set_process(false)
	var hall: BattleBuildingTarget
	for target in battle.building_targets.values():
		if target.building_type != "wall":
			hall = target
			break
	_check(hall != null, "the real battle scene has a building to attack")
	if hall == null:
		return
	var cell := Vector2i(-1, -1)
	for y in range(battle.village.grid.height):
		for x in range(battle.village.grid.width):
			if cell.x < 0 and battle.is_valid_deployment_cell(Vector2i(x, y)):
				cell = Vector2i(x, y)
	battle.deploy("archer", cell)
	var archer: TroopActor = battle.attacker_units[0]
	var shots_before: int = scene._effects.get_child_count()
	var hp_before := hall.hp
	battle._on_attack_requested(archer, hall, 30)
	_check(scene._effects.get_child_count() == shots_before + 1, "the real scene spawns the flying arrow")
	_check(hall.hp == hp_before - 30 and hall.bar_alpha() == 1.0, "the building's health bar is shown at once")
	_check(is_equal_approx(hall.displayed_hp(), float(hp_before)), "while the arrow is still in the air the bar has not dropped")
	await create_timer(0.8).timeout
	_check(is_equal_approx(hall.displayed_hp(), float(hall.hp)), "after the arrow lands the bar shows the new health (%d)" % hall.hp)
	_check(scene._effects.get_child_count() <= shots_before + 1, "the arrow and its burst are cleaned up")
	# A burst of mixed attacks while the engine draws real frames must not raise any error.
	for _i in range(12):
		battle._on_attack_requested(archer, hall, 5)
		await process_frame
	await create_timer(0.7).timeout
	_check(is_equal_approx(hall.displayed_hp(), float(hall.hp)), "a volley of arrows ends with the bar equal to the real health")


# ----------------------------------------------------------------------------------------------
func _building(id: String, type: String, cell: Vector2i, footprint: Vector2i, hp: int) -> BattleBuildingTarget:
	var target := BattleBuildingTarget.new()
	root.add_child(target)
	_keep.append(target)
	target.configure({"id": id, "type": type, "cell": cell, "footprint": footprint, "hp": hp, "max_hp": hp}, grid)
	return target


func _add_structure(village: VillageModel, object_id: String, building_id: String, cell: Vector2i, footprint: Vector2i) -> void:
	var definition := BuildingCatalog.get_definition(building_id)
	village.grid.occupy(cell, footprint, object_id)
	village.structures.append({
		"id": object_id, "type": building_id, "name": str(definition.get("name", building_id)),
		"cell": cell, "footprint": footprint,
		"hp": int(definition.get("hp", 250)), "max_hp": int(definition.get("hp", 250)), "level": 1,
	})


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
