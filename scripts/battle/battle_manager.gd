extends Node
class_name BattleManager
## Authoritative battle phase, simulation clock, deployment, and combat resolution.

const BATTLE_SEARCH := preload("res://scripts/ai/battle_search_ai.gd")

enum Phase { DEPLOYMENT, ACTIVE, PAUSED, VICTORY, DEFEAT, TIMEOUT }

signal battle_updated
signal battle_finished(result: Dictionary)
signal status_message(message: String)
## A ranged troop released an arrow or spell: kind ("arrow" / "magic"), start and end in world space, and how
## many battle seconds it is in flight. Always emitted just before the damage_event for the same attack.
signal projectile_event(kind: String, from_position: Vector2, to_position: Vector2, flight_time: float)
signal damage_event(world_position: Vector2, amount: int, heavy: bool)
signal destruction_event(world_position: Vector2)

const BATTLE_DURATION := 180.0
const DEPLOYMENT_CLEARANCE_TILES := 5
const ARMY_LIMIT := 29  # Minimum deploy cap; grows if the player trained a bigger army.
const TROOP_STOCK := {"warrior": 8, "mage": 3, "goblin": 8, "archer": 8, "tank": 2}
## Planning is the expensive part of a battle (a pathfinding search per candidate target), so planned
## re-evaluations are queued and served a few per frame instead of all in one frame.
const REPLANS_PER_FRAME := 1
const DEFENDER_DECISIONS_PER_FRAME := 2
const DEFENDER_THINK_INTERVAL := 0.6
const REPATH_INTERVAL := 0.45
const ATTACKER_RECONSIDER_INTERVAL := 1.5
const AWARENESS_TICK := 0.5
## Attackers only consider fighting defending troops this close (world pixels).
const TROOP_ENGAGE_RANGE := 520.0
## How far from the victim another attacker still joins a fight (used by the defender-side search).
const SUPPORT_RANGE := 150.0
const BREACH_CANDIDATES := 10
## How much a breach wall's distance to the buildings behind it counts, relative to the troop's own walk.
const BREACH_GAP_WEIGHT := 1.5
const HOME_ARRIVAL_DISTANCE := 6.0
const DEFENDER_HIT_PROBABILITY := 0.85
## Projectile speeds (world px per battle second) and the shortest / longest time a shot is allowed to fly.
const PROJECTILE_SPEEDS := {"arrow": 820.0, "magic": 560.0, "fire": 900.0}
const PROJECTILE_MIN_FLIGHT := 0.14
const PROJECTILE_MAX_FLIGHT := 0.42

var phase: Phase = Phase.DEPLOYMENT
var village: VillageModel
var units_root: Node2D
var targets_root: Node2D
var time_remaining := BATTLE_DURATION
var speed_multiplier := 1.0
var deployed_counts: Dictionary = {}
var troop_stock: Dictionary = TROOP_STOCK.duplicate(true)
var attacker_units: Array[TroopActor] = []
var building_targets: Dictionary = {}
var tower_cooldowns: Dictionary = {}
var tower_targets: Dictionary = {}
var initial_building_count := 0
var destroyed_count := 0
var total_deployed := 0
var town_hall_destroyed := false
var path_algorithm := GridPathfinder.ASTAR
var strategy_algorithm := BATTLE_SEARCH.MINIMAX
var last_ai_decision: Dictionary = {}
var visualization_enabled := false
var path_traces: Dictionary = {}
## Clan Castle state: {structure_id: {"released": bool, "lost": bool, "garrison": {troop_id: count}}}.
var castles: Dictionary = {}
var defender_units: Array[TroopActor] = []
var last_defender_decision: Dictionary = {}
var defenders_released := 0
var defenders_defeated := 0
var _replan_queue: Array[TroopActor] = []
var _defender_decision_queue: Array[TroopActor] = []
var _awareness_timer := 0.0
## Connected regions of walkable cells. Lets planning skip targets that are walled off without running a
## pathfinding search that would have to flood the whole map before giving up. Rebuilt when a building falls.
var _regions := PackedInt32Array()
var _regions_valid := false
## The one wall every troop attacks while the base is sealed, so a single gap opens quickly instead of
## troops chewing through different walls. Cleared when that wall falls.
var _breach_wall_id := ""
var army_limit := ARMY_LIMIT


func begin_battle(enemy_village: VillageModel, actor_root: Node2D, target_root: Node2D) -> void:
	village = enemy_village
	units_root = actor_root
	targets_root = target_root
	phase = Phase.DEPLOYMENT
	time_remaining = BATTLE_DURATION
	speed_multiplier = 1.0
	deployed_counts.clear()
	troop_stock = village.army.duplicate(true)
	var stock_total := 0
	for stocked in troop_stock.values():
		stock_total += int(stocked)
	army_limit = maxi(ARMY_LIMIT, stock_total)
	attacker_units.clear()
	building_targets.clear()
	tower_cooldowns.clear()
	tower_targets.clear()
	destroyed_count = 0
	total_deployed = 0
	town_hall_destroyed = false
	last_ai_decision.clear()
	last_defender_decision.clear()
	path_traces.clear()
	castles.clear()
	defender_units.clear()
	defenders_released = 0
	defenders_defeated = 0
	_replan_queue.clear()
	_defender_decision_queue.clear()
	_awareness_timer = 0.0
	_regions_valid = false
	_breach_wall_id = ""
	# Walls are obstacles, not objectives: they do not count toward destruction % or victory.
	initial_building_count = 0
	for counted in village.structures:
		if str(counted.get("type", "")) != "wall":
			initial_building_count += 1
	for structure in village.structures:
		var target := BattleBuildingTarget.new()
		target.name = str(structure["id"])
		target.configure(structure, village.grid)
		if units_root.has_method("set_building_aim"):
			target.aim_changed.connect(Callable(units_root, "set_building_aim"))
		target.damaged.connect(_on_building_damaged)
		target.destroyed.connect(_on_building_destroyed)
		targets_root.add_child(target)
		building_targets[structure["id"]] = target
		tower_cooldowns[structure["id"]] = 0.0
		if str(structure.get("type", "")) == ClanCastle.BUILDING_ID:
			castles[str(structure["id"])] = {
				"released": false, "lost": false,
				"garrison": ClanCastle.sanitize(structure.get("garrison", null)),
			}
	battle_updated.emit()


