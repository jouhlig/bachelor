extends Area2D
class_name TonnetzNode

@export var q: int
@export var r: int
@export var pitch: int
@export var config: TonnetzConfig

func _ready():
	if not config:
		config = TonnetzConfig.new()
	position = config.hex_to_world(q, r)
	
	# Collision
	var shape = CircleShape2D.new()
	shape.radius = config.note_radius
	var coll = CollisionShape2D.new()
	coll.shape = shape
	add_child(coll)
	
	# Visual
	var mesh_inst = MeshInstance2D.new()
	var sphere = SphereMesh.new()
	sphere.radius = config.note_radius
	sphere.height = config.note_radius * 2
	mesh_inst.mesh = sphere
	mesh_inst.modulate = config.note_color
	mesh_inst.z_index = 1  # Notes above triangles
	add_child(mesh_inst)
	
	_add_note_label()
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Set collision layer and mask
	collision_layer = 2
	collision_mask = 1  # Detect player

func _add_note_label() -> void:
	var label = Label.new()
	label.text = config.pitch_class_to_name(pitch)
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
		print("Entered note pitch: ", pitch)
		AM.play_notes([pitch])

func _on_body_exited(body):
	if body is CharacterBody2D:
		print("Exited note pitch: ", pitch)
		AM.stop_note(pitch)

func get_center() -> Vector2:
	return global_position
