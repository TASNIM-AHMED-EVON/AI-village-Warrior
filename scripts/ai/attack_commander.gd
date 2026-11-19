extends RefCounted
class_name AttackCommander
## The attacking AI for the Trial ("AI vs AI"). It plays the human's side: it reads the village layout, plans an
## attack and deploys troops on its own, then adapts as the battle unfolds. The troops themselves still choose
## targets and routes with the project's own search algorithms (Minimax / A*); the commander decides WHERE and
## WHEN to deploy, which is the part a human normally does.
##
## How it decides (every score is an expected-damage estimate, lower is better):
##   * approach damage  - damage a troop would take walking in a straight line from a deploy cell to an objective,
##                        counting only the defenses whose range covers each step (cannons cannot hit air);
##   * dwell damage     - damage taken while the objective is being destroyed, from the defenses that cover it;
##   * wall penalty     - extra cost for each wall the straight route crosses.
## It peels the base like an onion: the objective with the lowest total expected damage goes first, so the
## remaining defenses weaken as the attack goes on.

signal decided(text: String)

## What the base's defenses do (mirrors BattleManager._update_defenses).
const DEFENSE_REACH := {"cannon": 330.0, "archer_tower": 270.0, "wizard_tower": 300.0}
## The wizard tower's number includes its splash, which hurts clumped troops more than a single shot would.
const DEFENSE_DPS := {"cannon": 28.0, "archer_tower": 28.0, "wizard_tower": 28.0}
const DEFENSE_HITS_AIR := {"cannon": false, "archer_tower": true, "wizard_tower": true}
## The Clan Castle counts as a defense of this strength until its garrison has been dealt with.
const CASTLE_DPS := 45.0
## Tunable so the strategy can be tested (see tests): how fast troops are dropped and how tightly they cluster.
var deploy_period := 0.14
var support_pause := 0.5
var spread_penalty := 6.0
var air_wait := 0.0
var reserve_goblins_only := true
## Real seconds the briefing and heatmap stay on screen before the first troop is sent.
const OPENING_DELAY := 4.0
const SAMPLE_STEPS := 14
const TEAM_DPS := 120.0
## How long (battle seconds) a scoring of the deploy tiles is reused.
const SCORE_CACHE_SECONDS := 1.5
const WALL_PENALTY := 14.0
## How far from the best entry point (in tiles) troops may be spread out.
const CLUSTER_RADIUS := 6.0
const MAX_CANDIDATES := 220
const COMPASS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

enum Stage { ANALYSE, FRONT, SUPPORT, AIR, RESERVE, DONE }

var battle: BattleManager
var village: VillageModel
var stage: Stage = Stage.ANALYSE
var briefing: Array[String] = []
var log_lines: Array[String] = []
## {cell: Vector2i, exposure: float} for every deployment cell the commander considered (drawn as a heatmap).
var heatmap: Array[Dictionary] = []
## {cell: Vector2i, troop: String, time: float} for every troop deployed, so the screen can ping each one.
var deployments: Array[Dictionary] = []
var max_exposure := 1.0
var _initial_defenses := 0
var _candidates: Array[Vector2i] = []
var _band_cells: Array[Vector2i] = []  # Every deployable tile near the base (the heatmap); candidates are a sample of it.
var _wall_cells: Dictionary = {}
var _clock := 0.0
var _stage_clock := 0.0
var _cooldown := 0.0
var _objective_id := ""
var _objective_name := ""
var _recent_cells: Array[Vector2i] = []
var _score_cache: Dictionary = {}
var _queue: Array[String] = []
var _group_key := ""
var _group_count := 0
var _group_index := -1
var _group_sum := 0.0
var _group_cell := Vector2i.ZERO


func setup(manager: BattleManager) -> void:
	battle = manager
	village = manager.village
	for structure in village.structures:
		if str(structure["type"]) == "wall":
			_wall_cells[Vector2i(structure["cell"])] = true
	_collect_candidates()
	_analyse()
	_cooldown = OPENING_DELAY