func deploy(troop_id: String, cell: Vector2i) -> bool:
	if phase != Phase.DEPLOYMENT and phase != Phase.ACTIVE:
		return false
	if not troop_stock.has(troop_id) or int(troop_stock[troop_id]) <= 0:
		status_message.emit("No %s troops remain." % troop_id.capitalize())
		return false
	if total_deployed >= army_limit:
		status_message.emit("Army capacity reached.")
		return false
	if not _is_valid_deployment_cell(cell):
		status_message.emit("Deploy in the glowing outer ring, beyond the village walls.")
		return false
	var actor := TroopActor.new()
	actor.name = "Attacker_%s_%d" % [troop_id, attacker_units.size() + 1]
	if not actor.configure(troop_id, village.troop_level(troop_id)):
		actor.free()
		return false
	actor.global_position = village.grid.cell_to_world(Vector2(cell))
	actor.set_simulation_speed(speed_multiplier)
	actor.attack_requested.connect(_on_attack_requested)
	actor.died.connect(_on_attacker_died)
	units_root.add_child(actor)
	attacker_units.append(actor)
	troop_stock[troop_id] = int(troop_stock[troop_id]) - 1
	village.army[troop_id] = int(troop_stock[troop_id])
	deployed_counts[troop_id] = int(deployed_counts.get(troop_id, 0)) + 1
	total_deployed += 1
	_assign_minimax_attack_plan(actor)
	if phase == Phase.DEPLOYMENT:
		phase = Phase.ACTIVE
	status_message.emit("%s deployed." % troop_id.capitalize())
	battle_updated.emit()
	return true


func set_paused(is_paused: bool) -> void:
	if is_paused and phase == Phase.ACTIVE:
		phase = Phase.PAUSED
	elif not is_paused and phase == Phase.PAUSED:
		phase = Phase.ACTIVE
	for actor in _all_troops():
		actor.set_process(not is_paused)
		actor.set_animation_paused(is_paused)
	_sync_visual_time_scale()
	battle_updated.emit()


func set_speed(multiplier: float) -> void:
	speed_multiplier = clampf(multiplier, 1.0, 5.0)
	for actor in _all_troops():
		actor.set_simulation_speed(speed_multiplier)
	_sync_visual_time_scale()
	battle_updated.emit()


func set_path_algorithm(algorithm: String) -> void:
	if GridPathfinder.ALGORITHMS.has(algorithm):
		path_algorithm = algorithm
		_queue_replan_all()
		battle_updated.emit()


func set_strategy_algorithm(algorithm: String) -> void:
	if BATTLE_SEARCH.ALGORITHMS.has(algorithm):
		strategy_algorithm = algorithm
		_queue_replan_all()
		battle_updated.emit()



func set_visualization_enabled(enabled: bool) -> void:
	if visualization_enabled == enabled:
		return
	visualization_enabled = enabled
	path_traces.clear()
	if not enabled:
		return
	# Re-run search for display only. Never reassign targets or change troop state.
	for actor in attacker_units:
		if not is_instance_valid(actor) or not is_instance_valid(actor.target):
			continue
		if actor.target is BattleBuildingTarget:
			var trace := {"record": true}
			_find_attack_path(actor, actor.target, trace)
			_store_visual_trace(actor, actor.target, trace)


func _store_visual_trace(actor: TroopActor, target: BattleBuildingTarget, trace: Dictionary) -> void:
	if not visualization_enabled:
		return
	path_traces[actor.get_instance_id()] = {
		"visited": trace.get("visited", []),
		"path": trace.get("path", []),
		"algorithm": path_algorithm,
		"target": target.building_id,
		"nodes": int(trace.get("nodes_expanded", 0)),
	}

func get_destruction_percent() -> int:
	if initial_building_count <= 0:
		return 0
	return roundi(float(destroyed_count) * 100.0 / float(initial_building_count))


func get_stars() -> int:
	var stars := 0
	if town_hall_destroyed:
		stars = 1
	if get_destruction_percent() >= 50:
		stars = maxi(stars, 2)
	if get_destruction_percent() >= 100:
		stars = 3
	return stars


func is_valid_deployment_cell(cell: Vector2i) -> bool:
	return _is_valid_deployment_cell(cell)


func _process(delta: float) -> void:
	if phase != Phase.ACTIVE:
		return
	var sim_delta := delta * speed_multiplier
	time_remaining = maxf(0.0, time_remaining - sim_delta)
	_update_defenses(sim_delta)
	_update_castles()
	_prune_defenders()
	_update_defender_troops(sim_delta)
	_update_attacker_chase(sim_delta)
	_update_attacker_awareness(sim_delta)
	_process_replan_queue()
	if initial_building_count > 0 and destroyed_count >= initial_building_count:
		_finish(Phase.VICTORY)
	elif time_remaining <= 0.0:
		_finish(Phase.TIMEOUT)
	battle_updated.emit()


func _is_valid_deployment_cell(cell: Vector2i) -> bool:
	if not village.grid.contains_cell(cell) or village.grid.occupied.has(cell):
		return false
	for structure in village.structures:
		var origin: Vector2i = structure["cell"]
		var footprint: Vector2i = structure["footprint"]
		var dx := maxi(maxi(origin.x - cell.x, 0), cell.x - (origin.x + footprint.x - 1))
		var dy := maxi(maxi(origin.y - cell.y, 0), cell.y - (origin.y + footprint.y - 1))
		if Vector2(float(dx), float(dy)).length() < float(DEPLOYMENT_CLEARANCE_TILES):
			return false
	return true


