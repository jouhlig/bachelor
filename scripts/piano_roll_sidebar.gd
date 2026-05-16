extends Control

@onready var font = ThemeDB.fallback_font
var current_scroll_y := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func refresh_view(scroll_y: float) -> void:
	if current_scroll_y == scroll_y:
		return
	current_scroll_y = scroll_y
	queue_redraw()

func _draw() -> void:
	var piano_roll = get_parent()
	if piano_roll == null:
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)

	for pitch in range(piano_roll.MIN_PITCH, piano_roll.MAX_PITCH + 1):
		var y = (piano_roll.MAX_PITCH - pitch) * piano_roll.CELL_HEIGHT - current_scroll_y
		draw_string(font, Vector2(5, y + piano_roll.CELL_HEIGHT - 4), piano_roll.pitch_to_name(pitch))
