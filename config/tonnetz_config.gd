extends Resource
class_name TonnetzConfig

const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const TONNETZ_VIEWPORT_TILING_RADIUS := 1
@export var column_count: int = 12
@export var row_count: int = 10
@export var font = load("res://fonts/Rubik-VariableFont_wght.ttf")

@export_group("notes")
@export var note_color: Color = Color(0.955, 0.925, 0.855, 1.0)
@export var note_label_color: Color = Color(0.760, 0.752, 0.716, 1.0)
@export var note_border_color: Color = Color(0.955, 0.925, 0.855, 1.0)
@export var note_radius: float = 12

#@export var background_color: Color = Color.WHITE
@export var outline_width: float = 1.0

@export_group("ui")
@export var ui_panel_color: Color = Color(0.810, 0.801, 0.777, 1.0)
@export var ui_panel_border_color: Color = Color(0.561, 0.559, 0.431, 1.0)
@export var ui_text_color: Color = Color(0.235, 0.278, 0.176, 1.0)
@export var ui_muted_color: Color = Color(0.682, 0.702, 0.580, 1.0)
@export var ui_input_color: Color = Color(0.882, 0.861, 0.816, 1.0)
@export var ui_input_focus_color: Color = Color(0.914, 0.886, 0.824, 1.0)
@export var ui_selection_color: Color = Color(0.867, 0.631, 0.573, 0.36)
@export var tonnetz_background_color: Color = Color(0.760, 0.752, 0.716, 1.0)
@export var tonnetz_border_color: Color = Color(0.955, 0.925, 0.855, 1.0)

@export_group("turtle")
@export var player_radius: float = 12.0
@export_range(0.0, 0.45, 0.01) var turtle_speed_variation: float = 0.06
@export var turtle_speed_variation_phase: float = 0.35
@export var trail_dot_radius: float = 4.0
@export var turtle_trail_max_points: int = 12
@export var turtle_trail_prune_update_interval: float = 0.1
@export var VOICE_COLORS : Array[Color]= [
	Color(0.537, 0.628, 0.275),
	Color(0.682, 0.702, 0.580),
	Color(0.690, 0.765, 0.365),
	Color(0.737, 0.431, 0.369),
	Color(0.867, 0.631, 0.573),
	Color(0.561, 0.559, 0.431),
	Color(0.706, 0.769, 0.424),
	Color(0.757, 0.769, 0.600)
]

@export_group("walk recorder")
@export_range(0.0, 1.0, 0.01) var walk_highlight_alpha: float = 0.35
@export_range(0.0, 1.0, 0.01) var walk_preview_alpha: float = 0.8
@export var recorded_walk_min_step_duration: float = 0.05
@export var recorded_walk_reference_z_index: int = 48
@export var recorded_walk_reference_width: float = 5.0
@export_range(0.0, 1.0, 0.01) var recorded_walk_reference_alpha: float = 0.45

@export_group("interaction")
@export var anchor_click_radius_factor: float = 0.45
@export var node_click_radius_multiplier: float = 2.0

@export_group("triangles")
#@export var triangle_color: Color = Color.WHITE

@export_group("lines")
@export var line_color: Color = Color(0.955, 0.925, 0.855, 1.0)
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
@export var base_midi_note: int = 24
	