func _assign_minimax_attack_plan(actor: TroopActor) -> void:
	if not is_instance_valid(actor) or actor.team != TroopActor.Team.ATTACKER or actor.state == TroopActor.State.DEAD:
		return
	actor.think_cooldown = ATTACKER_RECONSIDER_INTERVAL
	var candidates: Array[BattleBuildingTarget] = []
	var candidate_paths: Dictionary = {}
	var path_costs: Dictionary = {}
	var stand_positions: Dictionary = {}
	for candidate in building_targets.values():
		# Walls are obstacles, not objectives: they are only attacked to breach a sealed base (below).
		if not is_instance_valid(candidate) or candidate.building_type == "wall":
			continue
		var path := _find_attack_path(actor, candidate)
		if path.is_empty():
			continue
		candidates.append(candidate)
		candidate_paths[candidate.building_id] = path
		path_costs[candidate.building_id] = maxi(0, path.size() - 1)
		stand_positions[candidate.building_id] = village.grid.cell_to_world(Vector2(path[path.size() - 1]))
	# Defending troops released from a Clan Castle are targets too.
	var troop_candidates: Array[TroopActor] = []
	var troop_lookup: Dictionary = {}
	for defender in _nearest_defenders(actor, BATTLE_SEARCH.MAX_TROOP_CANDIDATES):
		var troop_key := BATTLE_SEARCH.defender_target_id(defender)
		var troop_path: Array[Vector2i] = []
		var already_in_range := actor.global_position.distance_to(defender.global_position) <= actor.attack_range
		if not already_in_range:
			troop_path = _find_troop_path(actor, defender)
			if troop_path.is_empty():
				continue
		troop_candidates.append(defender)
		troop_lookup[troop_key] = defender
		candidate_paths[troop_key] = troop_path
		path_costs[troop_key] = maxi(0, troop_path.size() - 1)
		stand_positions[troop_key] = actor.global_position if troop_path.is_empty() else village.grid.cell_to_world(Vector2(troop_path[troop_path.size() - 1]))
	if candidates.is_empty() and troop_candidates.is_empty():
		var breach_target := _find_breaching_wall(actor)
		if is_instance_valid(breach_target):
			var breach_path := _find_attack_path(actor, breach_target)
			if not breach_path.is_empty():
				candidates.append(breach_target)
				candidate_paths[breach_target.building_id] = breach_path
				path_costs[breach_target.building_id] = maxi(0, breach_path.size() - 1)
				stand_positions[breach_target.building_id] = village.grid.cell_to_world(Vector2(breach_path[breach_path.size() - 1]))
	if candidates.is_empty() and troop_candidates.is_empty():
		actor.clear_target()
		path_traces.erase(actor.get_instance_id())
		return
	var defenses := _build_defense_inputs(actor)
	last_ai_decision = BATTLE_SEARCH.select_target(actor, candidates, village.structures, defenses, strategy_algorithm, path_costs, troop_candidates, stand_positions)
	var target_id := str(last_ai_decision.get("target_id", ""))
	var best_target: Node2D
	if target_id.begins_with(BATTLE_SEARCH.DEFENDER_ID_PREFIX):
		best_target = troop_lookup.get(target_id)
	else:
		best_target = building_targets.get(target_id)
	if not is_instance_valid(best_target):
		actor.clear_target()
		return
	actor.assign_target(best_target)
	var chosen_path: Array[Vector2i] = []
	if candidate_paths.has(target_id):
		chosen_path = candidate_paths[target_id]
	actor.set_walk_path(chosen_path, village.grid)
	actor.repath_cooldown = REPATH_INTERVAL
	last_ai_decision["path_cost"] = maxi(0, chosen_path.size() - 1)
	last_ai_decision["target_name"] = _describe_target(best_target)
	if visualization_enabled and best_target is BattleBuildingTarget:
		var trace := {"record": true}
		_find_attack_path(actor, best_target, trace)
		_store_visual_trace(actor, best_target, trace)
	else:
		path_traces.erase(actor.get_instance_id())


## What the opposition can do in reply, described as data for the tactical search. Each tower/cannon is its own
## hit-or-miss volley; every Clan Castle troop (inside the castle or already outside) is folded into one
## "garrison" volley so the search tree stays small.
func _build_defense_inputs(actor: TroopActor) -> Array[Dictionary]:
	var defenses: Array[Dictionary] = []
	for structure in village.structures:
		var type := str(structure.get("type", ""))
		if type != "cannon" and type != "archer_tower":
			continue
		var defense_target: BattleBuildingTarget = building_targets.get(str(structure.get("id", "")))
		if not is_instance_valid(defense_target):
			continue
		var is_cannon := type == "cannon"
		var interval := 1.5 if is_cannon else 1.0
		defenses.append({
			"id": defense_target.building_id,
			"damage": 42 if is_cannon else 28,
			"range": 330.0 if is_cannon else 270.0,
			"hit_probability": DEFENDER_HIT_PROBABILITY,
			"position": defense_target.global_position,
			"rate": clampf(actor.attack_interval / interval, 0.25, 3.0),
		})
	var garrison_members: Array[Dictionary] = []
	for castle_id in castles:
		var info: Dictionary = castles[castle_id]
		if bool(info["released"]) or bool(info["lost"]):
			continue
		var castle_target: BattleBuildingTarget = building_targets.get(castle_id)
		if not is_instance_valid(castle_target):
			continue
		# Still inside: it answers only if the attacker comes within the trigger radius.
		for troop_id in ClanCastle.expand(info["garrison"]):
			var definition := TroopCatalog.get_definition(troop_id)
			garrison_members.append({
				"target_id": "",
				"damage": float(definition["damage"]) * clampf(actor.attack_interval / float(definition["attack_speed"]), 0.25, 3.0),
				"position": castle_target.global_position,
				"range": ClanCastle.TRIGGER_RADIUS,
			})
	for defender in _living_defenders():
		garrison_members.append({
			"target_id": BATTLE_SEARCH.defender_target_id(defender),
			"damage": float(defender.damage) * clampf(actor.attack_interval / maxf(defender.attack_interval, 0.1), 0.25, 3.0),
			"position": defender.leash_center,
			"range": defender.leash_radius,
		})
	if not garrison_members.is_empty():
		defenses.append({"id": "clan_castle_garrison", "hit_probability": DEFENDER_HIT_PROBABILITY, "members": garrison_members})
	return defenses


func _describe_target(target: Node2D) -> String:
	if target is BattleBuildingTarget:
		return str(BuildingCatalog.get_definition(target.building_type).get("name", target.building_id))
	if target is TroopActor:
		return "%s (%s)" % [target.display_name, "defender" if target.team == TroopActor.Team.DEFENDER else "attacker"]
	return str(target.name)


func _nearest_defenders(actor: TroopActor, limit: int) -> Array[TroopActor]:
	var nearby: Array[TroopActor] = []
	for defender in _living_defenders():
		if actor.global_position.distance_to(defender.global_position) <= TROOP_ENGAGE_RANGE:
			nearby.append(defender)
	nearby.sort_custom(func(a: TroopActor, b: TroopActor) -> bool:
		return actor.global_position.distance_squared_to(a.global_position) < actor.global_position.distance_squared_to(b.global_position)
	)
	if nearby.size() > limit:
		nearby.resize(limit)
	return nearby


