extends RefCounted
class_name BattleSearchAI
## Bounded, data-only tactical search. It never changes live nodes or battle state.
##
## One search core serves both sides of the battle:
##   * select_target():          an ATTACKER picks a building or a defending troop to hit.
##   * select_defender_target(): a Clan Castle DEFENDER picks which attacker to fight.
##
## The game tree alternates two players:
##   MAX  - the acting troop chooses what to hit.
##   MIN  - the opposition answers. Each opposing "defense" (a tower, a cannon, or a whole group of
##          troops) either lands its volley or misses. Minimax/Alpha-Beta assume the worst case
##          (every volley lands); Expectimax averages with the hit probability.
##
## Crucially, the answer depends on the MAX move: a defense only answers if it covers the spot
## from which the troop would be attacking the chosen target. Different targets therefore draw
## different replies, which is what makes the adversarial search meaningful.
## A troop that is ALREADY inside a defense's reach is also covered wherever it goes next: it takes
## the volleys while it walks away, so running to a distant target is not a free escape.

const MINIMAX := "Minimax"
const ALPHA_BETA := "Alpha-Beta"
const EXPECTIMAX := "Expectimax"
const ALGORITHMS := [MINIMAX, ALPHA_BETA, EXPECTIMAX]
const MAX_DEPTH := 4
const MAX_NODES := 2500
const MAX_TIME_MS := 18
const MAX_CANDIDATES := 8
const MAX_TROOP_CANDIDATES := 6
const COVERAGE_SLACK := 24.0
const KILL_BONUS := 0.22
const DEFENDER_ID_PREFIX := "defender_"
const ATTACKER_ID_PREFIX := "attacker_"

var _nodes := 0
var _pruned := 0
var _deadline_usec := 0
var _budget_hit := false
var _algorithm := ALPHA_BETA
var _actor_damage := 0
var _actor_max_hp := 1
var _actor_position := Vector2.ZERO
var _targets: Array[Dictionary] = []
var _defenses: Array[Dictionary] = []


static func defender_target_id(defender: Node) -> String:
	return "%s%d" % [DEFENDER_ID_PREFIX, defender.get_instance_id()]


static func attacker_target_id(attacker: Node) -> String:
	return "%s%d" % [ATTACKER_ID_PREFIX, attacker.get_instance_id()]


## Attacker-side decision.
##   defenses:        [{id, damage, hit_probability, range?, position?, rate?, members?}]. A defense without a
##                    `position` answers every target (legacy behaviour). `members` groups several shooters into
##                    one volley: [{target_id?, damage, position?, range?}].
##   troop_targets:   live defending troops the attacker may fight instead of a building.
##   stand_positions: {target_id: Vector2} where the attacker would stand while attacking that target.
static func select_target(
	attacker: TroopActor,
	candidates: Array[BattleBuildingTarget],
	structures: Array[Dictionary],
	defenses: Array[Dictionary],
	algorithm: String = ALPHA_BETA,
	path_costs: Dictionary = {},
	troop_targets: Array[TroopActor] = [],
	stand_positions: Dictionary = {}
) -> Dictionary:
	var search = load("res://scripts/ai/battle_search_ai.gd").new()
	return search._run_attacker(attacker, candidates, structures, defenses, algorithm, path_costs, troop_targets, stand_positions)


## Defender-side decision: which attacker should this defending troop fight?
##   `attackers` are the live attackers it may reach. Every attacker near the chosen victim is modelled
##   as a possible retaliation, so a defender avoids dives into a crowd and finishes weakened, dangerous troops.
static func select_defender_target(
	defender: TroopActor,
	attackers: Array[TroopActor],
	algorithm: String = ALPHA_BETA,
	support_range: float = 150.0
) -> Dictionary:
	var search = load("res://scripts/ai/battle_search_ai.gd").new()
	return search._run_defender(defender, attackers, algorithm, support_range)


static func troop_value(troop: TroopActor) -> float:
	# How dangerous a troop is: its damage per second. Squishy, high-damage troops are the best kills.
	return 30.0 + float(troop.damage) / maxf(troop.attack_interval, 0.1) * 1.4


