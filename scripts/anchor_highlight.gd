class_name AnchorHighlight
extends Node2D

const OUTLINE_SEGMENTS := 48

var radius := 0.0
var color := Color(0, 0, 0, 0)
var outline_width := 0.0
var outline_darkening := 0.0

func configure(
	new_radius: float,
	new_color: Color,
	new_outline_width: float,
	new_outline_darkening: float
) -> void:
	radius = new_radius
	color = new_color
	outline_width = new_outline_width
	outline_darkening = new_outline_darkening
	queue_redraw()

func _draw() -> void:
	if radius <= 0.0:
		return

	draw_circle(Vector2.ZERO, radius, color, true, -1.0, true)

	if outline_width > 0.0:
		draw_arc(
			Vector2.ZERO,
			radius,
			0.0,
			TAU,
			OUTLINE_SEGMENTS,
			color.darkened(outline_darkening),
			outline_width,
			true
		)