func _find_attack_path(actor: TroopActor, target: BattleBuildingTarget, trace: Dictionary = {}) -> Array[Vector2i]:
	var structure := _get_structure(target.building_id)
	var no_path: Array[Vector2i] = []
	if structure.is_empty():
		return no_path
	if actor.is_flying:
		return _fly_path(actor, target)
	var start := village.grid.world_to_cell(actor.global_position)
	var radius := ceili(actor.attack_range / VillageGrid.TILE_SIZE.y) + 2
	var origin: Vector2i = structure["cell"]
	var footprint: Vector2i = structure["footprint"]
	var goals: Array[Vector2i] = []
	for y in range(maxi(0, origin.y - radius), mini(village.grid.height, origin.y + footprint.y + radius)):
		for x in range(maxi(0, origin.x - radius), mini(village.grid.width, origin.x + footprint.x + radius)):
			var cell := Vector2i(x, y)
			if village.grid.occupied.has(cell):
				continue
			if village.grid.cell_to_world(Vector2(cell)).distance_to(target.global_position) <= actor.attack_range:
				goals.append(cell)
	if not _can_reach(start, goals):
		return no_path
	return GridPathfinder.find_path_to_any(village.grid, start, goals, path_algorithm, trace)


## Flyers go in a straight line over walls and buildings, stopping once the target is in range.
func _fly_path(actor: TroopActor, target: Node2D) -> Array[Vector2i]:
	var start := village.grid.world_to_cell(actor.global_position)
	var path: Array[Vector2i] = [start]
	var gap := target.global_position - actor.global_position
	if gap.length() > actor.attack_range * 0.7:
		var stand := target.global_position - gap.normalized() * actor.attack_range * 0.6
		var stand_cell := village.grid.world_to_cell(stand)
		if stand_cell != start:
			path.append(stand_cell)
	return path


func _find_troop_path(actor: TroopActor, target: TroopActor, trace: Dictionary = {}) -> Array[Vector2i]:
	if actor.is_flying:
		return _fly_path(actor, target)
	var no_path: Array[Vector2i] = []
	if not is_instance_valid(target):
		return no_path
	var start := village.grid.world_to_cell(actor.global_position)
	var target_cell := village.grid.world_to_cell(target.global_position)
	var radius := ceili(actor.attack_range / VillageGrid.TILE_SIZE.y) + 2
	var goals: Array[Vector2i] = []
	for y in range(maxi(0, target_cell.y - radius), mini(village.grid.height, target_cell.y + radius + 1)):
		for x in range(maxi(0, target_cell.x - radius), mini(village.grid.width, target_cell.x + radius + 1)):
			var cell := Vector2i(x, y)
			if village.grid.occupied.has(cell):
				continue
			if village.grid.cell_to_world(Vector2(cell)).distance_to(target.global_position) <= actor.attack_range:
				goals.append(cell)
	if not _can_reach(start, goals):
		return no_path
	return GridPathfinder.find_path_to_any(village.grid, start, goals, path_algorithm, trace)


func _can_reach(start: Vector2i, goals: Array[Vector2i]) -> bool:
	_ensure_regions()
	var grid := village.grid
	if not grid.contains_cell(start):
		return false
	var start_region := _regions[start.y * grid.width + start.x]
	if start_region < 0:
		return true  # The troop stands inside an obstacle: let the real search decide.
	for goal in goals:
		if grid.contains_cell(goal) and _regions[goal.y * grid.width + goal.x] == start_region:
			return true
	return false


func _ensure_regions() -> void:
	if _regions_valid:
		return
	var grid := village.grid
	var width := grid.width
	var height := grid.height
	var cell_count := width * height
	var blocked := PackedByteArray()
	blocked.resize(cell_count)
	for occupied_cell in grid.occupied.keys():
		if occupied_cell.x >= 0 and occupied_cell.y >= 0 and occupied_cell.x < width and occupied_cell.y < height:
			blocked[occupied_cell.y * width + occupied_cell.x] = 1
	_regions = PackedInt32Array()
	_regions.resize(cell_count)
	_regions.fill(-1)
	var label := 0
	var stack := PackedInt32Array()
	for first in range(cell_count):
		if blocked[first] == 1 or _regions[first] != -1:
			continue
		_regions[first] = label
		stack.append(first)
		while not stack.is_empty():
			var current := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var cx := current % width
			@warning_ignore("integer_division")
			var cy := current / width
			if cx > 0 and blocked[current - 1] == 0 and _regions[current - 1] == -1:
				_regions[current - 1] = label
				stack.append(current - 1)
			if cx < width - 1 and blocked[current + 1] == 0 and _regions[current + 1] == -1:
				_regions[current + 1] = label
				stack.append(current + 1)
			if cy > 0 and blocked[current - width] == 0 and _regions[current - width] == -1:
				_regions[current - width] = label
				stack.append(current - width)
			if cy < height - 1 and blocked[current + width] == 0 and _regions[current + width] == -1:
				_regions[current + width] = label
				stack.append(current + width)
		label += 1
	_regions_valid = true


