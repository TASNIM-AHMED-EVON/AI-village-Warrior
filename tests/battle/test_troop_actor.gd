extends SceneTree

var failures := 0
var attack_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for troop_id in TroopCatalog.all_ids():
		var definition := TroopCatalog.get_definition(troop_id)
		_check(int(definition["hp"]) > 0 and int(definition["damage"]) > 0, "%s has valid combat stats" % troop_id)
	var actor: Variant = load("res://scripts/units/troop_actor.gd").new()
	root.add_child(actor)
	_check(actor.configure("warrior"), "warrior actor configures from troop definition")
	var grid := VillageGrid.new(20, 20)
	var target := Node2D.new()
	root.add_child(target)
	target.position = Vector2(400, 0)
	actor.attack_requested.connect(_on_attack_requested)
	actor.assign_target(target)
	var route: Array[Vector2i] = [Vector2i(1, 0)]
	actor.set_walk_path(route, grid)
	actor.step(0.1)
	_check(actor.state == actor.State.MOVE, "out of range target triggers movement state")
	var old_position: Vector2 = actor.global_position
	actor.step(0.1)
	_check(actor.global_position.x > old_position.x, "troop advances toward target")
	target.global_position = actor.global_position + Vector2(20, 0)
	actor.step(0.016)
	# A troop that gets in range attacks in that same frame (ATTACK is resolved immediately into RECOVER).
	_check(attack_count == 1 and actor.state == actor.State.RECOVER, "in range target triggers an immediate attack")
	actor.step(0.016)
	_check(attack_count == 1 and actor.state == actor.State.RECOVER, "attack emits one action and enters recovery")
	actor.step(actor.attack_interval)
	actor.step(0.016)
	_check(attack_count == 2, "attack cooldown allows a later attack")
	actor.apply_damage(9999)
	_check(actor.hp == 0 and actor.state == actor.State.DEAD, "lethal damage enters dead state")
	actor.apply_damage(10)
	_check(actor.hp == 0, "dead unit cannot take additional damage")
	actor.free()
	target.free()
	if failures == 0:
		print("Troop actor checks passed.")
		quit(0)
	else:
		push_error("%d troop actor check(s) failed." % failures)
		quit(1)


func _on_attack_requested(_attacker: Node2D, _target: Node2D, _damage: int) -> void:
	attack_count += 1


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
