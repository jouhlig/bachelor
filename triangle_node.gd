extends Area2D
class_name TriangleArea

var nodes: Array[TonnetzNode] = []
@export var config: TonnetzConfig

func set_nodes(node_array: Array[TonnetzNode]):
	if not config:
		config = TonnetzConfig.new()
	nodes = node_array
	
	# Compute average position
	var avg_pos = Vector2.ZERO
	for n in nodes:
		avg_pos += n.position
	avg_pos /= 3
	position = avg_pos
	
	# Compute relative points and shrink triangle slightly toward its center
	var points = PackedVector2Array()
	for n in nodes:
		points.append((n.position - position) * config.triangle_scale)
	
	# Collision
	var coll = CollisionPolygon2D.new()
	coll.polygon = points
	add_child(coll)
	
	# Visual
	var vis = Polygon2D.new()
	vis.polygon = points
	vis.z_index = 0
	var pitch_sum = 0
	for n in nodes:
		pitch_sum += n.pitch
	var hue = float(pitch_sum % 12) / 12.0
	var fill_color = Color.from_hsv(hue, 0.7, 0.9)
	vis.color = fill_color
	add_child(vis)
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Set collision layer and mask
	collision_layer = 3
	collision_mask = 1  # Detect player

func _on_body_entered(body):
	if body is CharacterBody2D:
		var pitches: Array[int] = []
		for n in nodes:
			pitches.append(n.pitch)
		print("Triangle pitches: ", pitches)
		AM.play_notes(pitches)

func _on_body_exited(body):
	if body is CharacterBody2D:
		print("Exited triangle")
		for n in nodes:
			AM.stop_note(n.pitch)