func is_done() -> bool:
	return stage == Stage.DONE


## Called every frame with battle-clock seconds. Deploys at most one troop per call.
func tick(delta: float) -> void:
	if stage == Stage.DONE or battle == null:
		return
	if battle.phase >= BattleManager.Phase.VICTORY:
		stage = Stage.DONE
		return
	_clock += delta
	_stage_clock += delta
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	match stage:
		Stage.ANALYSE:
			_enter(Stage.FRONT)
		Stage.FRONT:
			_run_stage(Stage.SUPPORT, support_pause)
		Stage.SUPPORT:
			_run_stage(Stage.AIR, air_wait)
		Stage.AIR:
			_run_stage(Stage.RESERVE, 0.0)
		Stage.RESERVE:
			_run_reserve()


# ---------------------------------------------------------------------------------------------
# Stage machine
# ---------------------------------------------------------------------------------------------

func _enter(next_stage: Stage) -> void:
	stage = next_stage
	_stage_clock = 0.0
	_recent_cells.clear()
	_queue.clear()
	match next_stage:
		Stage.FRONT:
			var objective := _choose_objective("tank", false, true)
			_set_objective(objective)
			_say("PHASE 1 · Main push: tanks and warriors go in together on the cheapest side to the %s." % _objective_name)
			for _i in range(_stock("tank")):
				_queue.append("tank")
			var warriors := _stock("warrior") if reserve_goblins_only else ceili(float(_stock("warrior")) * 0.6)
			for _i in range(warriors):
				_queue.append("warrior")
		Stage.SUPPORT:
			_say("PHASE 2 · Ranged support: archers and mages follow on the same side.")
			for _i in range(_stock("archer")):
				_queue.append("archer")
			for _i in range(_stock("mage")):
				_queue.append("mage")
		Stage.AIR:
			var objective := _choose_objective("dragon", false, true)
			_set_objective(objective)
			if _stock("dragon") > 0:
				_say("PHASE 3 · Air strike: dragons fly over the walls with the push. Cannons cannot hit air, so only archer towers matter to them.")
			for _i in range(_stock("dragon")):
				_queue.append("dragon")
		Stage.RESERVE:
			_say("PHASE 4 · Reserves: remaining troops go where they are most needed.")
		Stage.DONE:
			_say("All troops committed. The battle is in the hands of the troop AI.")


func _run_stage(next_stage: Stage, pause_after: float, ready: Callable = Callable()) -> void:
	if not _queue.is_empty():
		var troop_id: String = _queue.pop_front()
		_deploy(troop_id)
		_cooldown = deploy_period
		return
	var enough_time := _stage_clock >= pause_after
	if ready.is_valid():
		enough_time = bool(ready.call())
	if enough_time:
		_enter(next_stage)


func _run_reserve() -> void:
	var remaining_total := 0
	for troop_id in battle.troop_stock:
		remaining_total += int(battle.troop_stock[troop_id])
	if remaining_total <= 0:
		_enter(Stage.DONE)
		return
	var alive := _alive_attackers()
	var thin := alive <= maxi(6, int(0.25 * float(battle.total_deployed)))
	var late := battle.get_destruction_percent() >= 55 or _stage_clock >= 22.0
	if not (thin or late):
		return
	if _queue.is_empty():
		# Pick the next objective and send the strongest troops that are left.
		var lead := _strongest_remaining()
		var objective := _choose_objective(lead, lead == "dragon")
		_set_objective(objective)
		_say("Reinforcing: %d troops still fighting, %d%% destroyed. New objective: %s." % [alive, battle.get_destruction_percent(), _objective_name])
		var batch := 0
		for troop_id in ["tank", "warrior", "archer", "mage", "goblin", "dragon"]:
			for _i in range(_stock(troop_id)):
				if batch >= 6:
					break
				_queue.append(troop_id)
				batch += 1
	if not _queue.is_empty():
		_deploy(_queue.pop_front())
		_cooldown = deploy_period
	_stage_clock = 0.0 if _queue.is_empty() and alive > 0 else _stage_clock


