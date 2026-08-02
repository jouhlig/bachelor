extends Area2D
class_name TonnetzNode

@export var q: int
@export var r: int
@export var s: int
@export var pitch: int
@export var note_name: String
@export var octave: int
var neighbors := {}
var note_label: Label
var hovered := false

@onready var config: TonnetzConfig = Config.config
@onready var builder : TonnetzBuilder = get_node("/root/Game/UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld/TonnetzBuilder")

func _ready():
	
	
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
	note_name = _pitch_to_name(pitch)
	octave = _pitch_to_octave(pitch)
	_add_note_label()
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# Set collision layer and mask
	collision_layer = 2
	collision_mask = 1  # Detect player

func _add_note_label() -> void:
	var label = Label.new()
	label.text = note_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 2
	note_label = label
	
	var label_size = Vector2(config.note_radius * 2.0, config.note_radius * 2.0)
	label.position = Vector2(-label_size.x / 2.0, -label_size.y / 2.0)
	label.size = label_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var fv = FontVariation.new()
	fv.base_font = config.font

	fv.variation_opentype = {
		"weight": 300
	}
	var label_settings = LabelSettings.new()
	label_settings.font_size = 13
	label_settings.font_color = config.note_label_color
	label_settings.font = fv

	#label_settings.outline_size = 2
	#label_settings.outline_color = config.note_label_outline_color
	label.label_settings = label_settings
	label.visible = false
	
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
	if not hovered:
		return

	var points := PackedVector2Array()
	var radius := config.note_radius + 9.0

	for index in range(6):
		var angle := PI / 6.0 + TAU * float(index) / 6.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	var fill_color: Color = config.note_color.lightened(0.2)
	fill_color.a = 0.24
	var border_color: Color = config.note_border_color.lightened(0.15)
	border_color.a = 0.95
	draw_colored_polygon(points, fill_color)

	for index in range(points.size()):
		draw_line(points[index], points[(index + 1) % points.size()], border_color, 2.0, true)

func _on_mouse_entered() -> void:
	hovered = true
	if note_label:
		note_label.visible = true
		note_label.scale = Vector2(1.25, 1.25)
	queue_redraw()

func _on_mouse_exited() -> void:
	hovered = false
	if note_label:
		note_label.visible = false
		note_label.scale = Vector2.ONE
	queue_redraw()
	
func get_next(direction: Vector2i)-> TonnetzNode:
	return neighbors.get(direction)

func _pitch_to_name(value: int) -> String:
	return config.NOTE_NAMES[posmod(value, 12)]

func _pitch_to_octave(value: int) -> int:
	return floori(float(value) / 12.0)
