extends Area2D
class_name TonnetzNode

@export var q: int
@export var r: int
@export var s: int
@export var pitch: int
@export var note_name: String
@export var octave: int

@export var config: TonnetzConfig
const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

func _ready():
	if not config:
		print("No Tonnetz Config File selected for TonnetzNode")
		scale = Vector2.ZERO
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	
	# Erst wachsen (Overshoot)
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.15)
	
	# Dann zurück zur normalen Größe
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)

	# Match the same lattice basis vectors used in TonnetzBuilder:
	# (q, r) -> q * (0.5, 0.866) + r * (-0.5, 0.866)
	var x = config.offset * 0.5 * float(q - r)
	var y = config.offset * 0.866 * float(q + r)
	
	#print(x)
	#print(y)

	position = config.start_pos + Vector2(x, y)
	#print("actual position:", position)
	# Collision
	var shape = CircleShape2D.new()
	shape.radius = config.note_radius
	var coll = CollisionShape2D.new()
	coll.shape = shape
	add_child(coll)
	
	# Visual
	queue_redraw()
	#mesh_inst.z_index = 1  # Notes above triangles
	#add_child(mesh_inst)
	
	note_name = NOTE_NAMES[pitch%12]
	octave = floor(pitch/12)
	_add_note_label()
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Set collision layer and mask
	collision_layer = 2
	collision_mask = 1  # Detect player

func _add_note_label() -> void:
	var label = Label.new()
	label.text = note_name + "," +str(pitch) + ","+ str(octave)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 2
	
	var label_size = Vector2(config.note_radius * 3.0, config.note_radius * 2.0)
	label.position = Vector2(-label_size.x / 2.0, -label_size.y / 2.0)
	label.size = label_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	var label_settings = LabelSettings.new()
	label_settings.font_size = int(max(12.0, config.note_radius * 0.9))
	label_settings.font_color = config.note_label_color
	#label_settings.outline_size = 2
	#label_settings.outline_color = config.note_label_outline_color
	label.label_settings = label_settings
	
	add_child(label)

func _on_body_entered(body):
	if body is CharacterBody2D:
		if body.has_method("should_play_node_audio") and not body.should_play_node_audio():
			return
		#print("Entered note pitch: ", pitch)
		AM.play_notes([self])

func _on_body_exited(body):
	if body is CharacterBody2D:
		if body.has_method("should_play_node_audio") and not body.should_play_node_audio():
			return
		#print("Exited note pitch: ", pitch)
		#AM.stop_note(pitch)

func get_center() -> Vector2:
	return global_position
	
func _draw():
	draw_circle(Vector2.ZERO, config.note_radius + config.note_outline_width, config.note_border_color)
	draw_circle(Vector2.ZERO, config.note_radius, config.note_color)