func _deploy(troop_id: String) -> void:
	if _stock(troop_id) <= 0:
		return
	var target: Variant = battle.building_targets.get(_objective_id)
	if not is_instance_valid(target):
		_set_objective(_choose_objective(troop_id, troop_id == "dragon"))
		target = battle.building_targets.get(_objective_id)
		if not is_instance_valid(target):
			return
	var pick := _best_cell(target.global_position, troop_id, _recent_cells)
	if pick.is_empty():
		return
	var cell: Vector2i = pick["cell"]
	if battle.deploy(troop_id, cell):
		_recent_cells.append(cell)
		if _recent_cells.size() > 4:
			_recent_cells.pop_front()
		deployments.append({"cell": cell, "troop": troop_id, "time": _clock})
		_log_deploy(troop_id, cell, pick)


func _log_deploy(troop_id: String, cell: Vector2i, pick: Dictionary) -> void:
	var key := "%s|%d" % [troop_id, stage]
	if key != _group_key:
		_group_key = key
		_group_count = 0
		_group_sum = 0.0
		_group_cell = cell
		log_lines.append("")
		_group_index = log_lines.size() - 1
	_group_count += 1
	_group_sum += float(pick.get("approach", 0.0))
	var name_text := str(TroopCatalog.get_definition(troop_id).get("name", troop_id))
	log_lines[_group_index] = "%s ×%d near %s, %s side · expected damage %d" % [
		name_text, _group_count, _cell_label(_group_cell), _side_of(village.grid.cell_to_world(Vector2(_group_cell))), int(_group_sum / float(_group_count)),
	]
	decided.emit(log_lines[_group_index])


func _say(text: String) -> void:
	log_lines.append(text)
	_group_key = ""
	decided.emit(text)


# ---------------------------------------------------------------------------------------------
# Analysis: what the base looks like, and which side is softest
# ---------------------------------------------------------------------------------------------

func _analyse() -> void:
	var cannons := 0
	var towers := 0
	var wizards := 0
	var castle: Dictionary = {}
	var town_hall: Dictionary = {}
	var objective_count := 0
	for structure in village.structures:
		match str(structure["type"]):
			"cannon":
				cannons += 1
			"archer_tower":
				towers += 1
			"wizard_tower":
				wizards += 1
			"clan_castle":
				castle = structure
			"town_hall":
				town_hall = structure
		if str(structure["type"]) != "wall":
			objective_count += 1
	_initial_defenses = cannons + towers + wizards
	briefing.append("LAYOUT ANALYSIS")
	briefing.append("• %d buildings must fall for 3 stars." % objective_count)
	if wizards > 0:
		briefing.append("• Defenses: %d cannons (ground only), %d archer towers and %d wizard towers (both hit air; wizards splash)." % [cannons, towers, wizards])
	else:
		briefing.append("• Defenses: %d cannons (ground only) and %d archer towers (hit air too)." % [cannons, towers])
	if not castle.is_empty():
		briefing.append("• Clan Castle at %s, garrison: %s." % [_cell_label(castle["cell"]), ClanCastle.describe(ClanCastle.sanitize(castle.get("garrison", null)))])
	if not town_hall.is_empty():
		briefing.append("• Town Hall at %s, behind a wall ring." % _cell_label(town_hall["cell"]))
	# Exposure heatmap over every candidate cell (ground troops).
	var defenses := _defenses()
	max_exposure = 1.0
	for cell in _band_cells:
		var exposure := _exposure_at(village.grid.cell_to_world(Vector2(cell)), false, defenses)
		heatmap.append({"cell": cell, "exposure": exposure})
		max_exposure = maxf(max_exposure, exposure)
	# Which side of the base is cheapest to approach? Score eight compass sectors against the Town Hall.
	var centre := _base_centre()
	var focus := centre
	if not town_hall.is_empty():
		focus = village.grid.cell_to_world(Vector2(town_hall["cell"]) + Vector2(1, 1))
	var sector_cost: Array[float] = []
	for _i in range(8):
		sector_cost.append(INF)
	for cell in _candidates:
		var world_point := village.grid.cell_to_world(Vector2(cell))
		var sector := _sector_of(world_point, centre)
		sector_cost[sector] = minf(sector_cost[sector], _approach_damage(world_point, focus, "tank", defenses))
	var ranking: Array[Dictionary] = []
	for index in range(8):
		if sector_cost[index] < INF:
			ranking.append({"side": COMPASS[index], "cost": sector_cost[index]})
	ranking.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["cost"]) < float(b["cost"]))
	if not ranking.is_empty():
		var parts: Array[String] = []
		for entry in ranking:
			parts.append("%s %d" % [entry["side"], int(entry["cost"])])
		briefing.append("• Expected damage to reach the Town Hall from each side: " + "  ".join(parts))
	var opening := _choose_objective("tank", false, true)
	if not opening.is_empty():
		var pick := _best_cell(opening["pos"], "tank", [], 1)
		briefing.append("• Decision: attack the %s side, the cheapest way to the %s." % [_side_of(village.grid.cell_to_world(Vector2(pick["cell"]))), opening["name"]])
	briefing.append("PLAN: one concentrated push on that side → ranged support → air strike → reserves mop up what is left.")


