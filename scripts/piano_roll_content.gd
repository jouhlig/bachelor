extends Control

@onready var piano_roll = get_parent().get_parent()
@onready var cell_width = piano_roll.CELL_WIDTH
@onready var cell_height = piano_roll.CELL_HEIGHT
@onready var font = ThemeDB.fallback_font
var note_calculator
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_calculator = NoteValueCalculator.new()
func _draw() -> void:
	if piano_roll == null:
		return

	var seconds_per_beat = piano_roll.get_seconds_per_beat()
	
	var max_pitch = piano_roll.MAX_PITCH
	var min_pitch = piano_roll.MIN_PITCH
	var total_rows = max_pitch - min_pitch + 1
	var last_bar = piano_roll.config.length_bars
	var beats_per_bar = piano_roll.beats_per_bar

	for i in range(last_bar + 1):
		for beat in range(beats_per_bar):
			var x = cell_width * (i * beats_per_bar + beat)
			var color = Color(0.2, 0.2, 0.2)
			if beat == 0:
				color = Color.BLUE
			draw_line(Vector2(x, 0), Vector2(x, total_rows * cell_height), color, 2)

	for row in range(total_rows + 1):
		var y = row * cell_height
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.15, 0.15, 0.15), 1)

	for note in piano_roll.notes:
		var note_start = note.start_beat
		var duration = note.duration_beats
		var pitch = note.pitch
		var pitch_label = note_calculator.get_note_name(pitch)
		var note_start_seconds = note_start * seconds_per_beat
		var note_end_seconds = (note_start + duration) * seconds_per_beat
		var x = note_start_seconds * cell_width
		var w = (note_end_seconds - note_start_seconds) * cell_width
		var y = (max_pitch - pitch) * cell_height
		draw_rect(Rect2(x, y, w, cell_height), Color.SKY_BLUE)
		draw_string(font, Vector2(x,y+10),pitch_label)
	# Draw playback position indicator
	var current_beat = CL.time_beat
	var current_x = current_beat * cell_width
	draw_line(Vector2(current_x, 0), Vector2(current_x, total_rows * cell_height), Color.YELLOW, 3)