## Picks the wall to break through when the base is sealed. All troops share ONE breach wall (reused while it
## stands and is reachable) so a gap opens quickly; it is chosen close to the troop AND close to the buildings
## it opens the way to, rather than simply being the nearest wall.
func _find_breaching_wall(actor: TroopActor) -> BattleBuildingTarget:
	var start := village.grid.world_to_cell(actor.global_position)
	var shared: BattleBuildingTarget = building_targets.get(_breach_wall_id)
	if is_instance_valid(shared):
		var shared_structure := _get_structure(_breach_wall_id)
		if not shared_structure.is_empty() and _can_reach(start, _wall_access_cells(shared_structure)):
			return shared
	var objectives: Array[Dictionary] = []
	for structure in village.structures:
		if str(structure.get("type", "")) != "wall" and is_instance_valid(building_targets.get(str(structure.get("id", "")))):
			objectives.append(structure)
	# Cheap ranking first, so only the most promising walls get a real pathfinding search.
	var ranked: Array[Dictionary] = []
	for structure in village.structures:
		if str(structure.get("type", "")) != "wall" or not is_instance_valid(building_targets.get(str(structure.get("id", "")))):
			continue
		var wall_cell: Vector2i = structure["cell"]
		var gap := _distance_to_nearest_objective(wall_cell, objectives)
		ranked.append({
			"structure": structure, "gap": gap,
			"score": float(absi(wall_cell.x - start.x) + absi(wall_cell.y - start.y)) + BREACH_GAP_WEIGHT * gap,
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) < float(b["score"]))
	var best_target: BattleBuildingTarget
	var best_score := INF
	var searched := 0
	for entry in ranked:
		if searched >= BREACH_CANDIDATES:
			break
		var structure: Dictionary = entry["structure"]
		var access := _wall_access_cells(structure)
		if access.is_empty() or not _can_reach(start, access):
			continue
		searched += 1
		var path := GridPathfinder.find_path_to_any(village.grid, start, access, path_algorithm)
		if path.is_empty():
			continue
		var score := float(path.size()) + BREACH_GAP_WEIGHT * float(entry["gap"])
		if score < best_score:
			best_score = score
			best_target = building_targets.get(str(structure.get("id", "")))
	if is_instance_valid(best_target):
		_breach_wall_id = best_target.building_id
	return best_target


## Free cells touching a wall segment: where a troop can stand to hit it.
func _wall_access_cells(structure: Dictionary) -> Array[Vector2i]:
	var origin: Vector2i = structure["cell"]
	var footprint: Vector2i = structure["footprint"]
	var access: Array[Vector2i] = []
	for y in range(origin.y - 1, origin.y + footprint.y + 1):
		for x in range(origin.x - 1, origin.x + footprint.x + 1):
			var cell := Vector2i(x, y)
			var on_perimeter := x == origin.x - 1 or x == origin.x + footprint.x or y == origin.y - 1 or y == origin.y + footprint.y
			if on_perimeter and village.grid.contains_cell(cell) and not village.grid.occupied.has(cell):
				access.append(cell)
	return access


## Grid distance from a cell to the closest standing non-wall building (0 when there is none).
func _distance_to_nearest_objective(cell: Vector2i, objectives: Array[Dictionary]) -> float:
	var nearest := -1
	for structure in objectives:
		var origin: Vector2i = structure["cell"]
		var footprint: Vector2i = structure["footprint"]
		var dx := maxi(maxi(origin.x - cell.x, 0), cell.x - (origin.x + footprint.x - 1))
		var dy := maxi(maxi(origin.y - cell.y, 0), cell.y - (origin.y + footprint.y - 1))
		if nearest < 0 or dx + dy < nearest:
			nearest = dx + dy
	return float(maxi(nearest, 0))


func _get_structure(building_id: String) -> Dictionary:
	for structure in village.structures:
		if str(structure["id"]) == building_id:
			return structure
	return {}


func _on_attack_requested(attacker: TroopActor, target: Node2D, damage: int) -> void:
	if phase != Phase.ACTIVE or not is_instance_valid(target):
		return
	if target is TroopActor and (target.state == TroopActor.State.DEAD or target.hp <= 0):
		_retarget_after_kill(attacker)  # The victim died a moment ago; do not keep swinging at the corpse.
		return
	var flight_time := 0.0
	var fire_stream := attacker.projectile_kind == "fire"
	if attacker.projectile_kind != "":
		# Ranged attack: show the arrow / spell flying to its target. The damage is dealt now, but a building's
		# health bar and hit flash wait for the shot to land (flight_time).
		var from_point := attacker.projectile_origin()
		var to_point := _projectile_end_point(target)
		flight_time = _projectile_flight_time(attacker.projectile_kind, from_point.distance_to(to_point))
		projectile_event.emit(attacker.projectile_kind, from_point, to_point, flight_time)
	# A fire stream ticks several times a second; show one summed damage number every few ticks.
	var show_number := true
	if fire_stream:
		attacker.fire_pool += damage
		attacker.fire_ticks += 1
		show_number = attacker.fire_ticks >= 4
	if target is BattleBuildingTarget:
		target.apply_damage(damage, attacker.global_position, flight_time)
		if show_number:
			damage_event.emit(target.global_position, attacker.fire_pool if fire_stream else damage, false)
	elif target is TroopActor:
		target.apply_damage(damage, attacker.global_position)
		if show_number:
			damage_event.emit(target.global_position, attacker.fire_pool if fire_stream else damage, false)
	if fire_stream and show_number:
		attacker.fire_pool = 0
		attacker.fire_ticks = 0
	if is_instance_valid(attacker) and attacker.state != TroopActor.State.DEAD:
		var current_target: Variant = attacker.target
		var target_gone := not is_instance_valid(current_target)
		if not target_gone and current_target is TroopActor and current_target.state == TroopActor.State.DEAD:
			target_gone = true
		if target_gone:
			_retarget_after_kill(attacker)


func _projectile_end_point(target: Node2D) -> Vector2:
	if target is BattleBuildingTarget:
		return target.impact_point()
	return target.global_position + Vector2(0, -34)


func _projectile_flight_time(kind: String, distance: float) -> float:
	var speed := float(PROJECTILE_SPEEDS.get(kind, 700.0))
	return clampf(distance / speed, PROJECTILE_MIN_FLIGHT, PROJECTILE_MAX_FLIGHT)


## Visual timers (hit flashes, health bars, in-flight shots) follow the battle: frozen when paused, faster at 2-5x.
func _sync_visual_time_scale() -> void:
	var scale_value := 0.0 if phase == Phase.PAUSED else speed_multiplier
	for target in building_targets.values():
		if is_instance_valid(target):
			target.visual_time_scale = scale_value


func visual_time_scale() -> float:
	return 0.0 if phase == Phase.PAUSED else speed_multiplier


func _retarget_after_kill(actor: TroopActor) -> void:
	if not is_instance_valid(actor) or actor.state == TroopActor.State.DEAD:
		return
	if actor.team == TroopActor.Team.DEFENDER:
		actor.clear_target()
		actor.think_cooldown = 0.0
	else:
		_queue_replan(actor, true)


func _on_building_damaged(building_id: String, remaining_hp: int) -> void:
	for structure in village.structures:
		if structure["id"] == building_id:
			structure["hp"] = remaining_hp
			break


