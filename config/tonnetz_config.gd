extends Resource
class_name TonnetzConfig

const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
@export var column_count: int = 10
@export var row_count: int = 6
@export var wrap_row_count: int = 6
@export var font = load("res://fonts/Rubik-VariableFont_wght.ttf")

@export_group("notes")
@export var note_color: Color = Color.WHITE
@export var note_label_color: Color = Color.BLACK
@export var note_border_color: Color = Color.BLACK
@export var note_radius: float = 19

#@export var background_color: Color = Color.WHITE
@export var outline_width: float = 1.0

@export_group("turtle")
@export var player_radius: float = 8.0
@export var trail_dot_radius: float = 4.0
@export var trail_dot_spacing: float = 10.0
@export var trail_fade_duration: float = 2.0
@export var trail_fade_delay: float = 0.0
@export var VOICE_COLORS : Array[Color]= [
	Color(0.1, 0.74, 0.61),
	Color(0.93, 0.32, 0.27),
	Color(0.2, 0.45, 0.9),
	Color(0.95, 0.72, 0.18),
	Color(0.64, 0.34, 0.83),
	Color(0.95, 0.45, 0.13),
	Color(0.28, 0.76, 0.34),
	Color(0.88, 0.25, 0.55)
]

@export_group("walk recorder")
@export_range(0.0, 1.0, 0.01) var walk_highlight_alpha: float = 0.35
@export_range(0.0, 1.0, 0.01) var walk_preview_alpha: float = 0.8
@export var walk_highlight_outline_width: float = 3.0
@export_range(0.0, 1.0, 0.01) var walk_highlight_outline_darkening: float = 0.35
@export var recorded_walk_min_step_duration: float = 0.05
@export var recorded_walk_reference_z_index: int = 48
@export var recorded_walk_reference_width: float = 5.0
@export_range(0.0, 1.0, 0.01) var recorded_walk_reference_alpha: float = 0.45

@export_group("interaction")
@export var anchor_click_radius_factor: float = 0.45
@export var node_click_radius_multiplier: float = 2.0

@export_group("triangles")
#@export var triangle_color: Color = Color.WHITE
@export var hex_size: float = 56.0  

@export_group("lines")
@export var line_color: Color = Color.BLACK
@export var line_width: float = 1.0

@export var start_pos: Vector2 = Vector2(250,60)
@export var offset:  int = 100
@export var bpm = 120

@export_group("lsystems")
@export var number_iterations: int = 3
@export var max_rule_length: int = 5
@export var placement_probability : float = 0.7

@export_range(0.5, 1.0, 0.01) 
var triangle_scale: float = 0.72  # Shrink triangles away from the notes
@export var base_note: int = 12
@export var trail_color: Color = Color.DARK_SLATE_GRAY
	