# ---------------------------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------------------------

func _defenses() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for target in battle.building_targets.values():
		if not is_instance_valid(target) or target.hp <= 0:
			continue
		var type := str(target.building_type)
		if DEFENSE_REACH.has(type):
			result.append({"id": target.building_id, "pos": target.global_position, "reach": DEFENSE_REACH[type], "dps": DEFENSE_DPS[type], "air": DEFENSE_HITS_AIR[type]})
		elif type == ClanCastle.BUILDING_ID and _castle_still_armed(target.building_id):
			result.append({"id": target.building_id, "pos": target.global_position, "reach": ClanCastle.TRIGGER_RADIUS, "dps": CASTLE_DPS, "air": false})
	return result


func _castle_still_armed(castle_id: String) -> bool:
	var info: Dictionary = battle.castles.get(castle_id, {})
	return not bool(info.get("lost", false))


func _exposure_at(point: Vector2, air: bool, defenses: Array[Dictionary]) -> float:
	var total := 0.0
	for defense in defenses:
		if air and not bool(defense["air"]):
			continue
		if point.distance_to(defense["pos"]) <= float(defense["reach"]):
			total += float(defense["dps"])
	return total


## Expected damage a troop takes walking from `from_point` to within range of `to_point`.
func _approach_damage(from_point: Vector2, to_point: Vector2, troop_id: String, defenses: Array[Dictionary], skip_id: String = "") -> float:
	var definition := TroopCatalog.get_definition(troop_id)
	var speed := maxf(float(definition["move_speed"]), 1.0)
	var air := bool(definition.get("flying", false))
	var reach := float(definition["range"]) * 48.0
	var length := from_point.distance_to(to_point)
	var walk := maxf(length - reach * 0.8, 0.0)
	if walk <= 0.0:
		return 0.0
	var seconds_per_step := (walk / float(SAMPLE_STEPS)) / speed
	var direction := (to_point - from_point) / maxf(length, 0.001)
	var total := 0.0
	for step in range(SAMPLE_STEPS + 1):
		var point := from_point + direction * (walk * float(step) / float(SAMPLE_STEPS))
		for defense in defenses:
			if air and not bool(defense["air"]):
				continue
			if str(defense["id"]) == skip_id:
				continue
			if point.distance_to(defense["pos"]) <= float(defense["reach"]):
				total += float(defense["dps"]) * seconds_per_step
	return total


