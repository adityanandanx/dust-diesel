extends Control
class_name RadialCooldown

@export_range(0.0, 1.0, 0.001) var ratio: float = 0.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()

@export var ring_width: float = 6.0
@export var ring_color: Color = Color(0.95, 0.7, 0.2, 0.95)
@export var background_color: Color = Color(0.15, 0.15, 0.15, 0.75)


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = maxf(minf(size.x, size.y) * 0.5 - ring_width, 2.0)
	var points: int = 64
	var start_angle: float = - PI * 0.5

	draw_arc(center, radius, 0.0, TAU, points, background_color, ring_width, true)
	if ratio <= 0.0:
		return

	var end_angle: float = start_angle + TAU * ratio
	draw_arc(center, radius, start_angle, end_angle, points, ring_color, ring_width, true)
