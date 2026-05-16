extends Node2D
@onready var config: TonnetzConfig = Config.config


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	queue_redraw()

func _draw():
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), config.background_color)