func _wall_cost(from_point: Vector2, to_point: Vector2, troop_id: String) -> float:
	if bool(TroopCatalog.get_definition(troop_id).get("flying", false)):
		return 0.0
	var crossed := 0
	var steps := int(from_point.distance_to(to_point) / 18.0)
	var last := Vector2i(-999, -999)
	for step in range(steps + 1):
		var cell := village.grid.world_to_cell(from_point.lerp(to_point, float(step) / float(maxi(steps, 1))))
		if cell != last and _wall_cells.has(cell) and _wall_alive(cell):
			crossed += 1
		last = cell
	return float(crossed) * WALL_PENALTY


func _wall_alive(cell: Vector2i) -> bool:
	var occupant: Variant = village.grid.occupied.get(cell)
	return occupant != null and battle.building_targets.has(str(occupant))


## Best deployment cell for `troop_id` heading for `target_pos`. First the best entry point is found on cost alone;
## then, if recent drops are crowding it, the troop is spread to a free tile within a few tiles of that entry point
## (never across the map: the push stays together).
func _best_cell(target_pos: Vector2, troop_id: String, avoid: Array[Vector2i], stride: int = 1) -> Dictionary:
	var defenses := _defenses()
	# Scoring every tile is the expensive part, and the answer only changes when the defenses or the target change,
	# so one scoring is reused for a second or so (all the troops of one wave share it).
	var cache_key := "%s|%d|%d|%d|%d" % [troop_id, int(target_pos.x), int(target_pos.y), stride, defenses.size()]
	var cached: Dictionary = _score_cache.get(cache_key, {})
	var scored: Array[Dictionary] = []
	var best := {}
	var best_cost := INF
	if not cached.is_empty() and _clock - float(cached["time"]) < SCORE_CACHE_SECONDS:
		scored = cached["scored"]
		best = cached["best"]
	else:
		var index := 0
		for cell in _candidates:
			index += 1
			if stride > 1 and index % stride != 0:
				continue
			if not battle.is_valid_deployment_cell(cell):
				continue
			var from_point := village.grid.cell_to_world(Vector2(cell))
			var approach := _approach_damage(from_point, target_pos, troop_id, defenses)
			var cost := approach + 0.12 * from_point.distance_to(target_pos) + _wall_cost(from_point, target_pos, troop_id)
			var entry := {"cell": cell, "cost": cost, "approach": approach}
			scored.append(entry)
			if cost < best_cost:
				best_cost = cost
				best = entry
		_score_cache[cache_key] = {"time": _clock, "scored": scored, "best": best}
	if best.is_empty() or avoid.is_empty():
		return best
	var anchor: Vector2i = best["cell"]
	var spread := _effective_spread_penalty()
	var chosen := best
	var chosen_cost := INF
	for entry in scored:
		var cell: Vector2i = entry["cell"]
		if Vector2(cell).distance_to(Vector2(anchor)) > CLUSTER_RADIUS:
			continue
		var cost := float(entry["cost"])
		for other in avoid:
			if Vector2(cell).distance_to(Vector2(other)) < 3.0:
				cost += spread
		if cost < chosen_cost:
			chosen_cost = cost
			chosen = entry
	return chosen


## The building to hit first: the one whose total expected damage (approach + time spent under fire) is lowest.
func _choose_objective(troop_id: String, prefer_anti_air: bool, town_hall_first: bool = false) -> Dictionary:
	if town_hall_first:
		for target in battle.building_targets.values():
			if is_instance_valid(target) and target.hp > 0 and str(target.building_type) == "town_hall":
				return {"id": target.building_id, "name": str(target.building_name), "cost": 0.0, "pos": target.global_position}
	var defenses := _defenses()
	var candidates: Array = []
	var has_defense := false
	for target in battle.building_targets.values():
		if not is_instance_valid(target) or target.hp <= 0 or str(target.building_type) == "wall":
			continue
		var type := str(target.building_type)
		var is_defense := DEFENSE_REACH.has(type) or type == ClanCastle.BUILDING_ID
		if prefer_anti_air:
			is_defense = type == "archer_tower"
		if is_defense:
			has_defense = true
		candidates.append({"target": target, "defense": is_defense})
	var best := {}
	var best_cost := INF
	for entry in candidates:
		if has_defense and not bool(entry["defense"]):
			continue
		var target: BattleBuildingTarget = entry["target"]
		var pick := _best_cell(target.global_position, troop_id, [], 3)
		if pick.is_empty():
			continue
		var air := bool(TroopCatalog.get_definition(troop_id).get("flying", false))
		var dwell := clampf(float(target.hp) / TEAM_DPS, 2.0, 25.0)
		var dwell_cost := _exposure_at(target.global_position, air, defenses) * dwell * 0.5
		if DEFENSE_DPS.has(str(target.building_type)):
			dwell_cost -= float(DEFENSE_DPS[str(target.building_type)]) * dwell * 0.5  # The target does not shoot once it is dying.
		var cost := float(pick["cost"]) + maxf(dwell_cost, 0.0)
		if cost < best_cost:
			best_cost = cost
			best = {"id": target.building_id, "name": str(target.building_name), "cost": cost, "pos": target.global_position}
	return best


