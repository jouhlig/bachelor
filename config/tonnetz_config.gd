extends Resource
class_name TonnetzConfig

const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "H"]
@export var column_count: int = 12
@export var row_count: int = 8

@export_group("notes")
@export var note_color: Color = Color.WHITE
@export var note_label_color: Color = Color.BLACK
@export var note_border_color: Color = Color.BLACK
@export var note_outline_width: float = 2.0
@export var note_radius: float = 10.0

@export var background_color: Color = Color.WHITE

@export_group("turtle")
@export var player_radius: float = 8.0
@export var player_speed: float = 100.0
@export var player_color: Color = Color(1, 0.22352941, 1, 1)

@export_group("triangles")
@export var triangle_color: Color = Color.WHITE
@export var hex_size: float = 56.0  

@export_group("lines")
@export var line_color: Color = Color.BLACK
@export var line_width: float = 4.0
@export var line_duration: float = 0.2

@export var start_pos:  = Vector2(250,60)
@export var offset:  int = 100
@export var delay: float = .2
@export var bpm = 120

@export var number_iterations: int = 4

@export_range(0.5, 1.0, 0.01) 
var triangle_scale: float = 0.72  # Shrink triangles away from the notes
@export var base_note: int = 0
@export var trail_color: Color = Color.DARK_SLATE_GRAY
@export var pianoroll_size: Vector2 = Vector2(1920, 350)
@export var pianoroll_start_pos: Vector2 = Vector2(0, 1080-pianoroll_size.y)

@export var length_bars: int = 30
	
func triangle_color_for_pitches(pitches: Array[int]) -> Color:
	var normalized: Array[int] = []
	for pitch in pitches:
		normalized.append(posmod(pitch, NOTE_NAMES.size()))
	normalized.sort()

	var signature = ""
	for pitch in normalized:
		signature += str(pitch) + "_"

	var hash_value = abs(signature.hash())
	var hue = fmod(float(hash_value % 360), 360.0) / 360.0
	return Color.from_hsv(hue, 0.7, 0.92)