func _on_building_destroyed(building_id: String) -> void:
	for structure in village.structures:
		if structure["id"] == building_id:
			if structure["type"] == "town_hall":
				town_hall_destroyed = true
			var was_wall: bool = str(structure["type"]) == "wall"
			village.damage_structure(building_id, int(structure["hp"]))
			if not was_wall:
				destroyed_count += 1
			break
	_regions_valid = false  # A building (or wall) fell, so what is walkable has changed.
	if building_id == _breach_wall_id:
		_breach_wall_id = ""
	var removed_target: Variant = building_targets.get(building_id)
	building_targets.erase(building_id)
	if is_instance_valid(removed_target):
		destruction_event.emit(removed_target.global_position)
		removed_target.queue_free()
	status_message.emit("%s destroyed!" % building_id.capitalize().replace("_", " "))
	if castles.has(building_id):
		var info: Dictionary = castles[building_id]
		if not bool(info["released"]):
			info["lost"] = true  # The castle fell before it was ever triggered: its garrison is lost with it.
			status_message.emit("The Clan Castle collapsed with its garrison inside!")
	# Troops that lost their target need a new plan. Troops that are bashing a wall need one too: something just
	# fell, so a gap may have opened and a real building may now be reachable. They must not keep chewing on
	# their wall until it dies, so they go to the front of the queue.
	for attacker in attacker_units:
		if not is_instance_valid(attacker) or attacker.state == TroopActor.State.DEAD:
			continue
		var current_target: Variant = attacker.target
		if not is_instance_valid(current_target) or current_target == removed_target:
			_queue_replan(attacker)
		elif current_target is BattleBuildingTarget and current_target.building_type == "wall":
			_queue_replan(attacker, true)
	battle_updated.emit()


func _on_attacker_died(attacker: TroopActor) -> void:
	path_traces.erase(attacker.get_instance_id())
	for defender in defender_units:
		if is_instance_valid(defender) and defender.state != TroopActor.State.DEAD and is_instance_valid(defender.target) and defender.target == attacker:
			defender.clear_target()
			defender.think_cooldown = 0.0
	var another_attacker_alive := false
	for active_attacker in attacker_units:
		if is_instance_valid(active_attacker) and active_attacker != attacker and active_attacker.state != TroopActor.State.DEAD:
			another_attacker_alive = true
			break
	if phase == Phase.ACTIVE and not another_attacker_alive and total_deployed > 0:
		_finish(Phase.DEFEAT)


func _on_defender_died(defender: TroopActor) -> void:
	defenders_defeated += 1
	status_message.emit("%s defender defeated!" % defender.display_name)
	for attacker in attacker_units:
		if not is_instance_valid(attacker) or attacker.state == TroopActor.State.DEAD:
			continue
		if is_instance_valid(attacker.target) and attacker.target == defender:
			_queue_replan(attacker, true)
	battle_updated.emit()


func _update_defenses(delta: float) -> void:
	for structure in village.structures:
		var type: String = structure["type"]
		if type != "cannon" and type != "archer_tower":
			continue
		var building_id: String = structure["id"]
		var cooldown := maxf(0.0, float(tower_cooldowns.get(building_id, 0.0)) - delta)
		var target: TroopActor = tower_targets.get(building_id)
		var reach := 330.0 if type == "cannon" else 270.0
		var defense_target: Variant = building_targets.get(building_id)
		if not is_instance_valid(defense_target):
			continue
		var ground_only := type == "cannon"
		if not is_instance_valid(target) or target.state == TroopActor.State.DEAD or target.global_position.distance_to(defense_target.global_position) > reach or (ground_only and target.is_flying):
			target = _select_defender_response(defense_target.global_position, reach, ground_only)
			tower_targets[building_id] = target
		if is_instance_valid(target):
			defense_target.aim_at(target.global_position)
			if cooldown <= 0.0:
				defense_target.fire_at(target.global_position)
				var attack_damage := 42 if type == "cannon" else 28
				target.apply_damage(attack_damage, defense_target.global_position)
				damage_event.emit(target.global_position, attack_damage, type == "cannon")
				cooldown = 1.5 if type == "cannon" else 1.0
		tower_cooldowns[building_id] = cooldown


func _select_defender_response(from_position: Vector2, max_range: float, ground_only: bool = false) -> TroopActor:
	# Defenses focus the reachable attacker with the greatest current threat and vulnerability.
	var best_response: TroopActor
	var best_score := -INF
	for attacker in attacker_units:
		if not is_instance_valid(attacker) or attacker.state == TroopActor.State.DEAD:
			continue
		if ground_only and attacker.is_flying:
			continue
		var distance := from_position.distance_to(attacker.global_position)
		if distance > max_range:
			continue
		var attack_rate := float(attacker.damage) / maxf(attacker.attack_interval, 0.1)
		var urgency := (1.0 - float(attacker.hp) / maxf(float(attacker.max_hp), 1.0)) * 18.0
		var proximity := (1.0 - distance / maxf(max_range, 1.0)) * 12.0
		var response_score := attack_rate + urgency + proximity
		if response_score > best_score:
			best_score = response_score
			best_response = attacker
	return best_response


# ---------------------------------------------------------------------------------------------
# Troop bookkeeping
# ---------------------------------------------------------------------------------------------

func _all_troops() -> Array[TroopActor]:
	var troops: Array[TroopActor] = []
	for actor in attacker_units:
		if is_instance_valid(actor):
			troops.append(actor)
	for actor in defender_units:
		if is_instance_valid(actor):
			troops.append(actor)
	return troops


func _living_attackers() -> Array[TroopActor]:
	var living: Array[TroopActor] = []
	for attacker in attacker_units:
		if is_instance_valid(attacker) and attacker.state != TroopActor.State.DEAD and attacker.hp > 0:
			living.append(attacker)
	return living


func _living_defenders() -> Array[TroopActor]:
	var living: Array[TroopActor] = []
	for defender in defender_units:
		if is_instance_valid(defender) and defender.state != TroopActor.State.DEAD and defender.hp > 0:
			living.append(defender)
	return living


func _prune_defenders() -> void:
	if defender_units.is_empty():
		return
	var kept: Array[TroopActor] = []
	for index in range(defender_units.size()):
		var entry: Variant = defender_units[index]
		if is_instance_valid(entry):
			kept.append(entry)
	if kept.size() != defender_units.size():
		defender_units = kept