## Splash defenses (the wizard tower) punish a tight blob, so while one is standing the commander spreads out.
func _effective_spread_penalty() -> float:
	for target in battle.building_targets.values():
		if is_instance_valid(target) and target.hp > 0 and str(target.building_type) == "wizard_tower":
			return spread_penalty * 4.0
	return spread_penalty


func _set_objective(objective: Dictionary) -> void:
	_objective_id = str(objective.get("id", ""))
	_objective_name = str(objective.get("name", "none"))


# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

func _collect_candidates() -> void:
	var clearance := float(BattleManager.DEPLOYMENT_CLEARANCE_TILES)
	var all_cells: Array[Vector2i] = []
	for y in range(village.grid.height):
		for x in range(village.grid.width):
			var cell := Vector2i(x, y)
			if not battle.is_valid_deployment_cell(cell):
				continue
			if _edge_distance(cell) <= clearance + 6.0:
				all_cells.append(cell)
	_band_cells = all_cells
	var stride := maxi(1, ceili(float(all_cells.size()) / float(MAX_CANDIDATES)))
	for index in range(0, all_cells.size(), stride):
		_candidates.append(all_cells[index])


func _edge_distance(cell: Vector2i) -> float:
	var best := INF
	for structure in village.structures:
		var origin: Vector2i = structure["cell"]
		var footprint: Vector2i = structure["footprint"]
		var dx := maxi(maxi(origin.x - cell.x, 0), cell.x - (origin.x + footprint.x - 1))
		var dy := maxi(maxi(origin.y - cell.y, 0), cell.y - (origin.y + footprint.y - 1))
		best = minf(best, Vector2(float(dx), float(dy)).length())
	return best


func _base_centre() -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for structure in village.structures:
		if str(structure["type"]) == "wall":
			continue
		total += village.grid.cell_to_world(Vector2(structure["cell"]))
		count += 1
	return total / float(maxi(count, 1))


func _sector_of(point: Vector2, centre: Vector2) -> int:
	var angle := (point - centre).angle()
	return posmod(roundi(angle / (TAU / 8.0)), 8)


func _side_of(world_point: Vector2) -> String:
	return COMPASS[_sector_of(world_point, _base_centre())]


func _cell_label(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]


func _stock(troop_id: String) -> int:
	return int(battle.troop_stock.get(troop_id, 0))


func _alive_attackers() -> int:
	var alive := 0
	for index in range(battle.attacker_units.size()):
		var unit: Variant = battle.attacker_units[index]
		if is_instance_valid(unit) and unit.state != TroopActor.State.DEAD:
			alive += 1
	return alive


func _defenses_destroyed() -> int:
	var remaining := 0
	for target in battle.building_targets.values():
		if is_instance_valid(target) and DEFENSE_REACH.has(str(target.building_type)):
			remaining += 1
	return maxi(0, _initial_defenses - remaining)


func _strongest_remaining() -> String:
	for troop_id in ["tank", "warrior", "dragon", "archer", "mage", "goblin"]:
		if _stock(troop_id) > 0:
			return troop_id
	return "warrior"
