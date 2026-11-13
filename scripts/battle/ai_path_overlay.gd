extends Node2D
## A true trace of the CURRENT pathfinder's expanded nodes and chosen routes.
## Rendering is event-driven; none of the search algorithms are approximated.

const ROUTE_COLORS := {
	"BFS": Color("72d7fb"),
	"A* Search": Color("f9d777"),
	"Greedy BFS": Color("a7e78e"),
	"Weighted Best-First Search": Color("d6abfa"),
}
const MAX_DRAWN_VISITS := 1000  # Bounded rendering even for very broad BFS searches.

var battle: BattleManager


func set_battle(manager: BattleManager) -> void:
	battle = manager
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if battle == null or not battle.visualization_enabled or battle.village == null:
		return
	var grid: VillageGrid = battle.village.grid
	for actor_id in battle.path_traces:
		var trace: Dictionary = battle.path_traces[actor_id]
		var color: Color = ROUTE_COLORS.get(str(trace.get("algorithm", "")), Color("fff2af"))
		var visited: Array = trace.get("visited", [])
		for index in range(mini(visited.size(), MAX_DRAWN_VISITS)):
			var point := grid.cell_to_world(Vector2(visited[index]))
			var diamond := PackedVector2Array([
				point + Vector2(0, -6), point + Vector2(11, 0),
				point + Vector2(0, 6), point + Vector2(-11, 0),
			])
			draw_colored_polygon(diamond, Color(color.r, color.g, color.b, 0.12))
		var path: Array = trace.get("path", [])
		if path.size() < 2:
			continue
		var line := PackedVector2Array()
		for cell in path:
			line.append(grid.cell_to_world(Vector2(cell)) + Vector2(0, -4))
		draw_polyline(line, Color("10202a", 0.78), 6.0, true)
		draw_polyline(line, Color(color.r, color.g, color.b, 0.85), 3.0, true)
		var goal := grid.cell_to_world(Vector2(path.back()))
		draw_arc(goal, 12.0, 0, TAU, 20, color, 2.0, true)