# ---------------------------------------------------------------------------------------------
# Planning queue
# ---------------------------------------------------------------------------------------------

## `candidate` is deliberately untyped: dead troops are freed after their fade-out, and passing a freed
## object into a typed parameter is a runtime error. Everything that may hold a stale troop goes through here.
func _queue_replan(candidate: Variant, front: bool = false) -> void:
	if not is_instance_valid(candidate):
		return
	var actor := candidate as TroopActor
	if actor == null or actor.team != TroopActor.Team.ATTACKER or actor.state == TroopActor.State.DEAD:
		return
	if _replan_queue.has(actor):
		if not front:
			return
		_replan_queue.erase(actor)
	if front:
		_replan_queue.push_front(actor)
	else:
		_replan_queue.append(actor)


func _queue_replan_all() -> void:
	for index in range(attacker_units.size()):
		_queue_replan(attacker_units[index])


func _process_replan_queue() -> void:
	var processed := 0
	while processed < REPLANS_PER_FRAME and not _replan_queue.is_empty():
		var popped: Variant = _replan_queue.pop_front()
		if not is_instance_valid(popped):
			continue
		var actor := popped as TroopActor
		if actor.state == TroopActor.State.DEAD or actor.team != TroopActor.Team.ATTACKER:
			continue
		_assign_minimax_attack_plan(actor)
		processed += 1


# ---------------------------------------------------------------------------------------------
# Clan Castle: trigger, release and defender behaviour
# ---------------------------------------------------------------------------------------------

func _update_castles() -> void:
	for castle_id in castles:
		var info: Dictionary = castles[castle_id]
		if bool(info["released"]) or bool(info["lost"]):
			continue
		var castle_target: BattleBuildingTarget = building_targets.get(castle_id)
		if not is_instance_valid(castle_target):
			continue
		for attacker in attacker_units:
			if not is_instance_valid(attacker) or attacker.state == TroopActor.State.DEAD:
				continue
			if attacker.global_position.distance_to(castle_target.global_position) <= ClanCastle.TRIGGER_RADIUS:
				_release_castle(castle_id)
				break


func _release_castle(castle_id: String) -> void:
	var info: Dictionary = castles[castle_id]
	info["released"] = true
	var castle_target: BattleBuildingTarget = building_targets.get(castle_id)
	var structure := _get_structure(castle_id)
	if not is_instance_valid(castle_target) or structure.is_empty():
		return
	var troop_ids := ClanCastle.expand(info["garrison"])
	if troop_ids.is_empty():
		return
	var spawn_cells := _castle_spawn_cells(structure)
	var released := 0
	for troop_id in troop_ids:
		var actor := TroopActor.new()
		actor.name = "Defender_%s_%d" % [troop_id, defender_units.size() + 1]
		if not actor.configure(troop_id):
			actor.free()
			continue
		actor.team = TroopActor.Team.DEFENDER
		actor.castle_id = castle_id
		actor.leash_center = castle_target.global_position
		actor.leash_radius = ClanCastle.LEASH_RADIUS
		actor.global_position = village.grid.cell_to_world(Vector2(spawn_cells[released % spawn_cells.size()]))
		actor.home_position = actor.global_position
		actor.set_simulation_speed(speed_multiplier)
		actor.attack_requested.connect(_on_attack_requested)
		actor.died.connect(_on_defender_died)
		units_root.add_child(actor)
		defender_units.append(actor)
		released += 1
	defenders_released += released
	if released > 0:
		status_message.emit("Clan Castle troops rush out! (%d defenders)" % released)
		# Attackers now have defending troops to consider, so every attacker reconsiders its target.
		_queue_replan_all()
	battle_updated.emit()


## Free cells just outside the castle footprint, nearest first. Defenders appear here and walk home to here.
func _castle_spawn_cells(structure: Dictionary) -> Array[Vector2i]:
	var origin: Vector2i = structure["cell"]
	var footprint: Vector2i = structure["footprint"]
	var ranked: Array[Dictionary] = []
	for y in range(origin.y - 3, origin.y + footprint.y + 3):
		for x in range(origin.x - 3, origin.x + footprint.x + 3):
			var cell := Vector2i(x, y)
			if not village.grid.contains_cell(cell) or village.grid.occupied.has(cell):
				continue
			var dx := maxi(maxi(origin.x - x, 0), x - (origin.x + footprint.x - 1))
			var dy := maxi(maxi(origin.y - y, 0), y - (origin.y + footprint.y - 1))
			ranked.append({"cell": cell, "key": dx * dx + dy * dy})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["key"]) != int(b["key"]):
			return int(a["key"]) < int(b["key"])
		var ac: Vector2i = a["cell"]
		var bc: Vector2i = b["cell"]
		return ac.y < bc.y if ac.y != bc.y else ac.x < bc.x
	)
	var cells: Array[Vector2i] = []
	for entry in ranked:
		cells.append(entry["cell"])
	if cells.is_empty():
		cells.append(Vector2i(clampi(origin.x + footprint.x, 0, village.grid.width - 1), clampi(origin.y + footprint.y, 0, village.grid.height - 1)))
	return cells


func _update_defender_troops(delta: float) -> void:
	if defender_units.is_empty():
		return
	for defender in defender_units:
		if is_instance_valid(defender) and defender.state != TroopActor.State.DEAD:
			defender.think_cooldown = maxf(0.0, defender.think_cooldown - delta)
			defender.repath_cooldown = maxf(0.0, defender.repath_cooldown - delta)
	var attackers := _living_attackers()
	# Only a couple of full tactical decisions are made per frame so a large garrison never stalls the game.
	var decisions := 0
	for defender in defender_units:
		if not is_instance_valid(defender) or defender.state == TroopActor.State.DEAD:
			continue
		if defender.think_cooldown <= 0.0:
			if decisions >= DEFENDER_DECISIONS_PER_FRAME:
				continue
			decisions += 1
			_decide_defender(defender, attackers)
		else:
			_maintain_defender(defender)


func _defender_victim(defender: TroopActor) -> TroopActor:
	var current: Variant = defender.target
	if not is_instance_valid(current) or not (current is TroopActor):
		return null
	var victim := current as TroopActor
	if victim.state == TroopActor.State.DEAD or victim.hp <= 0 or victim.team != TroopActor.Team.ATTACKER:
		return null
	if victim.global_position.distance_to(defender.leash_center) > defender.leash_radius:
		return null
	return victim


