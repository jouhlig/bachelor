extends Node2D
class_name AnimatedLine

signal finished

@export var config: TonnetzConfig

var start: Vector2
var end: Vector2
var t := 0.0
var color: Color

func _ready():
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "t", 1.0, config.line_duration)

	tween.finished.connect(func():
		emit_signal("finished")
	)

	queue_redraw()

func _process(_delta):
	queue_redraw()

func _draw():
	var current_end = start.lerp(end, t)
	draw_line(start, current_end, color, config.line_width)