func _run_attacker(
	attacker: TroopActor,
	candidates: Array[BattleBuildingTarget],
	structures: Array[Dictionary],
	defenses: Array[Dictionary],
	algorithm: String,
	path_costs: Dictionary,
	troop_targets: Array[TroopActor],
	stand_positions: Dictionary
) -> Dictionary:
	_begin(algorithm, attacker)
	var buildings: Array[Dictionary] = []
	for target in candidates:
		if not is_instance_valid(target) or target.hp <= 0:
			continue
		var structure := _find_structure(structures, target.building_id)
		if structure.is_empty():
			continue
		if not path_costs.is_empty() and not path_costs.has(target.building_id):
			continue
		var route_cost := float(path_costs.get(target.building_id, attacker.global_position.distance_to(target.global_position) / 48.0))
		var value := _building_value(structure, attacker.troop_id)
		buildings.append({
			"id": target.building_id, "kind": "building", "hp": target.hp,
			"max_hp": maxi(int(structure.get("max_hp", 1)), 1), "value": value,
			"route_cost": route_cost, "static": value - route_cost * 0.6,
			"position": stand_positions.get(target.building_id, target.global_position),
		})
	buildings.sort_custom(_by_static_desc)
	if buildings.size() > MAX_CANDIDATES:
		buildings.resize(MAX_CANDIDATES)
	var troops: Array[Dictionary] = []
	for troop in troop_targets:
		if not is_instance_valid(troop) or troop.hp <= 0 or troop.state == TroopActor.State.DEAD:
			continue
		var troop_key := defender_target_id(troop)
		if not path_costs.is_empty() and not path_costs.has(troop_key):
			continue
		var route_cost := float(path_costs.get(troop_key, attacker.global_position.distance_to(troop.global_position) / 48.0))
		var value := troop_value(troop)
		troops.append({
			"id": troop_key, "kind": "troop", "hp": troop.hp, "max_hp": maxi(troop.max_hp, 1),
			"value": value, "route_cost": route_cost, "static": value - route_cost * 0.6,
			"position": stand_positions.get(troop_key, troop.global_position),
		})
	troops.sort_custom(_by_static_desc)
	if troops.size() > MAX_TROOP_CANDIDATES:
		troops.resize(MAX_TROOP_CANDIDATES)
	_targets = buildings + troops
	_targets.sort_custom(_by_static_desc)
	_prepare_defenses(defenses)
	return _search_root(attacker.hp, "Highest-scoring legal target after bounded tactical search.")


func _run_defender(defender: TroopActor, attackers: Array[TroopActor], algorithm: String, support_range: float) -> Dictionary:
	_begin(algorithm, defender)
	var members: Array[Dictionary] = []
	for attacker in attackers:
		if not is_instance_valid(attacker) or attacker.hp <= 0 or attacker.state == TroopActor.State.DEAD:
			continue
		var attacker_key := attacker_target_id(attacker)
		var route_cost := defender.global_position.distance_to(attacker.global_position) / 48.0
		var value := troop_value(attacker) + (1.0 - float(attacker.hp) / float(maxi(attacker.max_hp, 1))) * 10.0
		_targets.append({
			"id": attacker_key, "kind": "troop", "hp": attacker.hp, "max_hp": maxi(attacker.max_hp, 1),
			"value": value, "route_cost": route_cost, "static": value - route_cost * 0.6,
			"position": attacker.global_position,
		})
		# Every attacker is a potential retaliation. Hitting one of them also draws in its neighbours.
		var rate := clampf(defender.attack_interval / maxf(attacker.attack_interval, 0.1), 0.25, 3.0)
		members.append({
			"target_id": attacker_key, "damage": float(attacker.damage) * rate,
			"position": attacker.global_position, "range": attacker.attack_range + support_range,
		})
	_targets.sort_custom(_by_static_desc)
	if _targets.size() > MAX_CANDIDATES:
		_targets.resize(MAX_CANDIDATES)
	var groups: Array[Dictionary] = []
	if not members.is_empty():
		groups.append({"id": "retaliation", "hit_probability": 0.85, "members": members})
	_prepare_defenses(groups)
	return _search_root(defender.hp, "Best attacker to fight after bounded tactical search.")


func _begin(algorithm: String, actor: TroopActor) -> void:
	_algorithm = algorithm if ALGORITHMS.has(algorithm) else ALPHA_BETA
	_actor_damage = maxi(actor.damage, 1)
	_actor_max_hp = maxi(actor.max_hp, 1)
	_actor_position = actor.global_position
	_targets = []
	_defenses = []


