extends Control

@onready var font = ThemeDB.fallback_font
var current_scroll_x := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func refresh_view(scroll_x: float) -> void:
	if current_scroll_x == scroll_x:
		return
	current_scroll_x = scroll_x
	queue_redraw()

func _draw() -> void:
	var piano_roll = get_parent()
	if piano_roll == null:
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color.RED)

	var last_bar = piano_roll.config.length_bars
	var beats_per_bar = piano_roll.beats_per_bar
	var cell_width = piano_roll.CELL_WIDTH

	for bar_index in range(last_bar):
		var x = bar_index * beats_per_bar * cell_width - current_scroll_x
		draw_string(font, Vector2(x+cell_width*beats_per_bar/2-4, size.y - 2), str(bar_index + 1))
		draw_line(Vector2(x,0), Vector2(x,size.y), Color.BLUE, 2)
