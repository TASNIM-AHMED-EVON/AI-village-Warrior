extends Node2D
## Canvas for the AI commander's heatmap and deploy pings. It is its own node, drawn above the terrain,
## because a parent's own _draw() is covered by its children.
var painter: Callable


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