func _prepare_defenses(raw_defenses: Array[Dictionary]) -> void:
	_defenses = []
	for raw in raw_defenses:
		var rate := float(raw.get("rate", 1.0))
		var raw_members: Array = raw.get("members", [])
		if raw_members.is_empty():
			raw_members = [{
				"target_id": str(raw.get("target_id", "")), "damage": float(raw.get("damage", 0)),
				"position": raw.get("position", null), "range": float(raw.get("range", 0.0)),
			}]
		var members: Array[Dictionary] = []
		for raw_member in raw_members:
			var position: Variant = raw_member.get("position", null)
			var reach := float(raw_member.get("range", 0.0))
			var covers: Dictionary = {}
			for target_data in _targets:
				var covered := true
				if position is Vector2:
					var limit := reach + COVERAGE_SLACK
					covered = (target_data["position"] as Vector2).distance_to(position) <= limit or _actor_position.distance_to(position) <= limit
				covers[str(target_data["id"])] = covered
			members.append({
				"target_id": str(raw_member.get("target_id", "")),
				"damage": float(raw_member.get("damage", 0.0)) * rate,
				"covers": covers,
			})
		_defenses.append({
			"id": str(raw.get("id", "")),
			"hit_probability": clampf(float(raw.get("hit_probability", 0.85)), 0.0, 1.0),
			"members": members,
		})


func _search_root(actor_hp: int, reason: String) -> Dictionary:
	if _targets.is_empty():
		return {"target_id": "", "algorithm": _algorithm, "score": 0.0, "depth": 0, "nodes": 0, "pruned": 0, "time_ms": 0.0, "budget_hit": false, "reason": reason}
	var state := {"hp": {}, "actor_hp": float(actor_hp), "last": ""}
	for target_data in _targets:
		state["hp"][str(target_data["id"])] = int(target_data["hp"])
	_nodes = 0
	_pruned = 0
	_budget_hit = false
	var start_usec := Time.get_ticks_usec()
	_deadline_usec = start_usec + MAX_TIME_MS * 1000
	var best_id := str(_targets[0]["id"])
	var best_score := -INF
	var completed_depth := 0
	for depth in range(1, MAX_DEPTH + 1):
		if _budget_hit:
			break
		var iteration_id := best_id
		var iteration_score := -INF
		for target_data in _targets:
			if _over_budget():
				break
			var target_id := str(target_data["id"])
			var next_state: Dictionary = _attack(state, target_id)
			var score := _search_min(next_state, depth - 1, -INF, INF)
			if score > iteration_score:
				iteration_score = score
				iteration_id = target_id
		if not _budget_hit and iteration_score > -INF:
			best_id = iteration_id
			best_score = iteration_score
			completed_depth = depth
		else:
			break
	var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	return {
		"target_id": best_id,
		"algorithm": _algorithm,
		"score": best_score if best_score > -INF else float(_targets[0]["static"]),
		"depth": completed_depth,
		"nodes": _nodes,
		"pruned": _pruned,
		"time_ms": elapsed_ms,
		"budget_hit": _budget_hit,
		"reason": reason,
	}


func _search_min(state: Dictionary, depth: int, alpha: float, beta: float) -> float:
	if _over_budget():
		return _evaluate(state)
	_nodes += 1
	if depth <= 0 or float(state["actor_hp"]) <= 0.0:
		return _evaluate(state)
	var volleys := _active_volleys(state)
	if volleys.is_empty():
		return _search_max(state, depth - 1, alpha, beta)
	if _algorithm == EXPECTIMAX:
		return _search_chance(state, volleys, 0, depth, alpha, beta)
	return _search_min_volleys(state, volleys, 0, depth, alpha, beta)


## The opposition's answer to the move just made: only defenses that cover the chosen target
## (and are still alive) contribute, and they are grouped so each group is ONE hit/miss decision.
func _active_volleys(state: Dictionary) -> Array[Dictionary]:
	var volleys: Array[Dictionary] = []
	var last := str(state["last"])
	for defense in _defenses:
		var damage := 0.0
		for member in defense["members"]:
			var linked := str(member["target_id"])
			if not linked.is_empty() and int(state["hp"].get(linked, 1)) <= 0:
				continue
			if bool(member["covers"].get(last, false)):
				damage += float(member["damage"])
		if damage > 0.0:
			volleys.append({"damage": damage, "hit_probability": float(defense["hit_probability"])})
	return volleys


