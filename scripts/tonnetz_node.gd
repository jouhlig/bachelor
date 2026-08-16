extends Node2D
class_name TonnetzNode

# class for a single node in the Tonnetz
#representing a pitch class and its position

@export var q: int
@export var r: int
@export var s: int
@export var pitch: int
@export var note_name: String
@export var octave: int
var neighbors := {}
var selected := false

@onready var config: TonnetzConfig = Config.config

func _ready():
	# match the same lattice basis vectors used in TonnetzBuilder:
	# (q, r) -> q * (0.5, 0.866) + r * (-0.5, 0.866)
	var x = config.offset * 0.5 * float(q - r)
	var y = config.offset * 0.866 * float(q + r)

	position = config.start_pos + Vector2(x, y)
	#collision is no longer used; notes are triggered by Sequencer events.
	
	note_name = _pitch_to_name(pitch)
	octave = _pitch_to_octave(pitch)

	# Visual
	queue_redraw()
	#mesh_inst.z_index = 1  # Notes above triangles
	#add_child(mesh_inst)

func _draw() -> void:
	var border_radius := config.note_radius + config.outline_width
	var fill_color := config.note_border_color if selected else config.note_color
	draw_circle(Vector2.ZERO, border_radius, config.note_border_color, true, -1.0, true)
	draw_circle(Vector2.ZERO, config.note_radius, fill_color, true, -1.0, true)
	_draw_note_label()

func _draw_note_label() -> void:
	var note_font_size: int = config.node_note_font_size
	var octave_font_size: int = config.node_octave_font_size
	var octave_text := str(octave)
	var note_size: Vector2 = config.font.get_string_size(note_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, note_font_size)
	var octave_size: Vector2 = config.font.get_string_size(octave_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, octave_font_size)
	var total_width: float = note_size.x + octave_size.x
	var baseline := Vector2(-total_width * 0.5 + 1.0, 3.0)

	draw_string(
		config.font,
		baseline,
		note_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		note_font_size,
		Color.WHITE if selected else config.note_label_color
	)
	draw_string(
		config.font,
		baseline + Vector2(note_size.x, 3.0),
		octave_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		octave_font_size,
		Color.WHITE if selected else config.note_label_color
	)

func get_center() -> Vector2:
	return global_position

func set_selected(new_selected: bool) -> void:
	selected = new_selected
	queue_redraw()
	
func get_next(direction: Vector2i)-> TonnetzNode:
	return neighbors.get(direction)

func _pitch_to_name(value: int) -> String:
	return config.NOTE_NAMES[posmod(value, 12)]

func _pitch_to_octave(value: int) -> int:
	return floori(float(value) / 12.0)