func _decide_defender(defender: TroopActor, attackers: Array[TroopActor]) -> void:
	defender.think_cooldown = DEFENDER_THINK_INTERVAL + float(defender.get_instance_id() % 5) * 0.04
	var reachable: Array[TroopActor] = []
	for attacker in attackers:
		if attacker.is_flying and defender.attack_range <= 60.0:
			continue  # Melee defenders cannot reach a flyer.
		if attacker.global_position.distance_to(defender.leash_center) <= defender.leash_radius:
			reachable.append(attacker)
	if reachable.is_empty():
		_send_defender_home(defender)
		return
	var decision := BATTLE_SEARCH.select_defender_target(defender, reachable, strategy_algorithm, SUPPORT_RANGE)
	var chosen: TroopActor = null
	var chosen_id := str(decision.get("target_id", ""))
	for attacker in reachable:
		if BATTLE_SEARCH.attacker_target_id(attacker) == chosen_id:
			chosen = attacker
			break
	if chosen == null:
		_send_defender_home(defender)
		return
	decision["target_name"] = "%s (attacker)" % chosen.display_name
	last_defender_decision = decision
	var already_targeting := is_instance_valid(defender.target) and defender.target == chosen
	if not already_targeting:
		defender.assign_target(chosen)
	_chase_target(defender, chosen, true)


func _maintain_defender(defender: TroopActor) -> void:
	var victim := _defender_victim(defender)
	if victim != null:
		_chase_target(defender, victim, false)
	elif is_instance_valid(defender.target):
		defender.think_cooldown = 0.0  # Its victim died or ran out of reach: decide again right away.


func _chase_target(defender: TroopActor, victim: TroopActor, force: bool) -> void:
	if defender.global_position.distance_to(victim.global_position) <= defender.attack_range:
		return  # Already in range: stand and fight.
	if not force and defender.repath_cooldown > 0.0:
		return
	defender.repath_cooldown = REPATH_INTERVAL
	var path := _find_troop_path(defender, victim)
	if path.is_empty():
		_send_defender_home(defender)  # Cannot reach it (walled in): hold the line at home.
		defender.think_cooldown = 1.2
		return
	defender.set_walk_path(path, village.grid)


func _send_defender_home(defender: TroopActor) -> void:
	if defender.state == TroopActor.State.RETURN:
		return
	if defender.global_position.distance_to(defender.home_position) <= HOME_ARRIVAL_DISTANCE:
		if is_instance_valid(defender.target):
			defender.clear_target()
		return
	var start := village.grid.world_to_cell(defender.global_position)
	var goals: Array[Vector2i] = [village.grid.world_to_cell(defender.home_position)]
	var path: Array[Vector2i] = []
	if _can_reach(start, goals):
		path = GridPathfinder.find_path_to_any(village.grid, start, goals, path_algorithm)
	if path.is_empty():
		defender.clear_target()
		return
	defender.walk_home(path, village.grid)


# ---------------------------------------------------------------------------------------------
# Attackers reacting to defending troops
# ---------------------------------------------------------------------------------------------

## Attackers that are fighting a defending troop must keep following it as it moves.
func _update_attacker_chase(delta: float) -> void:
	if defender_units.is_empty():
		return
	for attacker in attacker_units:
		if not is_instance_valid(attacker) or attacker.state == TroopActor.State.DEAD:
			continue
		attacker.repath_cooldown = maxf(0.0, attacker.repath_cooldown - delta)
		var current: Variant = attacker.target
		if not is_instance_valid(current) or not (current is TroopActor):
			continue
		var victim := current as TroopActor
		if victim.state == TroopActor.State.DEAD or victim.hp <= 0:
			_queue_replan(attacker, true)
			continue
		if attacker.repath_cooldown > 0.0 or attacker.global_position.distance_to(victim.global_position) <= attacker.attack_range:
			continue
		attacker.repath_cooldown = REPATH_INTERVAL
		var path := _find_troop_path(attacker, victim)
		if path.is_empty():
			_queue_replan(attacker, true)
			attacker.repath_cooldown = 1.0
		else:
			attacker.set_walk_path(path, village.grid)


## Periodically lets attackers that are near a defending troop (or that are stuck without a target)
## reconsider what to do. Cheap: it only queues work, the queue serves a few plans per frame.
func _update_attacker_awareness(delta: float) -> void:
	_awareness_timer -= delta
	var tick := _awareness_timer <= 0.0
	if tick:
		_awareness_timer = AWARENESS_TICK
	var defenders := _living_defenders()
	for attacker in attacker_units:
		if not is_instance_valid(attacker) or attacker.state == TroopActor.State.DEAD:
			continue
		attacker.think_cooldown = maxf(0.0, attacker.think_cooldown - delta)
		if not tick or attacker.think_cooldown > 0.0:
			continue
		var stuck := not is_instance_valid(attacker.target) and attacker.state == TroopActor.State.IDLE
		var threatened := false
		for defender in defenders:
			if attacker.global_position.distance_to(defender.global_position) <= TROOP_ENGAGE_RANGE:
				threatened = true
				break
		if stuck or threatened:
			attacker.think_cooldown = ATTACKER_RECONSIDER_INTERVAL
			_queue_replan(attacker)


func _finish(final_phase: Phase) -> void:
	if phase == Phase.VICTORY or phase == Phase.DEFEAT or phase == Phase.TIMEOUT:
		return
	phase = final_phase
	_replan_queue.clear()
	for actor in _all_troops():
		actor.set_process(false)
	var loot_gold := roundi(350.0 * float(get_destruction_percent()) / 100.0)
	var loot_elixir := roundi(220.0 * float(get_destruction_percent()) / 100.0)
	village.gold += loot_gold
	village.elixir += loot_elixir
	var result := {
		"phase": Phase.keys()[phase],
		"stars": get_stars(),
		"destruction_percent": get_destruction_percent(),
		"town_hall_destroyed": town_hall_destroyed,
		"time_remaining": time_remaining,
		"loot_gold": loot_gold,
		"loot_elixir": loot_elixir,
		"defenders_released": defenders_released,
		"defenders_defeated": defenders_defeated,
	}
	battle_finished.emit(result)
