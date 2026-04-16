extends Resource
class_name TonnetzConfig

const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "H"]

@export var note_radius: float = 16.0
@export var player_radius: float = 10.0
@export var player_speed: float = 100.0
@export var note_color: Color = Color.WHITE
@export var note_label_color: Color = Color.BLACK
#@export var note_label_outline_color: Color = Color.BLACK
@export var player_color: Color = Color(1, 0.22352941, 1, 1)
@export var triangle_color: Color = Color.GREEN
@export var hex_size: float = 56.0  # More spacing between note centers
@export_range(0.5, 1.0, 0.01) var triangle_scale: float = 0.72  # Shrink triangles away from the notes
@export var base_note: int = 0

func hex_to_world(q: int, r: int) -> Vector2:
	var x = sqrt(3) * (q + r / 2.0) * hex_size
	var y = 1.5 * r * hex_size
	return Vector2(x, y)

func pitch_class_to_name(pitch_class: int) -> String:
	return NOTE_NAMES[posmod(pitch_class, NOTE_NAMES.size())]