func _search_min_volleys(state: Dictionary, volleys: Array[Dictionary], index: int, depth: int, alpha: float, beta: float) -> float:
	if _over_budget():
		return _evaluate(state)
	_nodes += 1
	if index >= volleys.size():
		return _search_max(state, depth - 1, alpha, beta)
	var hit_state: Dictionary = state.duplicate(true)
	hit_state["actor_hp"] = maxf(0.0, float(state["actor_hp"]) - float(volleys[index]["damage"]))
	var hit_value := _search_min_volleys(hit_state, volleys, index + 1, depth, alpha, beta)
	if _algorithm == ALPHA_BETA and hit_value <= alpha:
		_pruned += 1
		return hit_value
	beta = minf(beta, hit_value)
	var miss_value := _search_min_volleys(state, volleys, index + 1, depth, alpha, beta)
	var worst := minf(hit_value, miss_value)
	if _algorithm == ALPHA_BETA and beta <= alpha:
		_pruned += 1
	return worst


func _search_chance(state: Dictionary, volleys: Array[Dictionary], index: int, depth: int, alpha: float, beta: float) -> float:
	if _over_budget():
		return _evaluate(state)
	_nodes += 1
	if index >= volleys.size():
		return _search_max(state, depth - 1, alpha, beta)
	var hit_probability := float(volleys[index]["hit_probability"])
	var hit_state: Dictionary = state.duplicate(true)
	hit_state["actor_hp"] = maxf(0.0, float(state["actor_hp"]) - float(volleys[index]["damage"]))
	var hit_value := _search_chance(hit_state, volleys, index + 1, depth, alpha, beta)
	var miss_value := _search_chance(state, volleys, index + 1, depth, alpha, beta)
	return hit_probability * hit_value + (1.0 - hit_probability) * miss_value


func _search_max(state: Dictionary, depth: int, alpha: float, beta: float) -> float:
	if _over_budget():
		return _evaluate(state)
	_nodes += 1
	if depth <= 0 or float(state["actor_hp"]) <= 0.0:
		return _evaluate(state)
	var best := -INF
	var found := false
	for target_data in _targets:
		if _over_budget():
			break
		var target_id := str(target_data["id"])
		if int(state["hp"].get(target_id, 0)) <= 0:
			continue
		found = true
		var next_state: Dictionary = _attack(state, target_id)
		var score := _search_min(next_state, depth - 1, alpha, beta)
		best = maxf(best, score)
		alpha = maxf(alpha, best)
		if _algorithm == ALPHA_BETA and beta <= alpha:
			_pruned += 1
			break
	if not found:
		return _evaluate(state)
	return _evaluate(state) if best == -INF else best


func _attack(state: Dictionary, target_id: String) -> Dictionary:
	var next_state: Dictionary = state.duplicate(true)
	next_state["hp"][target_id] = maxi(0, int(state["hp"].get(target_id, 0)) - _actor_damage)
	next_state["last"] = target_id
	return next_state


func _evaluate(state: Dictionary) -> float:
	var score := (float(state["actor_hp"]) / float(_actor_max_hp)) * 85.0
	for target_data in _targets:
		var target_id := str(target_data["id"])
		var max_hp := maxi(int(target_data["max_hp"]), 1)
		var remaining := clampf(float(state["hp"].get(target_id, 0)) / float(max_hp), 0.0, 1.0)
		var value := float(target_data["value"])
		score += value * (1.0 - remaining)
		if remaining <= 0.0:
			score += value * KILL_BONUS
	return score


func _over_budget() -> bool:
	if _nodes >= MAX_NODES or Time.get_ticks_usec() >= _deadline_usec:
		_budget_hit = true
		return true
	return false


func _by_static_desc(a: Dictionary, b: Dictionary) -> bool:
	return float(a["static"]) > float(b["static"])


func _building_value(structure: Dictionary, troop_id: String) -> float:
	var type := str(structure.get("type", ""))
	if type == "town_hall":
		return 120.0
	if type == "gold_mine" or type == "elixir_pump":
		return 82.0 if troop_id == "goblin" else 58.0
	if type == "cannon" or type == "archer_tower" or type == "mage_tower":
		return 78.0
	if type == ClanCastle.BUILDING_ID:
		return 72.0
	if type == "barracks":
		return 65.0
	if type == "wall":
		return 12.0
	return 30.0


func _find_structure(structures: Array[Dictionary], structure_id: String) -> Dictionary:
	for structure in structures:
		if str(structure.get("id", "")) == structure_id:
			return structure
	return {}
